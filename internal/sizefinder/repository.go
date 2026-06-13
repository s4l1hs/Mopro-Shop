package sizefinder

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/pkg/crypto"
)

// pgxRepository persists fit profiles (sizefinder_schema — own schema) and
// reads the standard charts (ref_schema — the allowed §5 shared-read).
// Every measurement column holds pkg/crypto.EncryptPII ciphertext; plaintext
// mm values exist only in memory (§6 — the 0093 order-address pattern).
type pgxRepository struct {
	pool *pgxpool.Pool
}

// NewRepository builds the pgx-backed Repository.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgxRepository{pool: pool}
}

// encMM encrypts an optional millimetre value; nil stays nil (column NULL).
func encMM(v *int) (*string, error) {
	if v == nil {
		return nil, nil
	}
	c, err := crypto.EncryptPII(strconv.Itoa(*v))
	if err != nil {
		return nil, err
	}
	return &c, nil
}

// decMM decrypts an optional ciphertext back to millimetres.
func decMM(c *string) (*int, error) {
	if c == nil || *c == "" {
		return nil, nil
	}
	plain, err := crypto.DecryptPII(*c)
	if err != nil {
		return nil, err
	}
	v, err := strconv.Atoi(plain)
	if err != nil {
		return nil, err
	}
	return &v, nil
}

func (r *pgxRepository) UpsertProfile(ctx context.Context, p FitProfile) error {
	chest, err := encMM(p.ChestMM)
	if err != nil {
		return fmt.Errorf("sizefinder.repo: encrypt chest: %w", err)
	}
	waist, err := encMM(p.WaistMM)
	if err != nil {
		return fmt.Errorf("sizefinder.repo: encrypt waist: %w", err)
	}
	hip, err := encMM(p.HipMM)
	if err != nil {
		return fmt.Errorf("sizefinder.repo: encrypt hip: %w", err)
	}
	inseam, err := encMM(p.InseamMM)
	if err != nil {
		return fmt.Errorf("sizefinder.repo: encrypt inseam: %w", err)
	}
	height, err := encMM(p.HeightMM)
	if err != nil {
		return fmt.Errorf("sizefinder.repo: encrypt height: %w", err)
	}
	weight, err := encMM(p.WeightG) // grams, same EncryptPII envelope
	if err != nil {
		return fmt.Errorf("sizefinder.repo: encrypt weight: %w", err)
	}
	gender := p.Gender
	if gender == "" {
		gender = GenderUnspecified
	}
	_, err = r.pool.Exec(ctx,
		`INSERT INTO sizefinder_schema.fit_profiles
		   (user_id, chest_enc, waist_enc, hip_enc, inseam_enc, height_enc,
		    weight_enc, gender, fit_pref, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
		 ON CONFLICT (user_id) DO UPDATE SET
		   chest_enc = EXCLUDED.chest_enc,
		   waist_enc = EXCLUDED.waist_enc,
		   hip_enc = EXCLUDED.hip_enc,
		   inseam_enc = EXCLUDED.inseam_enc,
		   height_enc = EXCLUDED.height_enc,
		   weight_enc = EXCLUDED.weight_enc,
		   gender = EXCLUDED.gender,
		   fit_pref = EXCLUDED.fit_pref,
		   updated_at = now()`,
		p.UserID, chest, waist, hip, inseam, height, weight, gender, p.FitPref,
	)
	if err != nil {
		return fmt.Errorf("sizefinder.repo: UpsertProfile: %w", err)
	}
	return nil
}

func (r *pgxRepository) GetProfile(ctx context.Context, userID int64) (FitProfile, error) {
	var (
		p                                         FitProfile
		chest, waist, hip, inseam, height, weight *string
	)
	p.UserID = userID
	err := r.pool.QueryRow(ctx,
		`SELECT chest_enc, waist_enc, hip_enc, inseam_enc, height_enc, weight_enc,
		        gender, fit_pref, updated_at
		 FROM sizefinder_schema.fit_profiles WHERE user_id = $1`,
		userID,
	).Scan(&chest, &waist, &hip, &inseam, &height, &weight, &p.Gender, &p.FitPref, &p.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return FitProfile{}, ErrProfileNotFound
	}
	if err != nil {
		return FitProfile{}, fmt.Errorf("sizefinder.repo: GetProfile: %w", err)
	}
	if p.ChestMM, err = decMM(chest); err != nil {
		return FitProfile{}, fmt.Errorf("sizefinder.repo: decrypt chest: %w", err)
	}
	if p.WaistMM, err = decMM(waist); err != nil {
		return FitProfile{}, fmt.Errorf("sizefinder.repo: decrypt waist: %w", err)
	}
	if p.HipMM, err = decMM(hip); err != nil {
		return FitProfile{}, fmt.Errorf("sizefinder.repo: decrypt hip: %w", err)
	}
	if p.InseamMM, err = decMM(inseam); err != nil {
		return FitProfile{}, fmt.Errorf("sizefinder.repo: decrypt inseam: %w", err)
	}
	if p.HeightMM, err = decMM(height); err != nil {
		return FitProfile{}, fmt.Errorf("sizefinder.repo: decrypt height: %w", err)
	}
	if p.WeightG, err = decMM(weight); err != nil {
		return FitProfile{}, fmt.Errorf("sizefinder.repo: decrypt weight: %w", err)
	}
	return p, nil
}

func (r *pgxRepository) ChartFor(ctx context.Context, g GarmentType, gender string) ([]ChartRow, error) {
	// Match consumes the alpha-system rows for the resolved gender; the EU-numeric
	// rows (size_system='eu') are a parallel reference axis, not matched against.
	rows, err := r.pool.Query(ctx,
		`SELECT garment_type, size_label, sort_rank, measurement, min_mm, max_mm
		 FROM ref_schema.size_charts
		 WHERE garment_type = $1 AND gender = $2 AND size_system = 'alpha'
		 ORDER BY sort_rank ASC, measurement ASC`,
		string(g), gender,
	)
	if err != nil {
		return nil, fmt.Errorf("sizefinder.repo: ChartFor: %w", err)
	}
	defer rows.Close()
	var out []ChartRow
	for rows.Next() {
		var c ChartRow
		var gt string
		if err := rows.Scan(&gt, &c.SizeLabel, &c.SortRank, &c.Measurement, &c.MinMM, &c.MaxMM); err != nil {
			return nil, fmt.Errorf("sizefinder.repo: scan chart row: %w", err)
		}
		c.GarmentType = GarmentType(gt)
		out = append(out, c)
	}
	return out, rows.Err()
}
