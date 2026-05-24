package sellerpayout

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
)

const (
	dailyBatchSize = 200
	escrowAcctType = "asset:bank:escrow"
)

// runDailyPayouts is the core implementation of Service.RunDailyPayouts.
// It fetches all scheduled payouts due on payoutDate, groups them into per-seller
// batches, and processes each batch via the 3-phase sandwich:
//
//	Tx1 → PSP call → Tx2
func (s *payoutService) runDailyPayouts(ctx context.Context, payoutDate time.Time, market, currency string) (RunDailyResult, error) {
	result := RunDailyResult{PayoutDate: payoutDate, Currency: currency}

	// Resolve the escrow source account once.
	escrowAcctID, err := s.walletPoster.FindAccount(ctx, escrowAcctType, currency)
	if err != nil {
		return result, fmt.Errorf("sellerpayout: RunDailyPayouts find escrow account %s/%s: %w", escrowAcctType, currency, err)
	}

	// Fetch scheduled payouts in batches (SKIP LOCKED so concurrent runs don't overlap).
	for {
		payouts, err := s.repo.FetchScheduledPayouts(ctx, payoutDate, currency, dailyBatchSize)
		if err != nil {
			return result, fmt.Errorf("sellerpayout: FetchScheduledPayouts: %w", err)
		}
		if len(payouts) == 0 {
			break
		}

		// Group by seller_id → aggregate total.
		type batchAgg struct {
			payouts []Payout
			total   int64
		}
		bySellerID := make(map[int64]*batchAgg)
		for _, p := range payouts {
			agg := bySellerID[p.SellerID]
			if agg == nil {
				agg = &batchAgg{}
				bySellerID[p.SellerID] = agg
			}
			agg.payouts = append(agg.payouts, p)
			agg.total += p.AmountMinor
		}

		for sellerID, agg := range bySellerID {
			if err := s.processBatch(ctx, sellerID, agg.payouts, agg.total, payoutDate, market, currency, escrowAcctID, &result); err != nil {
				s.log.ErrorContext(ctx, "sellerpayout: processBatch error",
					"seller_id", sellerID,
					"payout_date", payoutDate.Format("2006-01-02"),
					"err", err,
				)
				result.Failed++
			}
		}

		if len(payouts) < dailyBatchSize {
			break
		}
	}

	return result, nil
}

// processBatch runs the 3-phase sandwich for a single (seller, payout_date, currency) batch.
func (s *payoutService) processBatch(
	ctx context.Context,
	sellerID int64,
	payouts []Payout,
	totalMinor int64,
	payoutDate time.Time,
	market, currency string,
	escrowAcctID int64,
	result *RunDailyResult,
) error {
	batchKey := batchIdempotencyKey(sellerID, payoutDate, currency)

	// ── Idempotency check: skip if batch already paid ──────────────────────────
	existing, err := s.repo.FindBatchByKey(ctx, batchKey)
	if err == nil {
		if existing.Status == BatchStatusPaid {
			result.Skipped++
			return nil
		}
		// Batch exists but not paid (processing/failed) — skip here, let reconcile handle it.
		result.Skipped++
		return nil
	}
	if err != ErrBatchNotFound {
		return fmt.Errorf("FindBatchByKey seller=%d: %w", sellerID, err)
	}

	// ── PSP lookup ─────────────────────────────────────────────────────────────
	pspAcc, err := s.repo.FindSellerPspAccount(ctx, sellerID)
	if err != nil {
		return fmt.Errorf("FindSellerPspAccount seller=%d: %w", sellerID, err)
	}

	// ── Seller payable account ─────────────────────────────────────────────────
	sellerPayableID, err := s.walletPoster.FindOrOpenSellerPayable(ctx, sellerID, currency)
	if err != nil {
		return fmt.Errorf("FindOrOpenSellerPayable seller=%d: %w", sellerID, err)
	}

	// ── Phase 1: Tx1 — create batch in 'processing' + link payout rows ─────────
	var batch PayoutBatch
	if err := s.repo.WithTx(ctx, pgx.ReadCommitted, func(tx pgx.Tx) error {
		b, insertErr := s.repo.InsertBatch(ctx, tx, PayoutBatch{
			SellerID:         sellerID,
			Currency:         currency,
			PayoutDate:       payoutDate,
			TotalAmountMinor: totalMinor,
			IdempotencyKey:   batchKey,
			Market:           market,
		})
		if insertErr != nil {
			return insertErr
		}
		batch = b

		for _, p := range payouts {
			if linkErr := s.repo.UpdatePayoutBatchID(ctx, tx, p.ID, batch.ID); linkErr != nil {
				return linkErr
			}
		}
		return nil
	}); err != nil {
		if err == ErrBatchAlreadyExists {
			result.Skipped++
			return nil
		}
		return fmt.Errorf("Tx1 seller=%d: %w", sellerID, err)
	}
	result.Batched++

	// ── Phase 2: PSP call (outside any transaction) ─────────────────────────────
	pspResp, pspErr := s.psp.Transfer(ctx, TransferRequest{
		BatchID:        batch.ID,
		PspMemberID:    pspAcc.PspMemberID,
		AmountMinor:    totalMinor,
		Currency:       currency,
		IdempotencyKey: batchKey,
		Market:         market,
	})

	// Store transfer_id immediately, even before Tx2 (enables reconcile on crash).
	if pspErr == nil && pspResp.TransferID != "" {
		if updateErr := s.repo.UpdateBatchPspTransferID(ctx, batch.ID, pspResp.TransferID); updateErr != nil {
			s.log.WarnContext(ctx, "sellerpayout: failed to store psp_transfer_id (non-fatal, reconcile will recover)",
				"batch_id", batch.ID,
				"err", updateErr,
			)
		}
	}

	if pspErr != nil {
		_ = s.repo.UpdateBatchStatus(ctx, batch.ID, BatchStatusFailed, pspErr.Error())
		return fmt.Errorf("PSP transfer seller=%d: %w", sellerID, pspErr)
	}

	// ── Phase 3: Tx2 — post ledger + mark paid ─────────────────────────────────
	if err := s.runTx2(ctx, batch.ID, pspResp.TransferID, sellerID, sellerPayableID, escrowAcctID, totalMinor, currency, market, batchKey, result); err != nil {
		// Don't mark failed here — reconcile will retry Tx2 using the stored psp_transfer_id.
		s.log.ErrorContext(ctx, "sellerpayout: Tx2 failed; will be retried by reconcile",
			"batch_id", batch.ID,
			"err", err,
		)
		return err
	}
	return nil
}

// runTx2 posts the ledger move and marks the batch paid.
// Called from both processBatch and reconcileProcessing.
func (s *payoutService) runTx2(
	ctx context.Context,
	batchID int64,
	pspTransferID string,
	sellerID, sellerPayableID, escrowAcctID int64,
	totalMinor int64,
	currency, market, batchKey string,
	result *RunDailyResult,
) error {
	// Check for open fraud-hold alert before proceeding.
	hasAlert, err := s.repo.HasOpenAlertForBatch(ctx, batchID)
	if err != nil {
		return fmt.Errorf("HasOpenAlertForBatch batch=%d: %w", batchID, err)
	}
	if hasAlert {
		s.log.WarnContext(ctx, "sellerpayout: fraud hold alert open, skipping Tx2",
			"batch_id", batchID,
			"seller_id", sellerID,
		)
		if result != nil {
			result.Skipped++
		}
		return nil
	}

	now := time.Now().UTC()
	return s.repo.WithTx(ctx, pgx.ReadCommitted, func(tx pgx.Tx) error {
		// D liability:seller_payable → C asset:bank:escrow
		// Paying OUT from escrow reduces the escrow asset (credit) and settles the liability (debit).
		postIn := ledger.PostInput{
			Type:           "seller_payout",
			IdempotencyKey: batchKey,
			Market:         market,
			Currency:       currency,
			EventType:      "fin.seller.payout.batch.paid.v1",
			Metadata: map[string]string{
				"batch_id":  strconv.FormatInt(batchID, 10),
				"seller_id": strconv.FormatInt(sellerID, 10),
			},
			Entries: []ledger.Entry{
				{AccountID: sellerPayableID, Direction: ledger.Debit, AmountMinor: totalMinor},
				{AccountID: escrowAcctID, Direction: ledger.Credit, AmountMinor: totalMinor},
			},
		}
		ledgerTxnID, postErr := s.walletPoster.PostInTx(ctx, tx, postIn)
		if postErr != nil {
			return fmt.Errorf("PostInTx batch=%d: %w", batchID, postErr)
		}

		if markErr := s.repo.UpdateBatchPaid(ctx, tx, batchID, ledgerTxnID, pspTransferID, now); markErr != nil {
			return fmt.Errorf("UpdateBatchPaid batch=%d: %w", batchID, markErr)
		}
		if markErr := s.repo.MarkPayoutsPaidByBatch(ctx, tx, batchID); markErr != nil {
			return fmt.Errorf("MarkPayoutsPaidByBatch batch=%d: %w", batchID, markErr)
		}
		return nil
	})
}

// batchIdempotencyKey returns the canonical idempotency key for a payout batch.
func batchIdempotencyKey(sellerID int64, payoutDate time.Time, currency string) string {
	return fmt.Sprintf("payout:seller_%d:date_%s:ccy_%s",
		sellerID,
		payoutDate.Format("20060102"),
		currency,
	)
}
