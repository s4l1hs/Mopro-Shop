//go:build integration

package timex_test

import (
	"testing"
	"time"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"

	"github.com/mopro/platform/pkg/timex"
)

// base is 2026-01-01; we generate offsets [0, 1825 days] = 5 years.
var base = time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

func TestProperty_AddBusinessDaysSkipsWeekends(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 200
	properties := gopter.NewProperties(params)

	cal := timex.Calendar{Market: "TEST", Holidays: map[string]struct{}{}}

	properties.Property(
		"result of AddBusinessDays(n>=1) is never Saturday or Sunday",
		prop.ForAll(
			func(offsetDays int64, rawN uint8) bool {
				n := int(rawN%30) + 1
				start := base.Add(time.Duration(offsetDays%1825) * 24 * time.Hour)
				result := timex.AddBusinessDays(start, n, cal)
				wd := result.Weekday()
				return wd != time.Saturday && wd != time.Sunday
			},
			gen.Int64Range(0, 1825),
			gen.UInt8(),
		),
	)

	properties.TestingRun(t)
}

func TestProperty_AddBusinessDaysSkipsHolidays(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 200
	properties := gopter.NewProperties(params)

	// TR holidays for 2026 (the launch year)
	holidays := map[string]struct{}{
		"2026-01-01": {},
		"2026-03-20": {},
		"2026-03-21": {},
		"2026-03-22": {},
		"2026-04-23": {},
		"2026-05-01": {},
		"2026-05-19": {},
		"2026-05-27": {},
		"2026-05-28": {},
		"2026-05-29": {},
		"2026-05-30": {},
		"2026-07-15": {},
		"2026-08-30": {},
		"2026-10-29": {},
	}
	cal := timex.Calendar{Market: "TR", Holidays: holidays}

	properties.Property(
		"result of AddBusinessDays is never a holiday and never a weekend",
		prop.ForAll(
			func(offsetDays int64, rawN uint8) bool {
				n := int(rawN%30) + 1
				start := base.Add(time.Duration(offsetDays%365) * 24 * time.Hour)
				result := timex.AddBusinessDays(start, n, cal)
				dateKey := result.Format("2006-01-02")
				_, isHoliday := holidays[dateKey]
				wd := result.Weekday()
				return !isHoliday && wd != time.Saturday && wd != time.Sunday
			},
			gen.Int64Range(0, 365),
			gen.UInt8(),
		),
	)

	properties.TestingRun(t)
}
