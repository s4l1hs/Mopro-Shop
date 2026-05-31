package seller

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxRepository struct{ pool *pgxpool.Pool }

// NewRepository returns a Repository backed by a pgx pool (postgres-ecom).
func NewRepository(pool *pgxpool.Pool) Repository { return &pgxRepository{pool: pool} }

const sellerCols = `id, slug, display_name, bio_translations, logo_image_url,
	banner_image_url, contact_email, status, created_at`

func scanSeller(row pgx.Row) (Seller, error) {
	var s Seller
	var bio []byte
	if err := row.Scan(&s.ID, &s.Slug, &s.DisplayName, &bio, &s.LogoImageURL,
		&s.BannerImageURL, &s.ContactEmail, &s.Status, &s.CreatedAt); err != nil {
		return Seller{}, err
	}
	if len(bio) > 0 {
		_ = json.Unmarshal(bio, &s.BioTranslations)
	}
	return s, nil
}

func (r *pgxRepository) GetBySlug(ctx context.Context, slug string) (Seller, error) {
	s, err := scanSeller(r.pool.QueryRow(ctx,
		`SELECT `+sellerCols+` FROM seller_schema.sellers WHERE slug = $1 AND status = 'active'`, slug))
	if errors.Is(err, pgx.ErrNoRows) {
		return Seller{}, ErrSellerNotFound
	}
	return s, err
}

func (r *pgxRepository) GetByID(ctx context.Context, id int64) (Seller, error) {
	s, err := scanSeller(r.pool.QueryRow(ctx,
		`SELECT `+sellerCols+` FROM seller_schema.sellers WHERE id = $1 AND status = 'active'`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return Seller{}, ErrSellerNotFound
	}
	return s, err
}

func (r *pgxRepository) SellerIDForUser(ctx context.Context, userID int64) (int64, bool, error) {
	var sellerID int64
	err := r.pool.QueryRow(ctx,
		`SELECT seller_id FROM seller_schema.seller_users WHERE user_id = $1 LIMIT 1`, userID).Scan(&sellerID)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, false, nil
	}
	if err != nil {
		return 0, false, err
	}
	return sellerID, true, nil
}
