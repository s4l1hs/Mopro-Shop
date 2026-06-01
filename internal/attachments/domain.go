package attachments

import "time"

// Entity types a photo can attach to (matches photo_attachments.entity_type).
const (
	EntityReview     = "review"
	EntityReturnItem = "return_item"
)

// Per-entity attachment limits.
const (
	MaxPhotosPerReview     = 5
	MaxPhotosPerReturnItem = 3
)

// PhotoAttachment is one uploaded photo. EntityID is nil while the photo is an
// orphan (uploaded but not yet attached to a review/return_item).
type PhotoAttachment struct {
	ID               int64     `json:"id"`
	StorageKey       string    `json:"storage_key"`
	ContentType      string    `json:"content_type"`
	ByteSize         int       `json:"byte_size"`
	WidthPx          int       `json:"width_px"`
	HeightPx         int       `json:"height_px"`
	UploadedByUserID int64     `json:"-"`
	EntityType       string    `json:"-"`
	EntityID         *int64    `json:"-"`
	SortOrder        int       `json:"sort_order"`
	CreatedAt        time.Time `json:"-"`
	PublicURL        string    `json:"public_url"`
}

// MaxPhotosFor returns the per-entity attachment cap.
func MaxPhotosFor(entityType string) int {
	if entityType == EntityReturnItem {
		return MaxPhotosPerReturnItem
	}
	return MaxPhotosPerReview
}
