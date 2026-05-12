package timex_test

import (
	"testing"
	"time"

	"github.com/mopro/platform/pkg/timex"
)

var noHolidays = timex.Calendar{Market: "TEST", Holidays: map[string]struct{}{}}

func TestAddBusinessDays_ZeroN(t *testing.T) {
	start := time.Date(2026, 5, 11, 0, 0, 0, 0, time.UTC) // Monday
	got := timex.AddBusinessDays(start, 0, noHolidays)
	if !got.Equal(start.UTC()) {
		t.Errorf("n=0: want %v, got %v", start.UTC(), got)
	}
}

func TestAddBusinessDays_SkipsWeekend(t *testing.T) {
	// Friday 2026-05-08 + 1 BD = Monday 2026-05-11
	friday := time.Date(2026, 5, 8, 0, 0, 0, 0, time.UTC)
	got := timex.AddBusinessDays(friday, 1, noHolidays)
	want := time.Date(2026, 5, 11, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Errorf("skip weekend: want %v, got %v", want, got)
	}
}

func TestAddBusinessDays_SkipsMultipleWeekends(t *testing.T) {
	// Friday 2026-05-08 + 3 BD = Wednesday 2026-05-13
	friday := time.Date(2026, 5, 8, 0, 0, 0, 0, time.UTC)
	got := timex.AddBusinessDays(friday, 3, noHolidays)
	want := time.Date(2026, 5, 13, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Errorf("skip weekend: want %v, got %v", want, got)
	}
}

func TestAddBusinessDays_SkipsHoliday(t *testing.T) {
	// Monday 2026-05-11 + 1 BD; 2026-05-12 is a holiday → result 2026-05-13
	cal := timex.Calendar{
		Market:   "TR",
		Holidays: map[string]struct{}{"2026-05-12": {}},
	}
	start := time.Date(2026, 5, 11, 0, 0, 0, 0, time.UTC)
	got := timex.AddBusinessDays(start, 1, cal)
	want := time.Date(2026, 5, 13, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Errorf("skip holiday: want %v, got %v", want, got)
	}
}

func TestAddBusinessDays_SkipsConsecutiveHolidays(t *testing.T) {
	// Tuesday 2026-05-26 + 1 BD.
	// 2026-05-27..30 = Kurban Bayramı (holiday), 2026-05-31 = Sunday → result 2026-06-01
	cal := timex.Calendar{
		Market: "TR",
		Holidays: map[string]struct{}{
			"2026-05-27": {},
			"2026-05-28": {},
			"2026-05-29": {},
			"2026-05-30": {},
		},
	}
	start := time.Date(2026, 5, 26, 0, 0, 0, 0, time.UTC)
	got := timex.AddBusinessDays(start, 1, cal)
	want := time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Errorf("consecutive holidays: want %v, got %v", want, got)
	}
}

func TestAddBusinessDays_ResultIsNeverWeekend(t *testing.T) {
	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	for n := 1; n <= 20; n++ {
		got := timex.AddBusinessDays(start, n, noHolidays)
		wd := got.Weekday()
		if wd == time.Saturday || wd == time.Sunday {
			t.Errorf("n=%d: result %v is a weekend (%v)", n, got, wd)
		}
	}
}

func TestAddBusinessDays_ThreeBDFromFriday(t *testing.T) {
	// Core business rule: delivered_at + 3 BD.
	// Friday + 3 BD = Wednesday (skips Sat + Sun)
	friday := time.Date(2026, 5, 8, 14, 30, 0, 0, time.UTC)
	got := timex.AddBusinessDays(friday, 3, noHolidays)
	want := time.Date(2026, 5, 13, 14, 30, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Errorf("3 BD from Friday: want %v, got %v", want, got)
	}
}
