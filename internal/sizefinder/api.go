// Package sizefinder provides size recommendation logic for apparel (jobs-svc).
// Phase 1: encrypted fit profiles + garment-type standard charts + match.
// See docs/internal/size-fit.md.
package sizefinder

import "context"

// Service is the public interface of the sizefinder module.
type Service interface {
	// UpsertProfile validates + stores the user's measurements (encrypted at rest).
	UpsertProfile(ctx context.Context, p FitProfile) error
	// GetProfile returns the decrypted profile; ErrProfileNotFound when absent.
	GetProfile(ctx context.Context, userID int64) (FitProfile, error)
	// Recommend classifies the product title, loads the chart, and matches the
	// user's profile to a size. Never errors for absent profile / unclassifiable
	// title — those are statuses on the Recommendation.
	Recommend(ctx context.Context, userID int64, productTitle string) (Recommendation, error)
}

// Repository is the storage interface of the sizefinder module.
type Repository interface {
	UpsertProfile(ctx context.Context, p FitProfile) error
	GetProfile(ctx context.Context, userID int64) (FitProfile, error)
	ChartFor(ctx context.Context, g GarmentType) ([]ChartRow, error)
}
