package sellerpayout

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/pkg/timex"
)

type payoutService struct {
	repo         Repository
	walletPoster WalletPoster
	psp          PspTransferer
	calLoader    timex.CalendarLoader
	currency     string // payout fiat currency; read from env at startup
	log          *slog.Logger
}

// NewService constructs a sellerpayout Service.
// currency is the fiat currency for payouts (e.g. TRY for TR launch).
// walletPoster is satisfied by wallet.Service (injected by fin-svc/main.go).
// psp is satisfied by sipay.Client.
func NewService(
	repo Repository,
	walletPoster WalletPoster,
	psp PspTransferer,
	calLoader timex.CalendarLoader,
	currency string,
	log *slog.Logger,
) Service {
	if log == nil {
		log = slog.Default()
	}
	return &payoutService{
		repo:         repo,
		walletPoster: walletPoster,
		psp:          psp,
		calLoader:    calLoader,
		currency:     currency,
		log:          log,
	}
}

// SchedulePayoutsForOrder aggregates seller_net_minor per seller and inserts one
// commission_schema.seller_payouts row per seller, with unlock_at = delivered_at + 3 BD.
// Idempotent: skips any seller whose payout row already exists.
func (s *payoutService) SchedulePayoutsForOrder(ctx context.Context, ev OrderDeliveredEvent) error {
	// 1. Aggregate seller_net_minor by seller (one payout per seller per order).
	bySellerNet := make(map[int64]int64)
	for _, it := range ev.Items {
		bySellerNet[it.SellerID] += it.SellerNetMinor
	}
	if len(bySellerNet) == 0 {
		s.log.WarnContext(ctx, "sellerpayout: no items in delivered event, skipping",
			"order_id", ev.OrderID)
		return nil
	}

	// 2. Compute unlock_at = delivered_at + 3 business days (CLAUDE.md § 4.8).
	cal, err := s.calLoader.Load(ctx, ev.Market)
	if err != nil {
		return fmt.Errorf("sellerpayout: load calendar for %s: %w", ev.Market, err)
	}
	unlockAt := timex.AddBusinessDays(ev.DeliveredAt, 3, cal)

	// 3. Insert one payout row per seller in a single transaction.
	return s.repo.WithTx(ctx, pgx.ReadCommitted, func(tx pgx.Tx) error {
		for sellerID, netMinor := range bySellerNet {
			if netMinor <= 0 {
				continue
			}
			idempKey := fmt.Sprintf("payout:order_%d:seller_%d", ev.OrderID, sellerID)

			// Idempotency: skip if already exists.
			if _, findErr := s.repo.FindPayoutByKey(ctx, idempKey); findErr == nil {
				continue
			}

			p := Payout{
				OrderID:        ev.OrderID,
				SellerID:       sellerID,
				AmountMinor:    netMinor,
				Currency:       s.currency,
				DeliveredAt:    ev.DeliveredAt,
				UnlockAt:       unlockAt,
				Status:         PayoutStatusScheduled,
				Market:         ev.Market,
				IdempotencyKey: idempKey,
			}
			if _, txErr := s.repo.InsertPayout(ctx, tx, p); txErr != nil {
				return txErr
			}
		}
		return nil
	})
}

// RunDailyPayouts — see run_daily.go.
func (s *payoutService) RunDailyPayouts(ctx context.Context, payoutDate time.Time, market, currency string) (RunDailyResult, error) {
	return s.runDailyPayouts(ctx, payoutDate, market, currency)
}

// ReconcileProcessing — see reconcile.go.
func (s *payoutService) ReconcileProcessing(ctx context.Context) error {
	return s.reconcileProcessing(ctx)
}

// HandlePspOnboarded — see psp_event_handler.go.
func (s *payoutService) HandlePspOnboarded(ctx context.Context, ev PspOnboardedEvent) error {
	return s.repo.UpsertSellerPspAccount(ctx, SellerPspAccount{
		SellerID:    ev.SellerID,
		PspMemberID: ev.PspMemberID,
		Market:      ev.Market,
	})
}

// HandleFraudHoldSet — see fraud_event_handler.go.
func (s *payoutService) HandleFraudHoldSet(ctx context.Context, ev FraudHoldSetEvent) error {
	return s.handleFraudHoldSet(ctx, ev)
}
