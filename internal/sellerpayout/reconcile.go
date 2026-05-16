package sellerpayout

import (
	"context"
	"fmt"
)

// reconcileProcessing finds payout_batches stuck in 'processing' (crashed between
// PSP call and Tx2) and retries Tx2, or escalates to ambiguous.
func (s *payoutService) reconcileProcessing(ctx context.Context) error {
	batches, err := s.repo.FetchProcessingBatches(ctx)
	if err != nil {
		return fmt.Errorf("sellerpayout: FetchProcessingBatches: %w", err)
	}

	for _, b := range batches {
		if err := s.reconcileBatch(ctx, b); err != nil {
			s.log.ErrorContext(ctx, "sellerpayout: reconcileBatch error",
				"batch_id", b.ID,
				"seller_id", b.SellerID,
				"err", err,
			)
		}
	}
	return nil
}

func (s *payoutService) reconcileBatch(ctx context.Context, b PayoutBatch) error {
	s.log.InfoContext(ctx, "sellerpayout: reconciling stuck batch",
		"batch_id", b.ID,
		"seller_id", b.SellerID,
		"psp_transfer_id", b.PspTransferID,
	)

	var pspTransferID string

	if b.PspTransferID == "" {
		// PSP call never completed or transfer_id was not stored. Retry the call.
		pspAcc, err := s.repo.FindSellerPspAccount(ctx, b.SellerID)
		if err != nil {
			return fmt.Errorf("reconcile: FindSellerPspAccount batch=%d: %w", b.ID, err)
		}
		resp, err := s.psp.Transfer(ctx, TransferRequest{
			BatchID:        b.ID,
			PspMemberID:    pspAcc.PspMemberID,
			AmountMinor:    b.TotalAmountMinor,
			Currency:       b.Currency,
			IdempotencyKey: b.IdempotencyKey,
			Market:         b.Market,
		})
		if err != nil {
			_ = s.repo.UpdateBatchStatus(ctx, b.ID, BatchStatusFailed, err.Error())
			return fmt.Errorf("reconcile: PSP Transfer batch=%d: %w", b.ID, err)
		}
		pspTransferID = resp.TransferID
		_ = s.repo.UpdateBatchPspTransferID(ctx, b.ID, pspTransferID)
	} else {
		// transfer_id is stored; confirm status via GetTransferStatus.
		resp, err := s.psp.GetTransferStatus(ctx, b.PspTransferID)
		if err != nil {
			return fmt.Errorf("reconcile: GetTransferStatus batch=%d: %w", b.ID, err)
		}
		// Defensive: if the PSP returns a different transfer_id, the state is ambiguous.
		if resp.TransferID != "" && resp.TransferID != b.PspTransferID {
			s.log.ErrorContext(ctx, "sellerpayout: ambiguous transfer — PSP returned different transfer_id",
				"batch_id", b.ID,
				"stored_transfer_id", b.PspTransferID,
				"psp_transfer_id", resp.TransferID,
			)
			alertMsg := fmt.Sprintf("ambiguous PSP transfer: batch %d, stored=%s, psp=%s",
				b.ID, b.PspTransferID, resp.TransferID)
			batchID := b.ID
			_ = s.repo.InsertLedgerAlert(ctx, LedgerAlert{
				Severity:  "CRITICAL",
				Currency:  b.Currency,
				BatchID:   &batchID,
				AlertType: "ambiguous_transfer",
				Message:   alertMsg,
			})
			_ = s.repo.UpdateBatchStatus(ctx, b.ID, BatchStatusAmbiguous, alertMsg)
			return ErrAmbiguousTransfer
		}
		if resp.Status == "failed" {
			_ = s.repo.UpdateBatchStatus(ctx, b.ID, BatchStatusFailed, resp.ErrorMsg)
			return nil
		}
		if resp.Status != "paid" {
			// Still pending on PSP side; try again next reconcile cycle.
			return nil
		}
		pspTransferID = b.PspTransferID
	}

	// Tx2: post ledger + mark paid.
	sellerPayableID, err := s.walletPoster.FindOrOpenSellerPayable(ctx, b.SellerID, b.Currency)
	if err != nil {
		return fmt.Errorf("reconcile: FindOrOpenSellerPayable batch=%d: %w", b.ID, err)
	}
	escrowAcctID, err := s.walletPoster.FindAccount(ctx, escrowAcctType, b.Currency)
	if err != nil {
		return fmt.Errorf("reconcile: FindAccount escrow batch=%d: %w", b.ID, err)
	}

	return s.runTx2(ctx, b.ID, pspTransferID, b.SellerID, sellerPayableID, escrowAcctID,
		b.TotalAmountMinor, b.Currency, b.Market, b.IdempotencyKey, nil)
}
