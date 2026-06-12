package order

import (
	"context"
	"errors"
	"testing"
	"time"
)

type fakeMembershipRepo struct {
	spend    int64
	count    int
	tiers    []MembershipTierDef
	statsErr error
	tiersErr error
	gotSince time.Time
}

func (f *fakeMembershipRepo) UserOrderStats(_ context.Context, _ int64, since time.Time) (int64, int, error) {
	f.gotSince = since
	return f.spend, f.count, f.statsErr
}

func (f *fakeMembershipRepo) ListMembershipTiers(context.Context, string) ([]MembershipTierDef, error) {
	return f.tiers, f.tiersErr
}

func trTiers() []MembershipTierDef {
	return []MembershipTierDef{
		{Code: "classic", Rank: 1, Currency: "TRY", MinSpendMinor: 0, MinOrders: 0},
		{Code: "gold", Rank: 2, Currency: "TRY", MinSpendMinor: 250000, MinOrders: 5},
		{Code: "elite", Rank: 3, Currency: "TRY", MinSpendMinor: 1000000, MinOrders: 15},
	}
}

func newSvc(repo MembershipRepository) *membershipService {
	return &membershipService{repo: repo, now: func() time.Time {
		return time.Date(2026, 6, 12, 12, 0, 0, 0, time.UTC)
	}}
}

func TestMembership_Derivation(t *testing.T) {
	cases := []struct {
		name      string
		spend     int64
		count     int
		wantTier  string
		wantNext  string // "" = top tier (next omitted)
		wantSpend int64
	}{
		{"new user → classic, next gold", 0, 0, "classic", "gold", 0},
		{"spend met but orders short → still classic (AND semantics)", 400000, 4, "classic", "gold", 400000},
		{"orders met but spend short → still classic (AND semantics)", 200000, 9, "classic", "gold", 200000},
		{"both gold thresholds met → gold, next elite", 412000, 7, "gold", "elite", 412000},
		{"exactly on gold thresholds → gold (inclusive)", 250000, 5, "gold", "elite", 250000},
		{"top tier → elite, no next", 1500000, 20, "elite", "", 1500000},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			repo := &fakeMembershipRepo{spend: tc.spend, count: tc.count, tiers: trTiers()}
			m, err := newSvc(repo).GetMembershipTier(context.Background(), 1, "TR")
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if m.Tier != tc.wantTier {
				t.Errorf("tier: want %q got %q", tc.wantTier, m.Tier)
			}
			if tc.wantNext == "" {
				if m.NextTier != nil {
					t.Errorf("next: want nil got %q", *m.NextTier)
				}
			} else {
				if m.NextTier == nil || *m.NextTier != tc.wantNext {
					t.Errorf("next: want %q got %v", tc.wantNext, m.NextTier)
				}
				if m.NextMinSpendMinor == nil || m.NextMinOrders == nil {
					t.Error("next thresholds: want non-nil")
				}
			}
			if m.SpendMinor != tc.wantSpend || m.OrderCount != tc.count {
				t.Errorf("stats: got spend=%d count=%d", m.SpendMinor, m.OrderCount)
			}
			if m.WindowDays != MembershipWindowDays || m.Currency != "TRY" {
				t.Errorf("window/currency: got %d/%s", m.WindowDays, m.Currency)
			}
		})
	}
}

func TestMembership_WindowIs365Days(t *testing.T) {
	repo := &fakeMembershipRepo{tiers: trTiers()}
	svc := newSvc(repo)
	if _, err := svc.GetMembershipTier(context.Background(), 1, "TR"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := time.Date(2026, 6, 12, 12, 0, 0, 0, time.UTC).AddDate(0, 0, -MembershipWindowDays)
	if !repo.gotSince.Equal(want) {
		t.Errorf("since: want %v got %v", want, repo.gotSince)
	}
}

func TestMembership_Errors(t *testing.T) {
	t.Run("no tiers → ErrNoMembershipTiers", func(t *testing.T) {
		_, err := newSvc(&fakeMembershipRepo{}).GetMembershipTier(context.Background(), 1, "XX")
		if !errors.Is(err, ErrNoMembershipTiers) {
			t.Fatalf("want ErrNoMembershipTiers got %v", err)
		}
	})
	t.Run("stats error propagates", func(t *testing.T) {
		repo := &fakeMembershipRepo{tiers: trTiers(), statsErr: errors.New("boom")}
		if _, err := newSvc(repo).GetMembershipTier(context.Background(), 1, "TR"); err == nil {
			t.Fatal("want error")
		}
	})
	t.Run("tiers error propagates", func(t *testing.T) {
		repo := &fakeMembershipRepo{tiersErr: errors.New("boom")}
		if _, err := newSvc(repo).GetMembershipTier(context.Background(), 1, "TR"); err == nil {
			t.Fatal("want error")
		}
	})
}
