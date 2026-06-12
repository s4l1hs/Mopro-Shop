package order

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// pgxMembershipRepository backs the tier read-model: one aggregate over the
// module's OWN order_schema.orders + one ref_schema read (allowed shared-read).
type pgxMembershipRepository struct {
	pool *pgxpool.Pool
}

// NewMembershipRepository builds the pgx-backed MembershipRepository.
func NewMembershipRepository(pool *pgxpool.Pool) MembershipRepository {
	return &pgxMembershipRepository{pool: pool}
}

func (r *pgxMembershipRepository) UserOrderStats(ctx context.Context, userID int64, since time.Time) (int64, int, error) {
	var spend int64
	var count int
	err := r.pool.QueryRow(ctx,
		`SELECT COALESCE(SUM(total_minor), 0), COUNT(*)
		 FROM order_schema.orders
		 WHERE user_id = $1 AND status = $2 AND created_at >= $3`,
		userID, string(StatusDelivered), since,
	).Scan(&spend, &count)
	if err != nil {
		return 0, 0, fmt.Errorf("order.repo: UserOrderStats: %w", err)
	}
	return spend, count, nil
}

func (r *pgxMembershipRepository) ListMembershipTiers(ctx context.Context, market string) ([]MembershipTierDef, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT code, rank, currency, min_spend_minor, min_orders
		 FROM ref_schema.membership_tiers
		 WHERE market = $1 AND active
		 ORDER BY rank ASC`,
		market,
	)
	if err != nil {
		return nil, fmt.Errorf("order.repo: ListMembershipTiers: %w", err)
	}
	defer rows.Close()

	var tiers []MembershipTierDef
	for rows.Next() {
		var t MembershipTierDef
		if err := rows.Scan(&t.Code, &t.Rank, &t.Currency, &t.MinSpendMinor, &t.MinOrders); err != nil {
			return nil, fmt.Errorf("order.repo: scan membership tier: %w", err)
		}
		tiers = append(tiers, t)
	}
	return tiers, rows.Err()
}
