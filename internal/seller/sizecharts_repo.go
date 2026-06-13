package seller

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// Seller size-chart persistence (seller_schema). Header + rows are always written
// in one transaction; resolution joins within seller_schema only (no §5 JOIN).

const chartHeaderCols = `id, seller_id, name, garment_type, gender, size_system, source, created_at, updated_at`

func scanChartHeader(row pgx.Row) (SizeChart, error) {
	var c SizeChart
	err := row.Scan(&c.ID, &c.SellerID, &c.Name, &c.GarmentType, &c.Gender,
		&c.SizeSystem, &c.Source, &c.CreatedAt, &c.UpdatedAt)
	return c, err
}

func (r *pgxRepository) InsertSizeChart(ctx context.Context, c SizeChart) (int64, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("seller.repo: InsertSizeChart begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var id int64
	if err := tx.QueryRow(ctx,
		`INSERT INTO seller_schema.seller_size_charts
		   (seller_id, name, garment_type, gender, size_system, source)
		 VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
		c.SellerID, c.Name, c.GarmentType, c.Gender, c.SizeSystem, c.Source,
	).Scan(&id); err != nil {
		return 0, fmt.Errorf("seller.repo: InsertSizeChart header: %w", err)
	}
	if err := insertChartRows(ctx, tx, id, c.Rows); err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, fmt.Errorf("seller.repo: InsertSizeChart commit: %w", err)
	}
	return id, nil
}

func (r *pgxRepository) ReplaceSizeChart(ctx context.Context, sellerID, chartID int64, c SizeChart) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("seller.repo: ReplaceSizeChart begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	ct, err := tx.Exec(ctx,
		`UPDATE seller_schema.seller_size_charts
		    SET name=$1, garment_type=$2, gender=$3, size_system=$4, updated_at=now()
		  WHERE id=$5 AND seller_id=$6`,
		c.Name, c.GarmentType, c.Gender, c.SizeSystem, chartID, sellerID)
	if err != nil {
		return fmt.Errorf("seller.repo: ReplaceSizeChart header: %w", err)
	}
	if ct.RowsAffected() == 0 {
		return ErrChartNotFound // unknown or not owned — no existence leak
	}
	if _, err := tx.Exec(ctx,
		`DELETE FROM seller_schema.seller_size_chart_rows WHERE chart_id=$1`, chartID); err != nil {
		return fmt.Errorf("seller.repo: ReplaceSizeChart clear rows: %w", err)
	}
	if err := insertChartRows(ctx, tx, chartID, c.Rows); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("seller.repo: ReplaceSizeChart commit: %w", err)
	}
	return nil
}

func insertChartRows(ctx context.Context, tx pgx.Tx, chartID int64, rows []SizeChartRow) error {
	for _, row := range rows {
		if _, err := tx.Exec(ctx,
			`INSERT INTO seller_schema.seller_size_chart_rows
			   (chart_id, size_label, sort_rank, measurement, min_mm, max_mm)
			 VALUES ($1,$2,$3,$4,$5,$6)`,
			chartID, row.SizeLabel, row.SortRank, row.Measurement, row.MinMM, row.MaxMM,
		); err != nil {
			return fmt.Errorf("seller.repo: insert chart row: %w", err)
		}
	}
	return nil
}

func (r *pgxRepository) ListSizeChartsBySeller(ctx context.Context, sellerID int64) ([]SizeChart, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT `+chartHeaderCols+` FROM seller_schema.seller_size_charts
		  WHERE seller_id=$1 ORDER BY id`, sellerID)
	if err != nil {
		return nil, fmt.Errorf("seller.repo: ListSizeCharts: %w", err)
	}
	defer rows.Close()
	var charts []SizeChart
	byID := map[int64]*SizeChart{}
	var ids []int64
	for rows.Next() {
		c, err := scanChartHeader(rows)
		if err != nil {
			return nil, fmt.Errorf("seller.repo: ListSizeCharts scan: %w", err)
		}
		charts = append(charts, c)
		ids = append(ids, c.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for i := range charts {
		byID[charts[i].ID] = &charts[i]
	}
	if err := r.loadRowsInto(ctx, ids, byID); err != nil {
		return nil, err
	}
	return charts, nil
}

// loadRowsInto fills the Rows slice of each chart in byID from one rows query.
func (r *pgxRepository) loadRowsInto(ctx context.Context, ids []int64, byID map[int64]*SizeChart) error {
	if len(ids) == 0 {
		return nil
	}
	rrows, err := r.pool.Query(ctx,
		`SELECT chart_id, size_label, sort_rank, measurement, min_mm, max_mm
		   FROM seller_schema.seller_size_chart_rows
		  WHERE chart_id = ANY($1) ORDER BY sort_rank, measurement`, ids)
	if err != nil {
		return fmt.Errorf("seller.repo: load chart rows: %w", err)
	}
	defer rrows.Close()
	for rrows.Next() {
		var cid int64
		var row SizeChartRow
		if err := rrows.Scan(&cid, &row.SizeLabel, &row.SortRank, &row.Measurement, &row.MinMM, &row.MaxMM); err != nil {
			return fmt.Errorf("seller.repo: scan chart row: %w", err)
		}
		if c, ok := byID[cid]; ok {
			c.Rows = append(c.Rows, row)
		}
	}
	return rrows.Err()
}

func (r *pgxRepository) ChartOwnedBy(ctx context.Context, sellerID, chartID int64) (bool, error) {
	var one int
	err := r.pool.QueryRow(ctx,
		`SELECT 1 FROM seller_schema.seller_size_charts WHERE id=$1 AND seller_id=$2`,
		chartID, sellerID).Scan(&one)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("seller.repo: ChartOwnedBy: %w", err)
	}
	return true, nil
}

func (r *pgxRepository) AttachProductChart(ctx context.Context, productID, chartID, sellerID int64) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO seller_schema.product_size_charts (product_id, chart_id, seller_id)
		 VALUES ($1,$2,$3)
		 ON CONFLICT (product_id) DO UPDATE SET chart_id=EXCLUDED.chart_id, seller_id=EXCLUDED.seller_id`,
		productID, chartID, sellerID)
	if err != nil {
		return fmt.Errorf("seller.repo: AttachProductChart: %w", err)
	}
	return nil
}

func (r *pgxRepository) DetachProductChart(ctx context.Context, productID, sellerID int64) error {
	ct, err := r.pool.Exec(ctx,
		`DELETE FROM seller_schema.product_size_charts WHERE product_id=$1 AND seller_id=$2`,
		productID, sellerID)
	if err != nil {
		return fmt.Errorf("seller.repo: DetachProductChart: %w", err)
	}
	if ct.RowsAffected() == 0 {
		return ErrChartNotFound
	}
	return nil
}

// SizeChartForProduct resolves the chart attached to a product (header + rows),
// joining within seller_schema only. (false) when no chart is attached.
func (r *pgxRepository) SizeChartForProduct(ctx context.Context, productID int64) (SizeChart, bool, error) {
	c, err := scanChartHeader(r.pool.QueryRow(ctx,
		`SELECT sc.id, sc.seller_id, sc.name, sc.garment_type, sc.gender,
		        sc.size_system, sc.source, sc.created_at, sc.updated_at
		   FROM seller_schema.product_size_charts psc
		   JOIN seller_schema.seller_size_charts sc ON sc.id = psc.chart_id
		  WHERE psc.product_id = $1`, productID))
	if errors.Is(err, pgx.ErrNoRows) {
		return SizeChart{}, false, nil
	}
	if err != nil {
		return SizeChart{}, false, fmt.Errorf("seller.repo: SizeChartForProduct: %w", err)
	}
	byID := map[int64]*SizeChart{c.ID: &c}
	if err := r.loadRowsInto(ctx, []int64{c.ID}, byID); err != nil {
		return SizeChart{}, false, err
	}
	return c, true, nil
}
