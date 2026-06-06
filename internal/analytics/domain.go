// Package analytics implements the Tranche 4a event pipeline: an append-only
// event log + derived projections (TRANCHE_4_DESIGN.md Decision 2), binary
// opt-in consent (Decision 3), session-identity merge (Decision 4), and 90-day
// retention (Decision 5). It is a shared package: the ingest/consent/read
// surface is wired into core-svc, while the retention/rebuild crons and the
// account-erasure consumer run in jobs-svc — both connect to postgres-ecom and
// touch only analytics_schema (no cross-schema SQL).
package analytics

import (
	"errors"
	"regexp"
	"strings"
	"time"
)

// MaxBatchSize caps events per ingest request (§3.3). Oversized → ErrBatchTooLarge.
const MaxBatchSize = 100

var (
	ErrUnknownEventType    = errors.New("analytics: unknown event type")
	ErrBatchTooLarge       = errors.New("analytics: batch exceeds max size")
	ErrEmptyBatch          = errors.New("analytics: batch has no events")
	ErrInvalidSession      = errors.New("analytics: session_id must be a UUID")
	ErrMissingPayloadField = errors.New("analytics: required payload field missing")
)

// The locked 20-event taxonomy (TRANCHE_4_DESIGN.md §2). Renames are migrations.
const (
	EventPageView         = "page_view"
	EventProductView      = "product_view"
	EventCategoryView     = "category_view"
	EventSearch           = "search"
	EventFilterApplied    = "filter_applied"
	EventSortChanged      = "sort_changed"
	EventMegaMenuOpened   = "mega_menu_opened"
	EventVariantSelected  = "pdp_variant_selected"
	EventScrollDepth      = "scroll_depth"
	EventTimeOnPage       = "time_on_page"
	EventAddToCart        = "add_to_cart"
	EventRemoveFromCart   = "remove_from_cart"
	EventPurchase         = "purchase"
	EventLogin            = "login"
	EventLogout           = "logout"
	EventSessionStart     = "session_start"
	EventSessionEnd       = "session_end"
	EventFavoriteAdded    = "favorite_added"
	EventFavoriteRemoved  = "favorite_removed"
	EventNotificationOpen = "notification_opened"
)

// requiredPayloadFields lists the field each event type must carry (presence,
// not value — §3.3). Types absent from the map have no required fields.
var requiredPayloadFields = map[string][]string{
	EventPageView:        {"path"},
	// product_view also accepts an OPTIONAL categoryId (additive, P-033) — not
	// required (old/offline/web clients omit it) — which enables P-031's
	// per-category popularity via a same-schema GROUP BY in RebuildPopular.
	EventProductView:     {"productId"},
	EventCategoryView:    {"categoryId"},
	EventSearch:          {"normalizedQuery"},
	EventVariantSelected: {"productId"},
	EventAddToCart:       {"variantId"},
	EventRemoveFromCart:  {"variantId"},
	EventPurchase:        {"orderId"},
	EventFavoriteAdded:   {"productId"},
	EventFavoriteRemoved: {"productId"},
}

// knownEventTypes is the validation set for ingest.
var knownEventTypes = func() map[string]struct{} {
	all := []string{
		EventPageView, EventProductView, EventCategoryView, EventSearch,
		EventFilterApplied, EventSortChanged, EventMegaMenuOpened, EventVariantSelected,
		EventScrollDepth, EventTimeOnPage, EventAddToCart, EventRemoveFromCart,
		EventPurchase, EventLogin, EventLogout, EventSessionStart, EventSessionEnd,
		EventFavoriteAdded, EventFavoriteRemoved, EventNotificationOpen,
	}
	m := make(map[string]struct{}, len(all))
	for _, t := range all {
		m[t] = struct{}{}
	}
	return m
}()

// IsKnownEventType reports whether t is in the locked taxonomy.
func IsKnownEventType(t string) bool {
	_, ok := knownEventTypes[t]
	return ok
}

// Event is one client-reported event before storage.
type Event struct {
	Type     string         `json:"type"`
	Payload  map[string]any `json:"payload"`
	ClientTs time.Time      `json:"clientTs"`
}

// IngestBatch is one ingest request: a session and its events. UserID is set by
// the handler from the bearer token when the caller is authenticated.
type IngestBatch struct {
	SessionID string
	UserID    *int64
	Events    []Event
}

// Consent is a user's analytics consent state (Decision 3).
type Consent struct {
	UserID           int64      `json:"-"`
	AnalyticsEnabled bool       `json:"analyticsEnabled"`
	ConsentedAt      *time.Time `json:"consentedAt,omitempty"`
	RevokedAt        *time.Time `json:"revokedAt,omitempty"`
}

// RecentlyViewedItem is a projection row (product enrichment happens in the
// handler via catalog.Service — never a cross-schema JOIN).
type RecentlyViewedItem struct {
	ProductID    int64     `json:"productId"`
	LastViewedAt time.Time `json:"lastViewedAt"`
	ViewCount    int       `json:"viewCount"`
}

var uuidRe = regexp.MustCompile(
	`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`,
)

// ValidSessionID reports whether s is UUID-shaped (§3.3).
func ValidSessionID(s string) bool { return uuidRe.MatchString(s) }

// ValidateBatch checks batch size + per-event type and required-field presence.
func ValidateBatch(b IngestBatch) error {
	if !ValidSessionID(b.SessionID) {
		return ErrInvalidSession
	}
	if len(b.Events) == 0 {
		return ErrEmptyBatch
	}
	if len(b.Events) > MaxBatchSize {
		return ErrBatchTooLarge
	}
	for _, e := range b.Events {
		if !IsKnownEventType(e.Type) {
			return ErrUnknownEventType
		}
		for _, f := range requiredPayloadFields[e.Type] {
			if _, ok := e.Payload[f]; !ok {
				return ErrMissingPayloadField
			}
		}
	}
	return nil
}

var searchNormalizeRe = regexp.MustCompile(`[^a-z0-9çğıöşü ]+`)
var multiSpaceRe = regexp.MustCompile(` +`)

// NormalizeSearchQuery applies the §3.2 raw-search-text stance (Option A —
// normalized intent only): lowercase, strip non-alphanumeric (Turkish letters
// kept), collapse whitespace, truncate to 50 chars. Used client-side; mirrored
// here so the server can defensively re-normalize and never persist raw text.
func NormalizeSearchQuery(raw string) string {
	s := strings.ToLower(strings.TrimSpace(raw))
	s = searchNormalizeRe.ReplaceAllString(s, "")
	s = multiSpaceRe.ReplaceAllString(s, " ")
	s = strings.TrimSpace(s)
	if len(s) > 50 {
		s = s[:50]
	}
	return s
}

// stripRawSearchText enforces Option A defensively: for search events, drop any
// raw-text keys a client might have sent, keeping only normalized intent.
func stripRawSearchText(e *Event) {
	if e.Type != EventSearch || e.Payload == nil {
		return
	}
	for _, k := range []string{"query", "rawQuery", "q", "text"} {
		delete(e.Payload, k)
	}
}
