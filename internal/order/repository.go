package order

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

const pgUniqueViolation = "23505"

type pgxOrderRepository struct {
	pool *pgxpool.Pool
}

// NewRepository returns a Repository backed by a pgx connection pool.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgxOrderRepository{pool: pool}
}

func (r *pgxOrderRepository) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("order.repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *pgxOrderRepository) InsertOrder(ctx context.Context, tx pgx.Tx, o Order) (Order, error) {
	// seller_id and checkout_session_id use NULLIF so zero-value → SQL NULL.
	var checkoutSessionID *string
	if o.CheckoutSessionID != "" {
		checkoutSessionID = &o.CheckoutSessionID
	}
	var sellerID *int64
	if o.SellerID != 0 {
		sellerID = &o.SellerID
	}
	var couponCode *string
	if o.CouponCode != "" {
		couponCode = &o.CouponCode
	}
	err := tx.QueryRow(ctx,
		`INSERT INTO order_schema.orders
			(user_id, status, subtotal_minor, shipping_minor, shipping_payer,
			 discount_minor, total_minor, currency, market,
			 cashback_eligible, cashback_currency, idempotency_key,
			 seller_id, checkout_session_id, coupon_code, coupon_discount_minor)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
		RETURNING id, created_at, updated_at`,
		o.UserID, string(o.Status), o.SubtotalMinor, o.ShippingMinor, o.ShippingPayer,
		o.DiscountMinor, o.TotalMinor, o.Currency, o.Market,
		o.CashbackEligible, o.CashbackCurrency, o.IdempotencyKey,
		sellerID, checkoutSessionID, couponCode, o.CouponDiscountMinor,
	).Scan(&o.ID, &o.CreatedAt, &o.UpdatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == pgUniqueViolation {
			return Order{}, ErrDuplicateIdempotency
		}
		return Order{}, fmt.Errorf("order.repo: InsertOrder: %w", err)
	}
	return o, nil
}

func (r *pgxOrderRepository) InsertOrderItem(ctx context.Context, tx pgx.Tx, item OrderItem) (OrderItem, error) {
	err := tx.QueryRow(ctx,
		`INSERT INTO order_schema.order_items
			(order_id, variant_id, seller_id, category_id, qty,
			 unit_price_minor, list_unit_price_minor, basket_discount_pct, unit_price_currency,
			 commission_pct_bps, kdv_pct_bps,
			 commission_amount_minor, kdv_amount_minor, seller_net_minor)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
		RETURNING id`,
		item.OrderID, item.VariantID, item.SellerID, item.CategoryID, item.Qty,
		item.UnitPriceMinor, item.ListUnitPriceMinor, item.BasketDiscountPct, item.UnitPriceCurrency,
		item.CommissionPctBps, item.KdvPctBps,
		item.CommissionAmountMinor, item.KdvAmountMinor, item.SellerNetMinor,
	).Scan(&item.ID)
	if err != nil {
		return OrderItem{}, fmt.Errorf("order.repo: InsertOrderItem: %w", err)
	}
	return item, nil
}

func (r *pgxOrderRepository) GetOrder(ctx context.Context, orderID int64) (Order, []OrderItem, error) {
	o, err := r.scanOrder(ctx, r.pool.QueryRow(ctx,
		`SELECT id, user_id, status, subtotal_minor, shipping_minor, shipping_payer,
		        discount_minor, total_minor, currency, market, delivered_at,
		        cashback_eligible, cashback_currency, idempotency_key,
		        created_at, updated_at,
		        COALESCE(seller_id, 0), COALESCE(checkout_session_id, ''),
		        COALESCE(coupon_code, ''), coupon_discount_minor
		FROM order_schema.orders WHERE id = $1`, orderID))
	if err != nil {
		return Order{}, nil, err
	}
	items, err := r.GetOrderItems(ctx, orderID)
	return o, items, err
}

func (r *pgxOrderRepository) GetOrderItems(ctx context.Context, orderID int64) ([]OrderItem, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, order_id, variant_id, seller_id, category_id, qty,
		        unit_price_minor, list_unit_price_minor, basket_discount_pct, unit_price_currency,
		        commission_pct_bps, kdv_pct_bps,
		        commission_amount_minor, kdv_amount_minor, seller_net_minor
		FROM order_schema.order_items WHERE order_id = $1 ORDER BY id ASC`, orderID)
	if err != nil {
		return nil, fmt.Errorf("order.repo: GetOrderItems: %w", err)
	}
	defer rows.Close()
	return scanItems(rows)
}

func (r *pgxOrderRepository) FindByIdempotencyKey(ctx context.Context, key string) (Order, error) {
	return r.scanOrder(ctx, r.pool.QueryRow(ctx,
		`SELECT id, user_id, status, subtotal_minor, shipping_minor, shipping_payer,
		        discount_minor, total_minor, currency, market, delivered_at,
		        cashback_eligible, cashback_currency, idempotency_key,
		        created_at, updated_at,
		        COALESCE(seller_id, 0), COALESCE(checkout_session_id, ''),
		        COALESCE(coupon_code, ''), coupon_discount_minor
		FROM order_schema.orders WHERE idempotency_key = $1`, key))
}

func (r *pgxOrderRepository) ListOrders(ctx context.Context, userID int64) ([]Order, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, status, subtotal_minor, shipping_minor, shipping_payer,
		        discount_minor, total_minor, currency, market, delivered_at,
		        cashback_eligible, cashback_currency, idempotency_key,
		        created_at, updated_at,
		        COALESCE(seller_id, 0), COALESCE(checkout_session_id, ''),
		        COALESCE(coupon_code, ''), coupon_discount_minor
		FROM order_schema.orders
		WHERE user_id = $1
		ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("order.repo: ListOrders: %w", err)
	}
	defer rows.Close()
	var orders []Order
	for rows.Next() {
		o, err := r.scanOrderRow(rows)
		if err != nil {
			return nil, err
		}
		orders = append(orders, o)
	}
	return orders, rows.Err()
}

func (r *pgxOrderRepository) UpdateStatus(ctx context.Context, tx pgx.Tx, orderID int64, status OrderStatus, updatedAt time.Time) error {
	tag, err := tx.Exec(ctx,
		`UPDATE order_schema.orders SET status = $1, updated_at = $2 WHERE id = $3`,
		string(status), updatedAt, orderID)
	if err != nil {
		return fmt.Errorf("order.repo: UpdateStatus: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrOrderNotFound
	}
	return nil
}

func (r *pgxOrderRepository) SetDelivered(ctx context.Context, tx pgx.Tx, orderID int64, deliveredAt time.Time) error {
	tag, err := tx.Exec(ctx,
		`UPDATE order_schema.orders
		 SET status = 'delivered', delivered_at = $1, updated_at = $1
		 WHERE id = $2`,
		deliveredAt.UTC(), orderID)
	if err != nil {
		return fmt.Errorf("order.repo: SetDelivered: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrOrderNotFound
	}
	return nil
}

// ── internal scan helpers ─────────────────────────────────────────────────────

func (r *pgxOrderRepository) scanOrder(ctx context.Context, row pgx.Row) (Order, error) {
	_ = ctx
	var o Order
	if err := row.Scan(
		&o.ID, &o.UserID, &o.Status,
		&o.SubtotalMinor, &o.ShippingMinor, &o.ShippingPayer,
		&o.DiscountMinor, &o.TotalMinor, &o.Currency, &o.Market, &o.DeliveredAt,
		&o.CashbackEligible, &o.CashbackCurrency, &o.IdempotencyKey,
		&o.CreatedAt, &o.UpdatedAt,
		&o.SellerID, &o.CheckoutSessionID,
		&o.CouponCode, &o.CouponDiscountMinor,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Order{}, ErrOrderNotFound
		}
		return Order{}, fmt.Errorf("order.repo: scan order: %w", err)
	}
	return o, nil
}

func (r *pgxOrderRepository) scanOrderRow(rows pgx.Rows) (Order, error) {
	var o Order
	if err := rows.Scan(
		&o.ID, &o.UserID, &o.Status,
		&o.SubtotalMinor, &o.ShippingMinor, &o.ShippingPayer,
		&o.DiscountMinor, &o.TotalMinor, &o.Currency, &o.Market, &o.DeliveredAt,
		&o.CashbackEligible, &o.CashbackCurrency, &o.IdempotencyKey,
		&o.CreatedAt, &o.UpdatedAt,
		&o.SellerID, &o.CheckoutSessionID,
		&o.CouponCode, &o.CouponDiscountMinor,
	); err != nil {
		return Order{}, fmt.Errorf("order.repo: scan order row: %w", err)
	}
	return o, nil
}

func scanItems(rows pgx.Rows) ([]OrderItem, error) {
	var items []OrderItem
	for rows.Next() {
		var it OrderItem
		if err := rows.Scan(
			&it.ID, &it.OrderID, &it.VariantID, &it.SellerID, &it.CategoryID, &it.Qty,
			&it.UnitPriceMinor, &it.ListUnitPriceMinor, &it.BasketDiscountPct, &it.UnitPriceCurrency,
			&it.CommissionPctBps, &it.KdvPctBps,
			&it.CommissionAmountMinor, &it.KdvAmountMinor, &it.SellerNetMinor,
		); err != nil {
			return nil, fmt.Errorf("order.repo: scan item: %w", err)
		}
		items = append(items, it)
	}
	return items, rows.Err()
}

// ── coupon storage (CT-03/CHK-04) ─────────────────────────────────────────────

func (r *pgxOrderRepository) GetCouponByCode(ctx context.Context, code, market string) (Coupon, error) {
	var c Coupon
	err := r.pool.QueryRow(ctx,
		`SELECT id, code, kind, percent_off, min_basket_minor, max_redemptions,
		        starts_at, expires_at, active, market
		 FROM order_schema.coupons
		 WHERE upper(code) = upper($1) AND market = $2`, code, market,
	).Scan(&c.ID, &c.Code, &c.Kind, &c.PercentOff, &c.MinBasketMinor, &c.MaxRedemptions,
		&c.StartsAt, &c.ExpiresAt, &c.Active, &c.Market)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Coupon{}, ErrCouponNotFound
		}
		return Coupon{}, fmt.Errorf("order.repo: GetCouponByCode: %w", err)
	}
	return c, nil
}

func (r *pgxOrderRepository) CountCouponRedemptions(ctx context.Context, couponID int64) (int, error) {
	var n int
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM order_schema.coupon_redemptions WHERE coupon_id = $1`,
		couponID,
	).Scan(&n); err != nil {
		return 0, fmt.Errorf("order.repo: CountCouponRedemptions: %w", err)
	}
	return n, nil
}

// InsertCouponRedemption is idempotent: a duplicate (coupon_id, order_id) is a
// no-op (ON CONFLICT DO NOTHING), so a retried capture cannot double-count.
func (r *pgxOrderRepository) InsertCouponRedemption(ctx context.Context, tx pgx.Tx, red CouponRedemption) error {
	_, err := tx.Exec(ctx,
		`INSERT INTO order_schema.coupon_redemptions
			(coupon_id, order_id, user_id, discount_minor)
		 VALUES ($1,$2,$3,$4)
		 ON CONFLICT (coupon_id, order_id) DO NOTHING`,
		red.CouponID, red.OrderID, red.UserID, red.DiscountMinor)
	if err != nil {
		return fmt.Errorf("order.repo: InsertCouponRedemption: %w", err)
	}
	return nil
}
