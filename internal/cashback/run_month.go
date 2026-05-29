package cashback

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
)

const (
	cronBatchSize  = 50
	equityAcctType = "equity:cashback_distribution"
)

// PayMonthlyInstallments processes all active plans whose next installment is due by runDate.
// For each due plan: posts D=C ledger entries via outbox, increments payments_made,
// and sets status='completed' atomically with the final installment.
func (s *cashbackService) PayMonthlyInstallments(ctx context.Context, runDate time.Time) (PaymentSummary, error) {
	result := PaymentSummary{}
	runDate = runDate.UTC()

	// Cache equity account IDs per coin currency to avoid repeated lookups.
	equityAcctsByCC := map[string]int64{}

	// runPeriod = the YYYYMM the cron is paying for, derived from runDate.
	// Used both as the period_yyyymm in cashback_schema.payments and as a
	// pre-filter in ListDuePlans (NOT EXISTS already-paid-for-this-period).
	runPeriod := timeToPeriod(runDate)

	for {
		plans, err := s.repo.ListDuePlans(ctx, runDate, runPeriod, cronBatchSize)
		if err != nil {
			return result, fmt.Errorf("cashback: PayMonthlyInstallments ListDuePlans: %w", err)
		}
		if len(plans) == 0 {
			break
		}

		for _, plan := range plans {
			equityAcctID, ok := equityAcctsByCC[plan.Currency]
			if !ok {
				equityAcctID, err = s.walletPoster.FindAccount(ctx, equityAcctType, plan.Currency)
				if err != nil {
					return result, fmt.Errorf("cashback: find equity account %s/%s: %w",
						equityAcctType, plan.Currency, err)
				}
				equityAcctsByCC[plan.Currency] = equityAcctID
			}

			retries, err := s.payOnePlan(ctx, plan, equityAcctID, runDate, &result)
			result.Retries += retries
			if err != nil {
				s.log.ErrorContext(ctx, "cashback: payOnePlan failed",
					"plan_id", plan.ID, "user_id", plan.UserID, "err", err)
				result.Failed++
			}
		}

		if len(plans) < cronBatchSize {
			break
		}
	}

	return result, nil
}

// payOnePlan wraps payOnePlanInTx with SERIALIZABLE retry on 40001.
// Returns (retryCount, error).
func (s *cashbackService) payOnePlan(ctx context.Context, plan Plan, equityAcctID int64, runDate time.Time, result *PaymentSummary) (int, error) {
	const maxRetries = 3
	for attempt := 0; attempt < maxRetries; attempt++ {
		done, err := s.payOnePlanInTx(ctx, plan, equityAcctID, runDate, result)
		if err == nil {
			return attempt, nil
		}
		if isSerializationFailure(err) && attempt < maxRetries-1 {
			continue
		}
		if done {
			return attempt, nil // skipped cleanly
		}
		return attempt, err
	}
	return maxRetries - 1, ErrMaxRetriesExceeded
}

// payOnePlanInTx executes one installment payment in a SERIALIZABLE tx.
// Returns (done=true, nil) when the plan is cleanly skipped (wallet inactive, etc.).
func (s *cashbackService) payOnePlanInTx(ctx context.Context, plan Plan, equityAcctID int64, runDate time.Time, result *PaymentSummary) (bool, error) {
	// n is the installment number we're about to pay.
	n := plan.PaymentsMade + 1

	terms := PlanTerms{
		TotalMonths:            plan.TotalMonths,
		MonthlyAmountMinor:     plan.MonthlyAmountMinor,
		MonthlyAmountLastMinor: plan.MonthlyAmountLastMinor,
	}
	amount := InstallmentAmount(terms, n)
	if amount == 0 {
		// n is out of range — plan already completed or data inconsistency.
		s.log.WarnContext(ctx, "cashback: InstallmentAmount returned 0, skipping",
			"plan_id", plan.ID, "n", n, "total_months", plan.TotalMonths)
		result.Skipped++
		return true, nil
	}

	// Pre-check wallet status (outside SERIALIZABLE tx, uses pool read).
	acctID, status, err := s.walletPoster.FindAccountByOwnerAnyStatus(ctx, "user", plan.UserID, plan.Currency)
	if err != nil {
		return false, fmt.Errorf("find wallet any status user=%d: %w", plan.UserID, err)
	}

	var userAcctID int64
	switch {
	case acctID == 0:
		// Wallet never created — create lazily.
		userAcctID, err = s.walletPoster.OpenOrFindUserWallet(ctx, plan.UserID, plan.Currency)
		if err != nil {
			return false, fmt.Errorf("open user wallet user=%d: %w", plan.UserID, err)
		}
	case status != "active":
		s.log.InfoContext(ctx, "cashback: wallet not active, skipping",
			"plan_id", plan.ID, "user_id", plan.UserID, "account_id", acctID, "status", status)
		result.Skipped++
		return true, nil
	default:
		userAcctID = acctID
	}

	// Fast-path pre-check: if a payment row for this (plan, run-period) already
	// exists, skip the SERIALIZABLE tx entirely. Correctness is still owned by
	// ClaimPaymentPeriod's UNIQUE — this just keeps the hot path fast when
	// ListDuePlans returns plans whose current-period payment was already
	// committed by a prior cron run.
	runMonthPeriodFast := timeToPeriod(runDate)
	if exists, existsErr := s.repo.PaymentExistsForPeriod(ctx, plan.ID, runMonthPeriodFast); existsErr != nil {
		return false, fmt.Errorf("PaymentExistsForPeriod plan=%d period=%d: %w", plan.ID, runMonthPeriodFast, existsErr)
	} else if exists {
		s.log.DebugContext(ctx, "cashback: period already paid (fast-path), skipping",
			"plan_id", plan.ID, "period_yyyymm", runMonthPeriodFast)
		result.Skipped++
		return true, nil
	}

	// period_yyyymm is derived from the cron's runDate (current month), not the
	// installment's scheduled month. Rationale: cron runs are the unit of work
	// — two cron invocations in the same calendar month must serialize on the
	// same (plan_id, period_yyyymm) UNIQUE; missed-month catch-up runs pay the
	// next due installment in the run-month they fire. Also keeps period_yyyymm
	// within the schema's BETWEEN 202600 AND 209912 CHECK even when plans have
	// pre-2026 start_dates (e.g. integration test seeds).
	runMonthPeriod := runMonthPeriodFast
	scheduled := plan.StartDate.AddDate(0, n-1, 0)
	paymentIdemKey := fmt.Sprintf("cashback:plan_%d:period_%d", plan.ID, runMonthPeriod)

	var done bool
	err = s.repo.WithTx(ctx, pgx.Serializable, func(tx pgx.Tx) error {
		// Step 1: claim this period in cashback_schema.payments. UNIQUE(plan_id,
		// period_yyyymm) is the v6 storage-layer idempotency guard — concurrent
		// racers lose here cleanly without touching the ledger.
		paymentID, claimed, claimErr := s.repo.ClaimPaymentPeriod(ctx, tx, ClaimPaymentInput{
			PlanID:         plan.ID,
			PeriodYYYYMM:   runMonthPeriod,
			ScheduledDate:  scheduled,
			AmountMinor:    amount,
			IdempotencyKey: paymentIdemKey,
		})
		if claimErr != nil {
			return claimErr
		}
		if !claimed {
			s.log.InfoContext(ctx, "cashback: period already claimed by concurrent worker, skipping",
				"plan_id", plan.ID, "period_yyyymm", runMonthPeriod)
			result.Skipped++
			return nil
		}

		// Step 2: post the ledger entries inside the same tx.
		ledgerIdemKey := fmt.Sprintf("cashback:%d:installment:%d", plan.ID, n)
		ref := fmt.Sprintf("plan:%d:installment:%d", plan.ID, n)

		postIn := ledger.PostInput{
			Type:           "cashback_payment",
			Reference:      ref,
			IdempotencyKey: ledgerIdemKey,
			Market:         plan.Market,
			Currency:       plan.Currency,
			EventType:      "fin.cashback.payment.posted.v1",
			Metadata: map[string]string{
				"plan_id":     strconv.FormatInt(plan.ID, 10),
				"installment": strconv.Itoa(n),
				"user_id":     strconv.FormatInt(plan.UserID, 10),
			},
			Entries: []ledger.Entry{
				{AccountID: equityAcctID, Direction: ledger.Debit, AmountMinor: amount},
				{AccountID: userAcctID, Direction: ledger.Credit, AmountMinor: amount},
			},
		}
		txnID, txErr := s.walletPoster.PostInTx(ctx, tx, postIn)
		if txErr != nil {
			return fmt.Errorf("PostInTx plan=%d installment=%d: %w", plan.ID, n, txErr)
		}

		// Step 3: flip the payment row to 'paid' with the ledger txn id.
		if markErr := s.repo.MarkPaymentPaid(ctx, tx, paymentID, txnID, runDate); markErr != nil {
			return markErr
		}

		// Step 4: refresh the denormalized payments_made cache from
		// COUNT(*) FROM payments WHERE plan_id=X AND status='paid'.
		// The payments table is now the source of truth; plans.payments_made
		// is a cache. Refreshing inside the same tx as MarkPaymentPaid keeps
		// the cache consistent at commit time.
		newCount, completed, refreshErr := s.repo.RefreshPaymentsMadeCache(ctx, tx, plan.ID)
		if refreshErr != nil {
			return refreshErr
		}

		paymentsRemaining := plan.TotalMonths - newCount
		statusStr := "active"
		if completed {
			statusStr = "completed"
		}
		s.log.InfoContext(ctx, "cashback: installment paid",
			"plan_id", plan.ID,
			"n", n,
			"amount_minor", amount,
			"payments_remaining", paymentsRemaining,
			"status", statusStr,
		)

		result.Processed++
		s.biz.IncCashbackInstallmentPaid("fin-svc", plan.Market)
		if completed {
			done = true
		}
		return nil
	})
	return done, err
}

// timeToPeriod converts a time.Time to YYYYMM integer (e.g. 2026-07-15 → 202607).
func timeToPeriod(t time.Time) int {
	return t.Year()*100 + int(t.Month())
}

// periodToFirstDay converts YYYYMM (e.g. 202607) to the first day of that month (UTC).
func periodToFirstDay(period int) time.Time {
	year := period / 100
	month := period % 100
	return time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.UTC)
}
