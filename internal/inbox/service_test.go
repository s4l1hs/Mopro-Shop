package inbox

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"
)

type fakeRepo struct {
	items      []Notification
	count      int
	prefs      []Preference
	upserted   []Preference
	markedRead []int64
	allRead    int
	pushTokens map[string]string // token -> platform
	deleted    []string
}

func (f *fakeRepo) List(_ context.Context, _ int64, unreadOnly bool, limit, offset int) ([]Notification, error) {
	out := f.items
	if offset >= len(out) {
		return nil, nil
	}
	end := offset + limit
	if end > len(out) {
		end = len(out)
	}
	return out[offset:end], nil
}
func (f *fakeRepo) Count(_ context.Context, _ int64, _ bool) (int, error) { return f.count, nil }
func (f *fakeRepo) MarkRead(_ context.Context, _, id int64) error {
	f.markedRead = append(f.markedRead, id)
	return nil
}
func (f *fakeRepo) MarkAllRead(_ context.Context, _ int64) (int, error) { return f.allRead, nil }
func (f *fakeRepo) ListPreferences(_ context.Context, _ int64) ([]Preference, error) {
	return f.prefs, nil
}
func (f *fakeRepo) UpsertPreferences(_ context.Context, _ pgx.Tx, _ int64, prefs []Preference) error {
	f.upserted = append(f.upserted, prefs...)
	return nil
}
func (f *fakeRepo) WithTx(ctx context.Context, fn func(pgx.Tx) error) error { return fn(nil) }
func (f *fakeRepo) UpsertPushToken(_ context.Context, _ int64, token, platform string) error {
	if f.pushTokens == nil {
		f.pushTokens = map[string]string{}
	}
	f.pushTokens[token] = platform
	return nil
}
func (f *fakeRepo) DeletePushToken(_ context.Context, _ int64, token string) error {
	f.deleted = append(f.deleted, token)
	return nil
}
func (f *fakeRepo) Insert(_ context.Context, n Notification) (Notification, error) { return n, nil }

func TestList_ClampsPageSizeAndReturnsTotal(t *testing.T) {
	repo := &fakeRepo{
		items: make([]Notification, 5),
		count: 12,
	}
	s := NewService(repo)
	items, total, err := s.List(context.Background(), 1, false, 1, 999) // oversized pageSize
	if err != nil {
		t.Fatal(err)
	}
	if total != 12 {
		t.Errorf("total=%d want 12", total)
	}
	// pageSize clamped to 20 → returns all 5 available
	if len(items) != 5 {
		t.Errorf("items=%d want 5", len(items))
	}
}

func TestMarkRead_Idempotent(t *testing.T) {
	repo := &fakeRepo{}
	s := NewService(repo)
	_ = s.MarkRead(context.Background(), 1, 7)
	_ = s.MarkRead(context.Background(), 1, 7) // again, no error
	if len(repo.markedRead) != 2 {
		t.Errorf("expected 2 idempotent calls, got %d", len(repo.markedRead))
	}
}

func TestGetPreferences_MergesDefaults(t *testing.T) {
	// Store overrides marketing/in_app to true (default would be false).
	repo := &fakeRepo{prefs: []Preference{{Category: TypeMarketing, Channel: ChannelInApp, Enabled: true}}}
	s := NewService(repo)
	got, err := s.GetPreferences(context.Background(), 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != len(PrefCategories)*len(PrefChannels) {
		t.Fatalf("expected full matrix %d, got %d", len(PrefCategories)*len(PrefChannels), len(got))
	}
	find := func(c, ch string) bool {
		for _, p := range got {
			if p.Category == c && p.Channel == ch {
				return p.Enabled
			}
		}
		t.Fatalf("missing %s/%s", c, ch)
		return false
	}
	if !find(TypeOrderStatus, ChannelEmail) {
		t.Error("transactional category should default enabled")
	}
	if find(TypeMarketing, ChannelEmail) {
		t.Error("marketing email should default disabled")
	}
	if !find(TypeMarketing, ChannelInApp) {
		t.Error("stored override (marketing in_app = true) should win")
	}
}

func TestUpsertPreferences_RejectsInvalid(t *testing.T) {
	s := NewService(&fakeRepo{})
	err := s.UpsertPreferences(context.Background(), 1, []Preference{{Category: "bogus", Channel: ChannelInApp, Enabled: true}})
	if !errors.Is(err, ErrInvalidPreference) {
		t.Errorf("want ErrInvalidPreference, got %v", err)
	}
	err = s.UpsertPreferences(context.Background(), 1, []Preference{{Category: TypeSecurity, Channel: "carrier_pigeon", Enabled: true}})
	if !errors.Is(err, ErrInvalidPreference) {
		t.Errorf("want ErrInvalidPreference for bad channel, got %v", err)
	}
}

func TestUpsertPreferences_PartialSubmitOnlyTouchesProvided(t *testing.T) {
	repo := &fakeRepo{}
	s := NewService(repo)
	if err := s.UpsertPreferences(context.Background(), 1, []Preference{
		{Category: TypeMarketing, Channel: ChannelEmail, Enabled: false},
	}); err != nil {
		t.Fatal(err)
	}
	if len(repo.upserted) != 1 {
		t.Errorf("partial submit should upsert exactly 1 row, got %d", len(repo.upserted))
	}
}

func TestRegisterPushToken_Validation(t *testing.T) {
	s := NewService(&fakeRepo{})
	if err := s.RegisterPushToken(context.Background(), 1, "tok", "blackberry"); !errors.Is(err, ErrInvalidPlatform) {
		t.Errorf("want ErrInvalidPlatform, got %v", err)
	}
	if err := s.RegisterPushToken(context.Background(), 1, "", "web"); !errors.Is(err, ErrInvalidPushToken) {
		t.Errorf("want ErrInvalidPushToken, got %v", err)
	}
	if err := s.RegisterPushToken(context.Background(), 1, "tok", "web"); err != nil {
		t.Errorf("valid token should succeed, got %v", err)
	}
}
