package timex

import (
	"context"
	"fmt"
	"strings"
	"time"
)

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
