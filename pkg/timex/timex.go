// Package timex provides timezone-aware time helpers and the business-day calendar.
package timex

import (
	"context"
	"time"
)

// Calendar holds public-holiday dates for a single market, enabling O(1) lookup.
type Calendar struct {
	Market   string
	Holidays map[string]struct{} // keys are YYYY-MM-DD strings
}

// CalendarLoader loads a market calendar from persistent storage.
type CalendarLoader interface {
	Load(ctx context.Context, market string) (Calendar, error)
}

// AddBusinessDays returns the date that is n business days after start,
// skipping weekends and any date present in cal.Holidays.
// If n == 0 the return value equals start.UTC().
func AddBusinessDays(start time.Time, n int, cal Calendar) time.Time {
	current := start.UTC()
	added := 0
	for added < n {
		current = current.AddDate(0, 0, 1)
		if current.Weekday() == time.Saturday || current.Weekday() == time.Sunday {
			continue
		}
		if _, holiday := cal.Holidays[current.Format("2006-01-02")]; holiday {
			continue
		}
		added++
	}
	return current
}
