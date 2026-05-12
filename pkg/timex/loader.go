package timex

import (
	"context"
	"fmt"
	"strings"
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

// staticCalendarLoader returns a pre-built Calendar without any external I/O.
// Used by fin-svc, which cannot reach postgres-ecom where ref_schema lives.
type staticCalendarLoader struct {
	calendars map[string]Calendar
}

// NewStaticCalendarLoader returns a CalendarLoader backed by pre-built calendars.
// Keys are market codes (e.g. "TR"); values are the corresponding Calendar.
func NewStaticCalendarLoader(calendars map[string]Calendar) CalendarLoader {
	return &staticCalendarLoader{calendars: calendars}
}

func (l *staticCalendarLoader) Load(_ context.Context, market string) (Calendar, error) {
	cal, ok := l.calendars[market]
	if !ok {
		return Calendar{}, fmt.Errorf("timex: no static calendar for market %q", market)
	}
	return cal, nil
}

// ParseCalendarDates builds a Calendar from a comma-separated list of YYYY-MM-DD holiday dates.
// Used by fin-svc to construct a static Calendar from an env var at startup
// (e.g. BUSINESS_CALENDAR_TR=2026-01-01,2026-04-23,...).
func ParseCalendarDates(market string, csv string) (Calendar, error) {
	holidays := make(map[string]struct{})
	for _, raw := range strings.Split(csv, ",") {
		d := strings.TrimSpace(raw)
		if d == "" {
			continue
		}
		if _, err := time.Parse("2006-01-02", d); err != nil {
			return Calendar{}, fmt.Errorf("timex: invalid holiday date %q for market %s: %w", d, market, err)
		}
		holidays[d] = struct{}{}
	}
	return Calendar{Market: market, Holidays: holidays}, nil
}
