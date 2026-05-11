// Package timex provides timezone-aware time helpers and the business-day calendar.
package timex

import "time"

// AddBusinessDays returns the date that is n business days after start, using
// the named market calendar to skip public holidays.
// calendar must match a market code in ref_schema.business_calendars (e.g. "TR").
// TODO(mopro:placeholder): replace the weekend-only fallback with ref_schema holiday lookup
// Unblocked by: Phase 0.2 (ref_schema seed) and Phase 1 (DB connectivity)
func AddBusinessDays(start time.Time, n int, calendar string) time.Time {
	current := start.UTC()
	added := 0
	for added < n {
		current = current.AddDate(0, 0, 1)
		if current.Weekday() == time.Saturday || current.Weekday() == time.Sunday {
			continue
		}
		added++
	}
	return current
}
