package cashback

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
)

const (
	cronBatchSize   = 50
	equityAcctType  = "equity:cashback_distribution"
)

// runMonth is the core implementation of Service.RunMonth.
// It loops over active plans in batches (FOR UPDATE SKIP LOCKED), processing each
// plan in its own SERIALIZABLE transaction.
func (s *cashbackService) runMonth(ctx context.Context, period int, asOf time.Time, currency string) (RunMonthResult, error) {
	result := RunMonthResult{Period: period, Currency: currency}

	// Resolve the equity distribution account once; it is a platform account.
	equityAcctID, err := s.walletPoster.FindAccount(ctx, equityAcctType, currency)
	if err != nil {
		return result, fmt.Errorf("cashback: RunMonth find equity account %s/%s: %w", equityAcctType, currency, err)
	}

	for {
		// Batch SELECT is READ COMMITTED; the pool executes it outside any long-held tx.
		plans, err := s.repo.FetchPlansBatch(ctx, period, asOf, currency, cronBatchSize)
		if err != nil {
			return result, fmt.Errorf("cashback: RunMonth FetchPlansBatch period=%d: %w", period, err)
		}
		if len(plans) == 0 {
			break
		}

		for _, plan := range plans {
			retries, err := s.processPlan(ctx, plan, period, asOf, equityAcctID, &result)
			result.TotalRetries += retries
			if err != nil {
				s.log.ErrorContext(ctx, "cashback: processPlan failed",
					"plan_id", plan.ID, "period", period, "err", err)
				result.Failed++
			}
		}

		if len(plans) < cronBatchSize {
			break // last batch
		}
	}

	return result, nil
}

// processPlan wraps processPlanInTx with SERIALIZABLE retry on 40001.
// Returns (retryCount, error).
func (s *cashbackService) processPlan(ctx context.Context, plan Plan, period int, asOf time.Time, equityAcctID int64, result *RunMonthResult) (int, error) {
	const maxRetries = 3
	for attempt := 0; attempt < maxRetries; attempt++ {
		done, err := s.processPlanInTx(ctx, plan, period, asOf, equityAcctID, result)
		if err == nil {
			return attempt, nil
		}
		if isSerializationFailure(err) && attempt < maxRetries-1 {
			continue
		}
		if done {
			// ErrPaymentAlreadyExists or ErrWalletNotActive — counted as skipped by callee.
			return attempt, nil
		}
		return attempt, err
	}
	return maxRetries - 1, ErrMaxRetriesExceeded
}

// processPlanInTx executes a single plan's payment in a SERIALIZABLE tx.
// Returns (done=true, nil) when the plan is skipped (already paid, wallet inactive).
// Returns (done=false, err) on a real failure.
func (s *cashbackService) processPlanInTx(ctx context.Context, plan Plan, period int, asOf time.Time, equityAcctID int64, result *RunMonthResult) (bool, error) {
	var done bool
	err := s.repo.WithTx(ctx, pgx.Serializable, func(tx pgx.Tx) error {
		// 1. Pre-check wallet status before lazy creation.
		//    FindAccountByOwnerAnyStatus returns (0,"",nil) when no row exists,
		//    (id,status,nil) when found — regardless of status.
		//    This avoids the "re-read after conflict" failure path that occurs when
		//    OpenOrFindUserWallet tries to create an account that exists but is frozen.
		acctID, status, err := s.walletPoster.FindAccountByOwnerAnyStatus(ctx, "user", plan.UserID, plan.Currency)
		if err != nil {
			return fmt.Errorf("find wallet any status user=%d: %w", plan.UserID, err)
		}

		var userAcctID int64
		switch {
		case acctID == 0:
			// Wallet never created — create lazily and proceed.
			userAcctID, err = s.walletPoster.OpenOrFindUserWallet(ctx, plan.UserID, plan.Currency)
			if err != nil {
				return fmt.Errorf("open user wallet user=%d: %w", plan.UserID, err)
			}
		case status != "active":
			// Wallet exists but is frozen/suspended — skip, do not fail.
			s.log.InfoContext(ctx, "cashback: wallet not active, skipping",
				"plan_id", plan.ID, "user_id", plan.UserID, "account_id", acctID, "status", status)
			result.Skipped++
			done = true
			return nil
		default:
			userAcctID = acctID
		}

		// 2. Insert payment row (SAVEPOINT guards against duplicate on re-run).
		idemKey := fmt.Sprintf("cashback:%d:%d", plan.ID, period)
		pay := Payment{
			PlanID:         plan.ID,
			PeriodYYYYMM:   period,
			ScheduledDate:  asOf,
			AmountMinor:    plan.MonthlyAmountMinor,
			IdempotencyKey: idemKey,
		}
		pay, err = s.repo.InsertPayment(ctx, tx, pay)
		if errors.Is(err, ErrPaymentAlreadyExists) {
			s.log.InfoContext(ctx, "cashback: payment already exists, skipping",
				"plan_id", plan.ID, "period", period)
			result.Skipped++
			done = true
			return nil
		}
		if err != nil {
			return fmt.Errorf("insert payment plan=%d period=%d: %w", plan.ID, period, err)
		}

		// 3. Post ledger entries: D equity:cashback_distribution → C liability:wallet:user.
		postIn := ledger.PostInput{
			Type:           "cashback_payment",
			Reference:      strconv.FormatInt(plan.ID, 10),
			IdempotencyKey: idemKey,
			Market:         plan.Market,
			Currency:       plan.Currency,
			EventType:      "fin.cashback.payment.posted.v1",
			Metadata: map[string]string{
				"plan_id":       strconv.FormatInt(plan.ID, 10),
				"period_yyyymm": strconv.Itoa(period),
				"user_id":       strconv.FormatInt(plan.UserID, 10),
			},
			Entries: []ledger.Entry{
				{AccountID: equityAcctID, Direction: ledger.Debit, AmountMinor: plan.MonthlyAmountMinor},
				{AccountID: userAcctID, Direction: ledger.Credit, AmountMinor: plan.MonthlyAmountMinor},
			},
		}
		ledgerTxnID, err := s.walletPoster.PostInTx(ctx, tx, postIn)
		if err != nil {
			return fmt.Errorf("PostInTx plan=%d period=%d: %w", plan.ID, period, err)
		}

		// 4. Mark payment paid.
		if err := s.repo.MarkPaymentPaid(ctx, tx, pay.ID, ledgerTxnID, asOf); err != nil {
			return err
		}

		// 5. Stamp plan with this period so it won't be re-selected.
		if err := s.repo.UpdateLastDistributedPeriod(ctx, tx, plan.ID, period); err != nil {
			return err
		}

		result.Processed++
		return nil
	})
	return done, err
}

// periodToFirstDay converts YYYYMM (e.g. 202607) to the first day of that month (UTC).
func periodToFirstDay(period int) time.Time {
	year := period / 100
	month := period % 100
	return time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.UTC)
}

// timeToPeriod converts a time.Time to YYYYMM integer (e.g. 2026-07-15 → 202607).
func timeToPeriod(t time.Time) int {
	return t.Year()*100 + int(t.Month())
}
