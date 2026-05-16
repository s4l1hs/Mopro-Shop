package reconcile

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"
)

type reconcileService struct {
	repo      Repository
	pd        PDClient
	walletSvc SystemStateSetter
	dryRun    bool
	log       *slog.Logger
}

// NewService constructs a reconcile Service.
// dryRun=true logs actions but skips system_state updates, PD calls, and outbox events.
func NewService(repo Repository, pd PDClient, walletSvc SystemStateSetter, dryRun bool, log *slog.Logger) Service {
	if log == nil {
		log = slog.Default()
	}
	return &reconcileService{repo: repo, pd: pd, walletSvc: walletSvc, dryRun: dryRun, log: log}
}

func (s *reconcileService) RunWeekly(ctx context.Context, asOf time.Time) (WeeklyResult, error) {
	result := WeeklyResult{AsOf: asOf}

	// Check 1: D=C invariant across all currencies.
	check1Results, err := runCheck1DCInvariant(ctx, s.repo)
	if err != nil {
		result.Errors = append(result.Errors, fmt.Errorf("check1: %w", err))
	}
	for _, cr := range check1Results {
		if err2 := s.handleFailedCheck(ctx, cr, &result); err2 != nil {
			result.Errors = append(result.Errors, err2)
		}
	}

	// Check 2: cashback backward check for last 3 periods.
	period := periodFromTime(asOf)
	check2Results, err := runCheck2CashbackBackward(ctx, s.repo, period)
	if err != nil {
		result.Errors = append(result.Errors, fmt.Errorf("check2: %w", err))
	}
	for _, cr := range check2Results {
		if err2 := s.handleFailedCheck(ctx, cr, &result); err2 != nil {
			result.Errors = append(result.Errors, err2)
		}
	}

	if result.AlertsInserted > 0 {
		s.log.ErrorContext(ctx, "reconcile: drift detected",
			"alerts_inserted", result.AlertsInserted, "dry_run", s.dryRun)
	} else {
		s.log.InfoContext(ctx, "reconcile: all invariants pass",
			"as_of", asOf.Format("2006-01-02"))
	}
	return result, nil
}

func (s *reconcileService) handleFailedCheck(ctx context.Context, cr CheckResult, result *WeeklyResult) error {
	s.log.ErrorContext(ctx, "reconcile: invariant violation",
		"check", cr.CheckName, "drift_minor", cr.DriftMinor, "details", cr.Details, "dry_run", s.dryRun)

	alert := ReconcileAlert{
		CheckName:        cr.CheckName,
		CurrencyOrPeriod: cr.Details,
		DriftMinor:       cr.DriftMinor,
		DedupKey:         buildDedupKey(cr.CheckName, cr.Details),
	}

	// Always insert the ledger_alert (even in dry_run) for audit visibility.
	// system_state update is done inside InsertAlertWithOutboxAndState only when !dryRun.
	if !s.dryRun {
		var alertID int64
		txErr := s.repo.WithTx(ctx, func(tx pgx.Tx) error {
			var err error
			alertID, err = s.repo.InsertAlertWithOutboxAndState(ctx, tx, alert, "")
			return err
		})
		if txErr != nil {
			return fmt.Errorf("reconcile: recordDrift WithTx: %w", txErr)
		}
		// After WithTx commits, invalidate wallet cache so PostInTx sees read_only=true.
		if s.walletSvc != nil {
			s.walletSvc.InvalidateReadOnlyCache()
		}

		// Page PagerDuty.
		dedupKey := buildDedupKey(cr.CheckName, cr.Details)
		summary := fmt.Sprintf("LEDGER INVARIANT VIOLATION: %s drift=%d", cr.CheckName, cr.DriftMinor)
		if pdErr := s.pd.Trigger(ctx, summary, dedupKey, map[string]any{
			"check_name":  cr.CheckName,
			"drift_minor": cr.DriftMinor,
			"details":     cr.Details,
			"alert_id":    alertID,
		}); pdErr != nil {
			s.log.ErrorContext(ctx, "reconcile: PagerDuty trigger failed", "err", pdErr)
			// Log but don't return — alert is already inserted and system is read-only.
		}
	} else {
		s.log.InfoContext(ctx, "reconcile: dry_run mode — alert logged but NOT persisted",
			"check", cr.CheckName, "drift_minor", cr.DriftMinor)
	}

	result.AlertsInserted++
	return nil
}
