package seller

import (
	"errors"
	"time"
)

// ErrSellerNotFound is returned for unknown or suspended sellers (callers map to 404).
var ErrSellerNotFound = errors.New("seller: not found")

// Seller is a storefront profile (seller_schema.sellers).
type Seller struct {
	ID              int64             `json:"id"`
	Slug            string            `json:"slug"`
	DisplayName     string            `json:"display_name"`
	BioTranslations map[string]string `json:"bio_translations"`
	LogoImageURL    *string           `json:"logo_image_url,omitempty"`
	BannerImageURL  *string           `json:"banner_image_url,omitempty"`
	ContactEmail    *string           `json:"contact_email,omitempty"`
	Status          string            `json:"status"`
	CreatedAt       time.Time         `json:"created_at"`
}
