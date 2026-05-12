package timex

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxCalendarLoader struct {
	pool *pgxpool.Pool
}

// NewPgxCalendarLoader returns a CalendarLoader backed by a pgx connection pool.
// Each Load call queries ref_schema.business_calendars for the given market.
func NewPgxCalendarLoader(pool *pgxpool.Pool) CalendarLoader {
	return &pgxCalendarLoader{pool: pool}
}

func (l *pgxCalendarLoader) Load(ctx context.Context, market string) (Calendar, error) {
	const q = `SELECT date FROM ref_schema.business_calendars WHERE market = $1`
	rows, err := l.pool.Query(ctx, q, market)
	if err != nil {
		return Calendar{}, fmt.Errorf("timex: load calendar for %s: %w", market, err)
	}
	defer rows.Close()

	holidays := make(map[string]struct{})
	for rows.Next() {
		var d time.Time
		if err := rows.Scan(&d); err != nil {
			return Calendar{}, fmt.Errorf("timex: scan date: %w", err)
		}
		holidays[d.UTC().Format("2006-01-02")] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		return Calendar{}, fmt.Errorf("timex: calendar rows: %w", err)
	}
	return Calendar{Market: market, Holidays: holidays}, nil
}
