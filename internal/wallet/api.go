// Package wallet owns the double-entry ledger I/O and balance API (fin-svc).
// All financial writes MUST go through wallet.Service.Post or wallet.Service.PostInTx.
// No other fin-svc module may INSERT directly into wallet_schema.transactions or
// wallet_schema.ledger_entries.
package wallet

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
)

// SystemState is the singleton read-only flag row from wallet_schema.system_state.
type SystemState struct {
	ReadOnly       bool
	ReadOnlyReason string     // empty when ReadOnly=false
	ReadOnlySince  *time.Time // nil when ReadOnly=false
}

// Service defines the public interface of the wallet module.
// cashback and sellerpayout MUST call only these methods; they must NEVER
// import or call walletRepository directly (enforced by depguard).
type Service interface {
	// Post starts its own SERIALIZABLE transaction, applies all entries, inserts an
	// outbox row, and commits. Use when the caller has no outer DB transaction.
	Post(ctx context.Context, in ledger.PostInput) (txnID int64, err error)

	// PostInTx joins the caller's existing transaction. Use when the ledger write
	// must commit atomically with other domain writes (e.g. cashback MarkPaid,
	// sellerpayout MarkProcessing). The caller is responsible for COMMIT/ROLLBACK.
	PostInTx(ctx context.Context, tx pgx.Tx, in ledger.PostInput) (txnID int64, err error)

	// GetBalance returns balance_minor from the wallet_schema.balances materialized
	// view. Stale by up to WALLET_BALANCE_REFRESH_INTERVAL (default 1h). Use for
	// display-only paths (mobile app, seller dashboard). Returns 0 for new accounts
	// not yet in the MV.
	GetBalance(ctx context.Context, accountID int64) (int64, error)

	// GetBalanceStrict computes balance live from wallet_schema.ledger_entries.
	// Use only for withdrawal authorization paths (Phase 3+). Never cache the result.
	GetBalanceStrict(ctx context.Context, accountID int64) (int64, error)

	// FindAccount looks up a platform account by (type, currency).
	// Returns ErrAccountNotFound if no match.
	FindAccount(ctx context.Context, accountType, currency string) (int64, error)

	// OpenOrFindUserWallet returns the accountID of the user's coin wallet for
	// the given currency. Creates it lazily if it does not exist (race-safe via
	// ON CONFLICT accounts_owner_currency_uq DO NOTHING).
	OpenOrFindUserWallet(ctx context.Context, userID int64, currency string) (int64, error)

	// FindOrOpenSellerPayable returns the accountID of the seller's fiat payable
	// account. Creates it lazily if it does not exist.
	FindOrOpenSellerPayable(ctx context.Context, sellerID int64, currency string) (int64, error)

	// FindAccountByOwnerAnyStatus looks up a per-entity account by (ownerType, ownerID, currency)
	// regardless of status. Returns (0, "", nil) when no row exists for the triple.
	// Returns (id, status, nil) when found. Use to distinguish "frozen" from "never created".
	FindAccountByOwnerAnyStatus(ctx context.Context, ownerType string, ownerID int64, currency string) (int64, string, error)

	// GetAccount fetches a wallet_schema.accounts row by primary key, regardless of
	// status. Returns ErrAccountNotFound if no row exists.
	GetAccount(ctx context.Context, accountID int64) (Account, error)

	// SetReadOnly marks the system as read-only. Writes to system_state and eagerly
	// updates the in-memory cache. Called by reconcile cron and mopro CLI.
	SetReadOnly(ctx context.Context, reason string) error

	// ClearReadOnly clears the read-only flag. Called by mopro CLI after human review.
	ClearReadOnly(ctx context.Context) error

	// InvalidateReadOnlyCache forces sysRefreshedAt to 0, causing the next PostInTx call
	// to re-read system_state from DB. Called by reconcile service after the WithTx
	// that writes system_state commits (so the eager cache update happens post-commit).
	InvalidateReadOnlyCache()

	// StartRefresher starts a background goroutine that refreshes the read-only cache
	// every 5 seconds. Must be called once from fin-svc/main.go after service construction.
	// No-op implementations satisfy test mocks.
	StartRefresher(ctx context.Context)

	// ListEntriesByAccount returns up to limit ledger entries for the given account,
	// ordered by id DESC. Pass beforeID > 0 to cursor-paginate (entries with id < beforeID).
	// Used by the HTTP wallet transaction list endpoint — read path only.
	ListEntriesByAccount(ctx context.Context, accountID int64, limit int, beforeID int64) ([]LedgerEntryRow, error)
}

// Repository defines the storage interface of the wallet module.
// Implementations MUST connect through PgBouncer (never direct to Postgres).
type Repository interface {
	// WithTx runs fn inside a transaction at level. Handles BEGIN, COMMIT, ROLLBACK,
	// and retries up to 3 times on pgError 40001 (serialization failure).
	WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(tx pgx.Tx) error) error

	// InsertTransaction inserts a wallet_schema.transactions row.
	// Returns (0, ledger.ErrDuplicateIdempotency) on UNIQUE(idempotency_key) violation.
	InsertTransaction(ctx context.Context, tx pgx.Tx, txn ledger.Transaction) (int64, error)

	// GetTransactionByIdempotencyKey fetches the id of an existing committed transaction.
	// Reads from the pool (not tx) to bypass snapshot isolation.
	GetTransactionByIdempotencyKey(ctx context.Context, key string) (int64, error)

	// InsertEntry inserts one wallet_schema.ledger_entries row.
	// The DEFERRABLE trigger fires at COMMIT — all D and C entries MUST be inserted
	// in the same tx before the caller commits.
	InsertEntry(ctx context.Context, tx pgx.Tx, txnID int64, e ledger.Entry) error

	// GetAccountCurrencies fetches the currency of each account in accountIDs.
	// Callers inside a WithTx block MUST pass the active tx — otherwise this
	// acquires a SECOND pool connection inside the transaction and can deadlock
	// when the pool budget is saturated (see CONTRIBUTING "Connection acquisition
	// inside transactions"; fix/cashback-pgxpool-deadlock). Pass nil outside a tx.
	// Returns a partial map if some IDs do not exist.
	GetAccountCurrencies(ctx context.Context, tx pgx.Tx, accountIDs []int64) (map[int64]string, error)

	// FindAccountByType looks up a platform account by (type, currency).
	// Hits the accounts_platform_type_currency_uq partial index.
	FindAccountByType(ctx context.Context, accountType, currency string) (Account, error)

	// FindAccountByOwner looks up a per-entity account by (ownerType, ownerID, currency).
	// Only returns accounts with status='active'.
	FindAccountByOwner(ctx context.Context, ownerType string, ownerID int64, currency string) (Account, error)

	// FindAccountByOwnerAnyStatus is like FindAccountByOwner but does NOT filter by
	// status. Returns ErrAccountNotFound if no row exists for the triple.
	// Use when the caller needs to distinguish between "frozen/suspended" (account
	// exists but not active) and "never created" (no row at all).
	FindAccountByOwnerAnyStatus(ctx context.Context, ownerType string, ownerID int64, currency string) (Account, error)

	// GetAccount fetches a wallet_schema.accounts row by primary key, regardless of
	// status. Returns ErrAccountNotFound if no row exists.
	GetAccount(ctx context.Context, accountID int64) (Account, error)

	// InsertAccount inserts a new accounts row. Returns (0, nil) when an
	// ON CONFLICT (accounts_owner_currency_uq) occurs so the caller can re-SELECT.
	InsertAccount(ctx context.Context, tx pgx.Tx, acct Account) (int64, error)

	// GetBalanceMV reads balance_minor from wallet_schema.balances (materialized view).
	// Returns 0 if the account is not yet in the MV (newly created).
	GetBalanceMV(ctx context.Context, accountID int64) (int64, error)

	// GetBalanceStrict computes live balance from wallet_schema.ledger_entries.
	GetBalanceStrict(ctx context.Context, accountID int64) (int64, error)

	// GetSystemState reads the singleton system_state row from the pool (not tx).
	// The seed row (id=1) always exists after migration 67; pgx.ErrNoRows is not expected.
	GetSystemState(ctx context.Context) (SystemState, error)

	// SetSystemState atomically sets read_only + reason + since in a single UPDATE WHERE id=1.
	// Accepts an optional pgx.Tx; if tx is nil, executes against the pool directly.
	// The tx parameter is required when the call must be atomic with other writes (OQ4).
	SetSystemState(ctx context.Context, tx pgx.Tx, readOnly bool, reason string) error

	// ListEntriesByAccount returns up to limit ledger entries for accountID, ordered
	// by id DESC. Pass beforeID > 0 to paginate (returns entries with id < beforeID).
	ListEntriesByAccount(ctx context.Context, accountID int64, limit int, beforeID int64) ([]LedgerEntryRow, error)
}
