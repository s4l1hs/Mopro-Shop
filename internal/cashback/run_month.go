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

	for {
		plans, err := s.repo.ListDuePlans(ctx, runDate, cronBatchSize)
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

			retries, err := s.payOnePlan(ctx, plan, equityAcctID, &result)
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
func (s *cashbackService) payOnePlan(ctx context.Context, plan Plan, equityAcctID int64, result *PaymentSummary) (int, error) {
	const maxRetries = 3
	for attempt := 0; attempt < maxRetries; attempt++ {
		done, err := s.payOnePlanInTx(ctx, plan, equityAcctID, result)
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
func (s *cashbackService) payOnePlanInTx(ctx context.Context, plan Plan, equityAcctID int64, result *PaymentSummary) (bool, error) {
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

	var done bool
	err = s.repo.WithTx(ctx, pgx.Serializable, func(tx pgx.Tx) error {
		idemKey := fmt.Sprintf("cashback:%d:installment:%d", plan.ID, n)
		ref := fmt.Sprintf("plan:%d:installment:%d", plan.ID, n)

		postIn := ledger.PostInput{
			Type:           "cashback_payment",
			Reference:      ref,
			IdempotencyKey: idemKey,
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
		if _, txErr := s.walletPoster.PostInTx(ctx, tx, postIn); txErr != nil {
			return fmt.Errorf("PostInTx plan=%d installment=%d: %w", plan.ID, n, txErr)
		}

		newCount, completed, txErr := s.repo.IncrPaymentsMade(ctx, tx, plan.ID)
		if txErr != nil {
			return txErr
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

