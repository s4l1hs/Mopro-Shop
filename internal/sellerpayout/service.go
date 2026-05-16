package sellerpayout

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/pkg/timex"
)

type payoutService struct {
	repo      Repository
	calLoader timex.CalendarLoader
	currency  string // payout fiat currency; read from env at startup
}

// NewService constructs a sellerpayout Service.
// currency should come from env DEFAULT_CURRENCY (e.g. TRY for TR launch).
func NewService(repo Repository, calLoader timex.CalendarLoader, currency string) Service {
	return &payoutService{
		repo:      repo,
		calLoader: calLoader,
		currency:  currency,
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
		slog.Warn("sellerpayout: no items in delivered event, skipping",
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
