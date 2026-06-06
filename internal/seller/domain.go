package seller

import (
	"errors"
	"time"
)

// ErrSellerNotFound is returned for unknown or suspended sellers (callers map to 404).
var ErrSellerNotFound = errors.New("seller: not found")

// Binding is a user's seller-account link (seller_users row + the bound active
// seller's public identity). Used to expose seller role on /me for client-side
// role detection (Tranche 5 seller dashboard).
type Binding struct {
	SellerID int64  `json:"seller_id"`
	Slug     string `json:"seller_slug"`
	Name     string `json:"seller_name"`
	Role     string `json:"role"` // 'owner' | 'staff'
}

// Seller is a storefront profile (seller_schema.sellers).
type Seller struct {
	ID              int64             `json:"id"`
	Slug            string            `json:"slug"`
	DisplayName     string            `json:"display_name"`
	BioTranslations map[string]string `json:"bio_translations"`
	LogoImageURL    *string           `json:"logo_image_url,omitempty"`
	BannerImageURL  *string           `json:"banner_image_url,omitempty"`
	ContactEmail    *string           `json:"contact_email,omitempty"`
	// DispatchCity is the normalized city key the seller ships from (P-034), the
	// origin input to shipping.EstimateETA for the PDP delivery estimate. nil =
	// no declared origin → estimator uses the conservative national fallback.
	DispatchCity *string   `json:"dispatch_city,omitempty"`
	Status       string    `json:"status"`
	CreatedAt    time.Time `json:"created_at"`
}
