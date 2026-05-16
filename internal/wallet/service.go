package wallet

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
	"github.com/mopro/platform/internal/outbox"
)

type walletService struct {
	repo       Repository
	outboxRepo outbox.Repository
	log        *slog.Logger
}

// NewService constructs a Service. repo and outboxRepo are wired by fin-svc/main.go
// at startup; no globals or service-locator patterns. A nil log falls back to slog.Default().
func NewService(repo Repository, outboxRepo outbox.Repository, log *slog.Logger) Service {
	if log == nil {
		log = slog.Default()
	}
	return &walletService{repo: repo, outboxRepo: outboxRepo, log: log}
}

// Post starts its own SERIALIZABLE transaction and delegates to PostInTx.
func (s *walletService) Post(ctx context.Context, in ledger.PostInput) (int64, error) {
	var txnID int64
	err := s.repo.WithTx(ctx, pgx.Serializable, func(tx pgx.Tx) error {
		var innerErr error
		txnID, innerErr = s.PostInTx(ctx, tx, in)
		return innerErr
	})
	return txnID, err
}

// PostInTx joins the caller's existing transaction.
// Three-layer idempotency:
//  1. Service: validates IdempotencyKey is non-empty before touching DB.
//  2. DB UNIQUE: InsertTransaction hits unique constraint on re-apply → ErrDuplicateIdempotency.
//  3. Service: intercepts ErrDuplicateIdempotency, looks up + returns original txnID.
//
// Defensive currency check: queries all entry account currencies from pool and
// rejects with ErrCurrencyMismatch before any write if they diverge from in.Currency.
func (s *walletService) PostInTx(ctx context.Context, tx pgx.Tx, in ledger.PostInput) (int64, error) {
	// ── 1. Validation ────────────────────────────────────────────────────────
	if in.IdempotencyKey == "" {
		return 0, ErrIdempotencyKeyRequired
	}
	if in.Currency == "" {
		return 0, ErrCurrencyRequired
	}
	if len(in.Entries) < 2 {
		return 0, fmt.Errorf("%w: need at least 2 entries, got %d", ErrInvalidAmount, len(in.Entries))
	}
	for i, e := range in.Entries {
		if e.AmountMinor <= 0 {
			return 0, fmt.Errorf("%w: entry[%d] amount_minor=%d must be >0", ErrInvalidAmount, i, e.AmountMinor)
		}
		if e.Direction != ledger.Debit && e.Direction != ledger.Credit {
			return 0, fmt.Errorf("%w: entry[%d] direction=%q invalid", ErrInvalidAmount, i, e.Direction)
		}
	}

	// ── 2. Defensive currency check (belt-and-suspenders over DB trigger) ───
	acctIDs := make([]int64, len(in.Entries))
	for i, e := range in.Entries {
		acctIDs[i] = e.AccountID
	}
	currencies, err := s.repo.GetAccountCurrencies(ctx, acctIDs)
	if err != nil {
		return 0, fmt.Errorf("wallet: get account currencies: %w", err)
	}
	for _, id := range acctIDs {
		cur, ok := currencies[id]
		if !ok {
			return 0, fmt.Errorf("%w: account %d not found", ErrAccountNotFound, id)
		}
		if cur != in.Currency {
			return 0, fmt.Errorf("%w: account %d has currency %s, PostInput.Currency=%s",
				ErrCurrencyMismatch, id, cur, in.Currency)
		}
	}

	// ── 3. Insert transaction row (idempotency dedup at DB level) ────────────
	txnID, err := s.repo.InsertTransaction(ctx, tx, ledger.Transaction{
		Type:           in.Type,
		Reference:      in.Reference,
		FxPairID:       in.FxPairID,
		IdempotencyKey: in.IdempotencyKey,
	})
	if errors.Is(err, ledger.ErrDuplicateIdempotency) {
		// Already applied in a prior call. Return the original txnID silently.
		existing, lookupErr := s.repo.GetTransactionByIdempotencyKey(ctx, in.IdempotencyKey)
		if lookupErr != nil {
			return 0, fmt.Errorf("wallet: idempotency lookup: %w", lookupErr)
		}
		s.log.InfoContext(ctx, "wallet: idempotent replay",
			"idempotency_key", in.IdempotencyKey, "txn_id", existing)
		return existing, nil
		// Return here: do NOT re-insert entries or outbox (they already exist).
	}
	if err != nil {
		return 0, err
	}

	// ── 4. Insert ledger entries (ALL D and C in this tx before COMMIT) ──────
	// The DEFERRABLE INITIALLY DEFERRED trigger fires at COMMIT and validates
	// per-currency D=C. All entries MUST be inserted before the caller commits.
	for _, e := range in.Entries {
		if err := s.repo.InsertEntry(ctx, tx, txnID, e); err != nil {
			return 0, err
		}
	}

	// ── 5. Insert outbox row in the SAME tx ──────────────────────────────────
	// If Insert fails → entire tx rolls back → no ledger entries persist → correct.
	payload, err := json.Marshal(in)
	if err != nil {
		return 0, fmt.Errorf("wallet: marshal outbox payload: %w", err)
	}
	eventType := outboxEventType(in.Type)
	if in.EventType != "" {
		eventType = in.EventType
	}
	outboxRow := outbox.Row{
		Aggregate:      outboxAggregate(in.Type),
		EventType:      eventType,
		Payload:        json.RawMessage(payload),
		IdempotencyKey: in.IdempotencyKey,
		Market:         in.Market,
		Currency:       in.Currency,
		// TraceID / SpanID populated by OTel wiring in Phase 2.x.
	}
	if err := s.outboxRepo.Insert(ctx, tx, outboxRow); err != nil {
		// outbox.ErrDuplicateIdempotency here means the outbox row already exists
		// (committed by the original tx). Treat as success — we already returned
		// the txnID from the dedup path above, so this branch is unreachable in
		// normal operation but guarded for safety.
		if !errors.Is(err, outbox.ErrDuplicateIdempotency) {
			return 0, fmt.Errorf("wallet: insert outbox: %w", err)
		}
	}

	return txnID, nil
}

// GetBalance reads from the materialized view (fast, stale ≤ refresh interval).
func (s *walletService) GetBalance(ctx context.Context, accountID int64) (int64, error) {
	return s.repo.GetBalanceMV(ctx, accountID)
}

// GetBalanceStrict computes live balance. Phase 3 withdrawal paths only.
func (s *walletService) GetBalanceStrict(ctx context.Context, accountID int64) (int64, error) {
	return s.repo.GetBalanceStrict(ctx, accountID)
}

// FindAccount looks up a platform account by (type, currency).
func (s *walletService) FindAccount(ctx context.Context, accountType, currency string) (int64, error) {
	acct, err := s.repo.FindAccountByType(ctx, accountType, currency)
	if err != nil {
		return 0, err
	}
	return acct.ID, nil
}

// OpenOrFindUserWallet returns the user's coin wallet account ID, creating it lazily.
// type = 'liability:wallet:user', owner_type = 'user'.
func (s *walletService) OpenOrFindUserWallet(ctx context.Context, userID int64, currency string) (int64, error) {
	return s.openOrFind(ctx, "liability:wallet:user", "user", userID, currency)
}

// FindOrOpenSellerPayable returns the seller's fiat payable account ID, creating it lazily.
// type = 'liability:payable:seller', owner_type = 'seller'.
func (s *walletService) FindOrOpenSellerPayable(ctx context.Context, sellerID int64, currency string) (int64, error) {
	return s.openOrFind(ctx, "liability:payable:seller", "seller", sellerID, currency)
}

// openOrFind is the shared lazy-create pattern used by OpenOrFindUserWallet and
// FindOrOpenSellerPayable. Thread-safe via ON CONFLICT accounts_owner_currency_uq.
func (s *walletService) openOrFind(ctx context.Context, accountType, ownerType string, ownerID int64, currency string) (int64, error) {
	// Fast path: account already exists.
	acct, err := s.repo.FindAccountByOwner(ctx, ownerType, ownerID, currency)
	if err == nil {
		return acct.ID, nil
	}
	if !errors.Is(err, ErrAccountNotFound) {
		return 0, err
	}

	// Slow path: first time for this (ownerType, ownerID, currency) — create lazily.
	// Use READ COMMITTED for account creation; the UNIQUE index + DO NOTHING make it safe.
	ownerIDCopy := ownerID
	newAcct := Account{
		Type:      accountType,
		OwnerType: ownerType,
		OwnerID:   &ownerIDCopy,
		Currency:  currency,
		Status:    "active",
	}
	var newID int64
	if insertErr := s.repo.WithTx(ctx, pgx.ReadCommitted, func(tx pgx.Tx) error {
		id, err := s.repo.InsertAccount(ctx, tx, newAcct)
		if err != nil {
			return err
		}
		newID = id
		return nil
	}); insertErr != nil {
		return 0, insertErr
	}

	if newID > 0 {
		return newID, nil // we created it
	}

	// Another goroutine won the race (ON CONFLICT → 0 returned). Re-read the winner's row.
	acct, err = s.repo.FindAccountByOwner(ctx, ownerType, ownerID, currency)
	if err != nil {
		return 0, fmt.Errorf("wallet: re-read after conflict: %w", err)
	}
	return acct.ID, nil
}

// outboxAggregate maps a transaction type to the outbox aggregate name.
func outboxAggregate(txType string) string {
	switch txType {
	case "cashback_payment", "cashback_reversal":
		return "cashback"
	case "seller_payout":
		return "sellerpayout"
	case "commission_accrual":
		return "commission"
	case "fx_outbound", "fx_inbound":
		return "treasury"
	default:
		return "wallet"
	}
}

// outboxEventType maps a transaction type to the canonical Redis Streams event type.
func outboxEventType(txType string) string {
	switch txType {
	case "cashback_payment":
		return "fin.cashback.payment.posted.v1"
	case "cashback_reversal":
		return "fin.cashback.reversal.posted.v1"
	case "seller_payout":
		return "fin.seller.payout.posted.v1"
	case "commission_accrual":
		return "fin.commission.accrual.posted.v1"
	case "fx_outbound":
		return "fin.fx.outbound.posted.v1"
	case "fx_inbound":
		return "fin.fx.inbound.posted.v1"
	default:
		return "fin.ledger.posted.v1"
	}
}
