package shipping

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxShippingRepository struct {
	pool *pgxpool.Pool
}

// NewRepository constructs a shipping Repository backed by postgres-ecom.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgxShippingRepository{pool: pool}
}

func (r *pgxShippingRepository) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback(ctx)
		return err
	}
	return tx.Commit(ctx)
}

func (r *pgxShippingRepository) InsertShipment(ctx context.Context, tx pgx.Tx, s Shipment) (Shipment, error) {
	row := tx.QueryRow(ctx, `
		INSERT INTO shipping_schema.shipments
			(order_id, carrier, tracking_number, carrier_shipment_id, state,
			 label_pdf_b2_key, estimated_delivery_at, cost_minor, cost_currency, idempotency_key)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		RETURNING id, created_at, updated_at`,
		s.OrderID, s.Carrier, nullableStr(s.TrackingNumber), nullableStr(s.CarrierShipmentID),
		string(s.State), nullableStr(s.LabelPDFB2Key),
		s.EstimatedDeliveryAt, s.CostMinor, nullableStr(s.CostCurrency), s.IdempotencyKey,
	)
	if err := row.Scan(&s.ID, &s.CreatedAt, &s.UpdatedAt); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return Shipment{}, fmt.Errorf("shipping: duplicate shipment idempotency key %q", s.IdempotencyKey)
		}
		return Shipment{}, err
	}
	return s, nil
}

func (r *pgxShippingRepository) FindShipmentByOrderID(ctx context.Context, orderID int64) (Shipment, error) {
	return r.scanOne(ctx, r.pool, `
		SELECT id, order_id, carrier, COALESCE(tracking_number,''),
		       COALESCE(carrier_shipment_id,''), state,
		       COALESCE(label_pdf_b2_key,''),
		       estimated_delivery_at, delivered_at, last_polled_at,
		       idempotency_key, COALESCE(cost_minor,0), COALESCE(cost_currency,''),
		       created_at, updated_at
		FROM shipping_schema.shipments
		WHERE order_id = $1
		ORDER BY created_at DESC LIMIT 1`, orderID)
}

func (r *pgxShippingRepository) FindShipmentByTrackingNumber(ctx context.Context, carrier, trackingNumber string) (Shipment, error) {
	return r.scanOne(ctx, r.pool, `
		SELECT id, order_id, carrier, COALESCE(tracking_number,''),
		       COALESCE(carrier_shipment_id,''), state,
		       COALESCE(label_pdf_b2_key,''),
		       estimated_delivery_at, delivered_at, last_polled_at,
		       idempotency_key, COALESCE(cost_minor,0), COALESCE(cost_currency,''),
		       created_at, updated_at
		FROM shipping_schema.shipments
		WHERE carrier = $1 AND tracking_number = $2
		LIMIT 1`, carrier, trackingNumber)
}

func (r *pgxShippingRepository) UpdateShipmentState(ctx context.Context, tx pgx.Tx, id int64, state ShipmentState, deliveredAt *time.Time) error {
	_, err := tx.Exec(ctx, `
		UPDATE shipping_schema.shipments
		SET state = $2, delivered_at = $3, updated_at = NOW()
		WHERE id = $1`, id, string(state), deliveredAt)
	return err
}

func (r *pgxShippingRepository) InsertShipmentEvent(ctx context.Context, tx pgx.Tx, e ShipmentEvent) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO shipping_schema.shipment_events (shipment_id, state, source, carrier_raw, event_at)
		VALUES ($1, $2, $3, $4, $5)`,
		e.ShipmentID, string(e.State), e.Source, nullableJSON(e.CarrierRaw), e.EventAt)
	return err
}

func (r *pgxShippingRepository) FindPollableShipments(ctx context.Context, carrier string, limit int) ([]Shipment, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, order_id, carrier, COALESCE(tracking_number,''),
		       COALESCE(carrier_shipment_id,''), state,
		       COALESCE(label_pdf_b2_key,''),
		       estimated_delivery_at, delivered_at, last_polled_at,
		       idempotency_key, COALESCE(cost_minor,0), COALESCE(cost_currency,''),
		       created_at, updated_at
		FROM shipping_schema.shipments
		WHERE carrier = $1
		  AND state IN ('pending','picked_up','in_transit','out_for_delivery')
		  AND (last_polled_at IS NULL OR last_polled_at < NOW() - INTERVAL '285 seconds')
		ORDER BY last_polled_at ASC NULLS FIRST
		LIMIT $2`, carrier, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanShipments(rows)
}

func (r *pgxShippingRepository) UpdateLastPolledAt(ctx context.Context, id int64) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE shipping_schema.shipments SET last_polled_at = NOW() WHERE id = $1`, id)
	return err
}

// ── Pre-purchase ETA reference lookups (P-034, ref_schema, read-only) ───────────

// LookupTransit joins origin/dest cities → zones → transit_days in one query.
// A miss on any join (unknown city or zone pair) returns found=false.
func (r *pgxShippingRepository) LookupTransit(ctx context.Context, market, originCity, destCity string) (int, int, bool, error) {
	var minD, maxD int
	err := r.pool.QueryRow(ctx, `
		SELECT t.min_days, t.max_days
		FROM ref_schema.shipping_zones o
		JOIN ref_schema.shipping_zones d
		  ON d.market = o.market AND d.city = $3
		JOIN ref_schema.transit_days t
		  ON t.market = o.market AND t.origin_zone = o.zone AND t.dest_zone = d.zone
		WHERE o.market = $1 AND o.city = $2`, market, originCity, destCity).Scan(&minD, &maxD)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, 0, false, nil
	}
	if err != nil {
		return 0, 0, false, err
	}
	return minD, maxD, true, nil
}

// LookupTransitDefault returns the market's conservative national fallback range.
func (r *pgxShippingRepository) LookupTransitDefault(ctx context.Context, market string) (int, int, bool, error) {
	var minD, maxD int
	err := r.pool.QueryRow(ctx, `
		SELECT min_days, max_days FROM ref_schema.transit_default WHERE market = $1`, market).Scan(&minD, &maxD)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, 0, false, nil
	}
	if err != nil {
		return 0, 0, false, err
	}
	return minD, maxD, true, nil
}

// ── scan helpers ──────────────────────────────────────────────────────────────

type querier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

func (r *pgxShippingRepository) scanOne(ctx context.Context, q querier, sql string, args ...any) (Shipment, error) {
	var s Shipment
	var stateStr string
	err := q.QueryRow(ctx, sql, args...).Scan(
		&s.ID, &s.OrderID, &s.Carrier, &s.TrackingNumber, &s.CarrierShipmentID,
		&stateStr, &s.LabelPDFB2Key,
		&s.EstimatedDeliveryAt, &s.DeliveredAt, &s.LastPolledAt,
		&s.IdempotencyKey, &s.CostMinor, &s.CostCurrency,
		&s.CreatedAt, &s.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Shipment{}, ErrShipmentNotFound
		}
		return Shipment{}, err
	}
	s.State = ShipmentState(stateStr)
	return s, nil
}

func scanShipments(rows pgx.Rows) ([]Shipment, error) {
	var result []Shipment
	for rows.Next() {
		var s Shipment
		var stateStr string
		if err := rows.Scan(
			&s.ID, &s.OrderID, &s.Carrier, &s.TrackingNumber, &s.CarrierShipmentID,
			&stateStr, &s.LabelPDFB2Key,
			&s.EstimatedDeliveryAt, &s.DeliveredAt, &s.LastPolledAt,
			&s.IdempotencyKey, &s.CostMinor, &s.CostCurrency,
			&s.CreatedAt, &s.UpdatedAt,
		); err != nil {
			return nil, err
		}
		s.State = ShipmentState(stateStr)
		result = append(result, s)
	}
	return result, rows.Err()
}

func nullableStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func nullableJSON(b []byte) any {
	if len(b) == 0 {
		return nil
	}
	return b
}
