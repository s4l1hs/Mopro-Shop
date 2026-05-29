package orderledger

import (
	"context"
	"errors"
	"fmt"
	"log/slog"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/commission"
	"github.com/mopro/platform/internal/ledger"
	"github.com/mopro/platform/pkg/metrics"
)

type captureService struct {
	repo     Repository
	recorder commission.CaptureRecorder
	wallet   WalletPoster
	log      *slog.Logger
	biz      *metrics.BusinessMetrics // nil disables business KPI counters
}

// NewService constructs a Service.
//
// `recorder` is the commission-owned seam for persisting capture_postings
// audit rows — orderledger no longer reaches into commission_schema
// directly. wallet is satisfied by wallet.Service (injected from
// fin-svc/main.go). biz is optional (nil disables business KPI metrics).
func NewService(repo Repository, recorder commission.CaptureRecorder, wallet WalletPoster, log *slog.Logger, biz *metrics.BusinessMetrics) Service {
	if log == nil {
		log = slog.Default()
	}
	return &captureService{repo: repo, recorder: recorder, wallet: wallet, log: log, biz: biz}
}

// PostCapture posts the 4-or-5-entry balanced ledger transaction for a PSP
// capture and writes the capture_postings audit row (owned by the
// commission package via commission.CaptureRecorder) atomically in a
// SERIALIZABLE transaction.
//
// Idempotency layers:
//  1. Pre-check: recorder.FindCapturePostingByOrderID returns early if the
//     audit row exists.
//  2. UNIQUE(order_id) on capture_postings: commission.ErrAlreadyPosted on
//     concurrent retry.
//  3. wallet.PostInTx idempotency key: UNIQUE transactions.idempotency_key.
func (s *captureService) PostCapture(ctx context.Context, ev OrderPaidEvent) error { //nolint:gocyclo // double-entry capture with idempotency; complexity is inherent
	// Fast idempotency check before starting an expensive SERIALIZABLE tx.
	existing, err := s.recorder.FindCapturePostingByOrderID(ctx, ev.OrderID)
	if err != nil {
		return fmt.Errorf("orderledger: idempotency check order=%d: %w", ev.OrderID, err)
	}
	if existing != nil {
		s.log.InfoContext(ctx, "orderledger: capture already posted, skipping",
			"order_id", ev.OrderID,
			"transaction_id", existing.TransactionID,
		)
		return nil
	}

	in := Aggregate(ev)
	entries, err := Compute(in)
	if err != nil {
		return fmt.Errorf("orderledger: compute entries order=%d: %w", ev.OrderID, err)
	}

	// Resolve account IDs (reads from pool, no tx needed).
	pspReceivableID, err := s.wallet.FindAccount(ctx, "asset:psp_receivable", ev.Currency)
	if err != nil {
		return fmt.Errorf("orderledger: find psp_receivable account: %w", err)
	}
	retainedCommissionID, err := s.wallet.FindAccount(ctx, "equity:retained_commission", ev.Currency)
	if err != nil {
		return fmt.Errorf("orderledger: find retained_commission account: %w", err)
	}
	kdvPayableID, err := s.wallet.FindAccount(ctx, "liability:kdv_payable", ev.Currency)
	if err != nil {
		return fmt.Errorf("orderledger: find kdv_payable account: %w", err)
	}
	sellerPayableID, err := s.wallet.FindOrOpenSellerPayable(ctx, ev.SellerID, ev.Currency)
	if err != nil {
		return fmt.Errorf("orderledger: find seller_payable seller=%d: %w", ev.SellerID, err)
	}

	// Build account ID lookup by account type for the loop below.
	platformAccounts := map[string]int64{
		"asset:psp_receivable":       pspReceivableID,
		"equity:retained_commission": retainedCommissionID,
		"liability:kdv_payable":      kdvPayableID,
	}

	// Optionally resolve shipping_payable if a shipping line is present.
	var shippingPayableID int64
	for _, l := range entries.Lines {
		if l.AccountType == "liability:shipping_payable" {
			shippingPayableID, err = s.wallet.FindAccount(ctx, "liability:shipping_payable", ev.Currency)
			if err != nil {
				return fmt.Errorf("orderledger: find shipping_payable account: %w", err)
			}
			platformAccounts["liability:shipping_payable"] = shippingPayableID
			break
		}
	}

	// Map LedgerLines to ledger.Entry values.
	lentries := make([]ledger.Entry, 0, len(entries.Lines))
	for _, l := range entries.Lines {
		var acctID int64
		if l.AccountType == "liability:seller_payable" {
			acctID = sellerPayableID
		} else {
			acctID = platformAccounts[l.AccountType]
		}
		dir := ledger.Debit
		if l.Direction == "C" {
			dir = ledger.Credit
		}
		lentries = append(lentries, ledger.Entry{
			AccountID:   acctID,
			Direction:   dir,
			AmountMinor: l.AmountMinor,
		})
	}

	idemKey := fmt.Sprintf("order:capture:order_%d", ev.OrderID)
	postIn := ledger.PostInput{
		Type:           "order_capture",
		Reference:      fmt.Sprintf("order:%d:psp_capture", ev.OrderID),
		IdempotencyKey: idemKey,
		Market:         ev.Market,
		Currency:       ev.Currency,
		Entries:        lentries,
		Metadata: map[string]string{
			"order_id":  fmt.Sprintf("%d", ev.OrderID),
			"seller_id": fmt.Sprintf("%d", ev.SellerID),
		},
	}

	var txnID int64
	err = s.repo.WithTx(ctx, pgx.Serializable, func(tx pgx.Tx) error {
		var innerErr error
		txnID, innerErr = s.wallet.PostInTx(ctx, tx, postIn)
		if innerErr != nil {
			return fmt.Errorf("orderledger: PostInTx order=%d: %w", ev.OrderID, innerErr)
		}

		posting := commission.CapturePosting{
			OrderID:         ev.OrderID,
			TransactionID:   txnID,
			IdempotencyKey:  idemKey,
			GrossMinor:      in.GrossMinor,
			SellerNetMinor:  in.SellerNetMinor,
			CommissionMinor: in.CommissionMinor,
			KdvMinor:        in.KdvMinor,
			ShippingMinor:   in.ShippingMinor,
			Currency:        ev.Currency,
			Market:          ev.Market,
		}
		if insertErr := s.recorder.InsertCapturePosting(ctx, tx, posting); insertErr != nil {
			if errors.Is(insertErr, commission.ErrAlreadyPosted) {
				// Concurrent retry committed before us — the ledger tx above also
				// hit its idempotency guard, so returning nil is safe.
				return nil
			}
			return insertErr
		}
		return nil
	})
	if err != nil {
		return err
	}

	s.log.InfoContext(ctx, "orderledger: capture posted",
		"order_id", ev.OrderID,
		"seller_id", ev.SellerID,
		"gross_minor", in.GrossMinor,
		"transaction_id", txnID,
	)
	s.biz.IncOrderLedgerPosting("fin-svc", ev.Market)
	return nil
}
