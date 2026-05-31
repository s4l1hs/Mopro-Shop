package analytics

import (
	"context"
	"time"

	"github.com/google/uuid"
)

type service struct {
	repo Repository
}

// NewService builds the analytics pipeline service.
func NewService(repo Repository) Service { return &service{repo: repo} }

// Ingest validates → consent-gates → appends → projects (§3.3).
func (s *service) Ingest(ctx context.Context, batch IngestBatch) error {
	if err := ValidateBatch(batch); err != nil {
		return err
	}
	userID, err := s.resolveUser(ctx, batch)
	if err != nil {
		return err
	}
	// Consent gate: an identified user must have opted in (silent denial).
	// Guests (no resolved user) are stored so a later login can merge them.
	if userID != nil {
		allowed, err := s.consentAllows(ctx, *userID)
		if err != nil {
			return err
		}
		if !allowed {
			return nil
		}
	}

	stored := make([]StoredEvent, 0, len(batch.Events))
	for i := range batch.Events {
		e := batch.Events[i]
		stripRawSearchText(&e) // enforce Option A (normalized search intent only)
		stored = append(stored, StoredEvent{
			SessionID: batch.SessionID, UserID: userID,
			Type: e.Type, Payload: e.Payload, ClientTs: e.ClientTs,
		})
	}
	if err := s.repo.InsertEvents(ctx, uuid.New(), stored); err != nil {
		return err
	}
	return s.projectViews(ctx, userID, stored)
}

// resolveUser returns the effective user for a batch: explicit bearer id wins,
// else the session_identity binding, else nil (guest).
func (s *service) resolveUser(ctx context.Context, batch IngestBatch) (*int64, error) {
	if batch.UserID != nil {
		return batch.UserID, nil
	}
	uid, ok, err := s.repo.ResolveUserID(ctx, batch.SessionID)
	if err != nil || !ok {
		return nil, err
	}
	return &uid, nil
}

func (s *service) consentAllows(ctx context.Context, userID int64) (bool, error) {
	c, ok, err := s.repo.GetConsent(ctx, userID)
	if err != nil {
		return false, err
	}
	return ok && c.AnalyticsEnabled, nil
}

// projectViews upserts the recently-viewed projection from product_view events
// (authed users only; guests project on later identify-backfill).
func (s *service) projectViews(ctx context.Context, userID *int64, stored []StoredEvent) error {
	if userID == nil {
		return nil
	}
	for _, e := range stored {
		if e.Type != EventProductView {
			continue
		}
		pid, ok := payloadInt64(e.Payload, "productId")
		if !ok {
			continue
		}
		if err := s.repo.UpsertRecentlyViewed(ctx, *userID, pid, e.ClientTs); err != nil {
			return err
		}
	}
	return nil
}

func (s *service) IdentifySession(ctx context.Context, sessionID string, userID int64) error {
	if !ValidSessionID(sessionID) {
		return ErrInvalidSession
	}
	if err := s.repo.InsertSessionIdentity(ctx, sessionID, userID); err != nil {
		return err
	}
	// Merge-on-auth: fold the session's past product views into the projection.
	return s.repo.BackfillRecentlyViewed(ctx, sessionID, userID)
}

func (s *service) GetConsent(ctx context.Context, userID int64) (Consent, error) {
	c, ok, err := s.repo.GetConsent(ctx, userID)
	if err != nil {
		return Consent{}, err
	}
	if !ok {
		return Consent{UserID: userID, AnalyticsEnabled: false}, nil
	}
	return c, nil
}

func (s *service) SetConsent(ctx context.Context, userID int64, enabled bool) (Consent, error) {
	return s.repo.UpsertConsent(ctx, userID, enabled)
}

func (s *service) DeleteUserData(ctx context.Context, userID int64) error {
	return s.repo.DeleteUserData(ctx, userID)
}

func (s *service) RecentlyViewed(ctx context.Context, userID int64, limit int) ([]RecentlyViewedItem, error) {
	if limit < 1 {
		limit = 20
	}
	if limit > 50 {
		limit = 50
	}
	return s.repo.ListRecentlyViewed(ctx, userID, limit)
}

func (s *service) PruneEvents(ctx context.Context, before time.Time, capPerRun int) (int64, error) {
	if capPerRun < 1 {
		capPerRun = 100000
	}
	return s.repo.PruneEvents(ctx, before, capPerRun)
}

func (s *service) RebuildRecentlyViewed(ctx context.Context, since time.Time) error {
	return s.repo.RebuildRecentlyViewed(ctx, since)
}

// payloadInt64 extracts an integer-valued payload field (JSON numbers decode as
// float64; ints may arrive directly from internal callers).
func payloadInt64(p map[string]any, key string) (int64, bool) {
	switch v := p[key].(type) {
	case float64:
		return int64(v), true
	case int64:
		return v, true
	case int:
		return int64(v), true
	default:
		return 0, false
	}
}
