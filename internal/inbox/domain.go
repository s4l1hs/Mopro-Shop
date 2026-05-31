// Package inbox is the core-svc user-facing notification inbox: per-user
// notifications, channel preferences, and push-token registration. It owns
// inbox_schema. (Distinct from jobs-svc's internal/notification, which handles
// Slack drift alerts.)
package inbox

import "time"

// Notification types (also used as preference categories, plus "general").
const (
	TypeOrderStatus  = "order_status"
	TypeReturnUpdate = "return_update"
	TypeSecurity     = "security"
	TypeMarketing    = "marketing"
	TypeSystem       = "system"
)

// Preference channels.
const (
	ChannelInApp = "in_app"
	ChannelEmail = "email"
	ChannelPush  = "push"
)

// PrefCategories are the categories surfaced in the preferences matrix.
var PrefCategories = []string{
	TypeOrderStatus,
	TypeReturnUpdate,
	TypeSecurity,
	TypeMarketing,
	"general",
}

// PrefChannels are the channels surfaced per category.
var PrefChannels = []string{ChannelInApp, ChannelEmail, ChannelPush}

// Notification is one user-targeted inbox row. title_key/body_key are
// easy_localization keys rendered client-side with body_params.
type Notification struct {
	ID         int64             `json:"id"`
	UserID     int64             `json:"user_id"`
	Type       string            `json:"type"`
	TitleKey   string            `json:"title_key"`
	BodyKey    string            `json:"body_key"`
	BodyParams map[string]string `json:"body_params"`
	DeepLink   *string           `json:"deep_link,omitempty"`
	IsRead     bool              `json:"is_read"`
	ReadAt     *time.Time        `json:"read_at,omitempty"`
	CreatedAt  time.Time         `json:"created_at"`
	ExpiresAt  *time.Time        `json:"expires_at,omitempty"`
}

// Preference is one (category, channel) toggle for a user.
type Preference struct {
	Category string `json:"category"`
	Channel  string `json:"channel"`
	Enabled  bool   `json:"enabled"`
}

// defaultEnabled returns the default toggle for a (category, channel) when no
// row is stored: transactional categories default on; marketing defaults off.
func defaultEnabled(category, _ string) bool {
	return category != TypeMarketing
}

// DefaultPreferences returns the full category×channel matrix with defaults.
func DefaultPreferences() []Preference {
	out := make([]Preference, 0, len(PrefCategories)*len(PrefChannels))
	for _, c := range PrefCategories {
		for _, ch := range PrefChannels {
			out = append(out, Preference{Category: c, Channel: ch, Enabled: defaultEnabled(c, ch)})
		}
	}
	return out
}
