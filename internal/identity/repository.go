package identity

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PgxRepository is the pgx/v5 implementation of Repository.
type PgxRepository struct {
	pool *pgxpool.Pool
}

// NewRepository returns a PgxRepository backed by the given connection pool.
func NewRepository(pool *pgxpool.Pool) *PgxRepository {
	return &PgxRepository{pool: pool}
}

// ── User reads ────────────────────────────────────────────────────────────────

func (r *PgxRepository) FindUserByPhoneHash(ctx context.Context, phoneHash []byte) (User, error) {
	const q = `
		SELECT id, phone_hash, phone_enc, COALESCE(email_enc,''), name, locale, status,
		       created_at, updated_at, deleted_at
		FROM identity_schema.users
		WHERE phone_hash = $1`
	return r.scanUser(r.pool.QueryRow(ctx, q, phoneHash))
}

func (r *PgxRepository) GetUser(ctx context.Context, id int64) (User, error) {
	const q = `
		SELECT id, phone_hash, phone_enc, COALESCE(email_enc,''), name, locale, status,
		       created_at, updated_at, deleted_at
		FROM identity_schema.users
		WHERE id = $1`
	return r.scanUser(r.pool.QueryRow(ctx, q, id))
}

func (r *PgxRepository) scanUser(row pgx.Row) (User, error) {
	var u User
	err := row.Scan(
		&u.ID, &u.PhoneHash, &u.PhoneEnc, &u.EmailEnc,
		&u.Name, &u.Locale, &u.Status,
		&u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrUserNotFound
	}
	return u, err
}

// ── OTP ───────────────────────────────────────────────────────────────────────

func (r *PgxRepository) CreateOTP(ctx context.Context, otp OTP) error {
	const q = `
		INSERT INTO identity_schema.otp_codes
		       (phone_hash, purpose, code_hash, expires_at)
		VALUES ($1,         $2,      $3,        $4)`
	_, err := r.pool.Exec(ctx, q, otp.PhoneHash, otp.Purpose, otp.CodeHash, otp.ExpiresAt)
	return err
}

func (r *PgxRepository) FindLatestOTP(ctx context.Context, phoneHash []byte, purpose string) (OTP, error) {
	const q = `
		SELECT id, phone_hash, purpose, code_hash, created_at, expires_at, verified_at
		FROM identity_schema.otp_codes
		WHERE phone_hash = $1 AND purpose = $2 AND verified_at IS NULL
		ORDER BY expires_at DESC
		LIMIT 1`
	var o OTP
	err := r.pool.QueryRow(ctx, q, phoneHash, purpose).Scan(
		&o.ID, &o.PhoneHash, &o.Purpose, &o.CodeHash,
		&o.CreatedAt, &o.ExpiresAt, &o.VerifiedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return OTP{}, ErrOTPNotFound
	}
	return o, err
}

// MarkOTPVerified marks a single OTP record as used.
func (r *PgxRepository) MarkOTPVerified(ctx context.Context, otpID int64) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE identity_schema.otp_codes SET verified_at = now() WHERE id = $1 AND verified_at IS NULL`,
		otpID,
	)
	if err != nil {
		return fmt.Errorf("identity repo: mark otp verified: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrOTPAlreadyUsed
	}
	return nil
}

// MarkOTPVerifiedAndCreateSession runs atomically:
// 1. marks otp_codes.verified_at
// 2. upserts the user row
// 3. inserts a refresh_token
func (r *PgxRepository) MarkOTPVerifiedAndCreateSession(
	ctx context.Context,
	otpID int64,
	phoneHash []byte,
	phoneEnc string,
	market string,
	defaultLocale string,
	newToken RefreshToken,
) (User, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return User{}, fmt.Errorf("identity repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	// 1. Mark OTP verified — fail if already verified (concurrent double-submit).
	tag, err := tx.Exec(ctx,
		`UPDATE identity_schema.otp_codes SET verified_at = now() WHERE id = $1 AND verified_at IS NULL`,
		otpID,
	)
	if err != nil {
		return User{}, fmt.Errorf("identity repo: mark otp verified: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return User{}, ErrOTPAlreadyUsed
	}

	// 2. Upsert user (first-time login creates the row).
	var u User
	err = tx.QueryRow(ctx, `
		INSERT INTO identity_schema.users (phone_hash, phone_enc, locale)
		VALUES ($1, $2, $3)
		ON CONFLICT (phone_hash) DO UPDATE
		  SET updated_at = now()
		RETURNING id, phone_hash, phone_enc, COALESCE(email_enc,''), name, locale, status,
		          created_at, updated_at, deleted_at`,
		phoneHash, phoneEnc, defaultLocale,
	).Scan(
		&u.ID, &u.PhoneHash, &u.PhoneEnc, &u.EmailEnc,
		&u.Name, &u.Locale, &u.Status,
		&u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
	)
	if err != nil {
		return User{}, fmt.Errorf("identity repo: upsert user: %w", err)
	}

	// 3. Insert refresh token.
	_, err = tx.Exec(ctx, `
		INSERT INTO identity_schema.refresh_tokens
		       (user_id, token_hash, family_root, expires_at)
		VALUES ($1,      $2,         $3,          $4)`,
		u.ID, newToken.TokenHash, newToken.FamilyRoot, newToken.ExpiresAt,
	)
	if err != nil {
		return User{}, fmt.Errorf("identity repo: insert refresh token: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return User{}, fmt.Errorf("identity repo: commit: %w", err)
	}
	return u, nil
}

// ── Refresh tokens ────────────────────────────────────────────────────────────

func (r *PgxRepository) FindTokenByHash(ctx context.Context, tokenHash string) (RefreshToken, error) {
	const q = `
		SELECT id, user_id, token_hash, family_root, issued_at, expires_at, revoked_at, COALESCE(revoked_reason,'')
		FROM identity_schema.refresh_tokens
		WHERE token_hash = $1`
	var t RefreshToken
	err := r.pool.QueryRow(ctx, q, tokenHash).Scan(
		&t.ID, &t.UserID, &t.TokenHash, &t.FamilyRoot,
		&t.IssuedAt, &t.ExpiresAt, &t.RevokedAt, &t.RevokedReason,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return RefreshToken{}, ErrTokenNotFound
	}
	return t, err
}

// RotateRefreshToken atomically revokes the current token and inserts a successor.
// If the current token is already revoked, the full family is revoked and ErrTokenFamilyRevoked is returned.
func (r *PgxRepository) RotateRefreshToken(
	ctx context.Context,
	currentTokenHash string,
	newToken RefreshToken,
) (User, RefreshToken, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return User{}, RefreshToken{}, fmt.Errorf("identity repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	// Lock and read current token.
	var cur RefreshToken
	err = tx.QueryRow(ctx, `
		SELECT id, user_id, token_hash, family_root, issued_at, expires_at, revoked_at, COALESCE(revoked_reason,'')
		FROM identity_schema.refresh_tokens
		WHERE token_hash = $1
		FOR UPDATE`,
		currentTokenHash,
	).Scan(
		&cur.ID, &cur.UserID, &cur.TokenHash, &cur.FamilyRoot,
		&cur.IssuedAt, &cur.ExpiresAt, &cur.RevokedAt, &cur.RevokedReason,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, RefreshToken{}, ErrTokenNotFound
	}
	if err != nil {
		return User{}, RefreshToken{}, fmt.Errorf("identity repo: select token for update: %w", err)
	}

	// Theft detection: token already revoked → revoke entire family.
	if cur.RevokedAt != nil {
		_, _ = tx.Exec(ctx, `
			UPDATE identity_schema.refresh_tokens
			SET revoked_at = now(), revoked_reason = 'theft'
			WHERE family_root = $1 AND revoked_at IS NULL`,
			cur.FamilyRoot,
		)
		_ = tx.Commit(ctx)
		return User{}, RefreshToken{}, ErrTokenFamilyRevoked
	}

	if time.Now().After(cur.ExpiresAt) {
		return User{}, RefreshToken{}, ErrTokenExpired
	}

	// Revoke current token.
	_, err = tx.Exec(ctx, `
		UPDATE identity_schema.refresh_tokens
		SET revoked_at = now(), revoked_reason = 'rotation'
		WHERE id = $1`,
		cur.ID,
	)
	if err != nil {
		return User{}, RefreshToken{}, fmt.Errorf("identity repo: revoke current token: %w", err)
	}

	// Insert successor with same family_root.
	var created RefreshToken
	err = tx.QueryRow(ctx, `
		INSERT INTO identity_schema.refresh_tokens
		       (user_id, token_hash, family_root, expires_at)
		VALUES ($1,      $2,         $3,          $4)
		RETURNING id, user_id, token_hash, family_root, issued_at, expires_at, revoked_at, COALESCE(revoked_reason,'')`,
		cur.UserID, newToken.TokenHash, cur.FamilyRoot, newToken.ExpiresAt,
	).Scan(
		&created.ID, &created.UserID, &created.TokenHash, &created.FamilyRoot,
		&created.IssuedAt, &created.ExpiresAt, &created.RevokedAt, &created.RevokedReason,
	)
	if err != nil {
		return User{}, RefreshToken{}, fmt.Errorf("identity repo: insert successor token: %w", err)
	}

	// Fetch user.
	var u User
	err = tx.QueryRow(ctx, `
		SELECT id, phone_hash, phone_enc, COALESCE(email_enc,''), name, locale, status,
		       created_at, updated_at, deleted_at
		FROM identity_schema.users WHERE id = $1`,
		cur.UserID,
	).Scan(
		&u.ID, &u.PhoneHash, &u.PhoneEnc, &u.EmailEnc,
		&u.Name, &u.Locale, &u.Status,
		&u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
	)
	if err != nil {
		return User{}, RefreshToken{}, fmt.Errorf("identity repo: fetch user: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return User{}, RefreshToken{}, fmt.Errorf("identity repo: commit: %w", err)
	}
	return u, created, nil
}

func (r *PgxRepository) RevokeToken(ctx context.Context, tokenHash string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE identity_schema.refresh_tokens
		SET revoked_at = now(), revoked_reason = 'logout'
		WHERE token_hash = $1 AND revoked_at IS NULL`,
		tokenHash,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrTokenNotFound
	}
	return nil
}

func (r *PgxRepository) RevokeTokenFamily(ctx context.Context, familyRoot string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE identity_schema.refresh_tokens
		SET revoked_at = now(), revoked_reason = 'theft'
		WHERE family_root = $1 AND revoked_at IS NULL`,
		familyRoot,
	)
	return err
}

// ── User writes ───────────────────────────────────────────────────────────────

func (r *PgxRepository) UpdateUser(ctx context.Context, id int64, updates UserUpdates) (User, error) {
	// Build dynamic SET clause for only non-nil fields.
	// We always set updated_at (trigger also does this, but be explicit).
	setClauses := []string{"updated_at = now()"}
	args := []any{id}
	argIdx := 2

	if updates.Name != nil {
		setClauses = append(setClauses, fmt.Sprintf("name = $%d", argIdx))
		args = append(args, *updates.Name)
		argIdx++
	}
	if updates.Email != nil {
		setClauses = append(setClauses, fmt.Sprintf("email_enc = $%d", argIdx))
		args = append(args, *updates.Email) // pre-encrypted by service layer
		argIdx++
	}
	if updates.Locale != nil {
		setClauses = append(setClauses, fmt.Sprintf("locale = $%d", argIdx))
		args = append(args, *updates.Locale)
		argIdx++
	}

	set := ""
	for i, c := range setClauses {
		if i > 0 {
			set += ", "
		}
		set += c
	}

	q := fmt.Sprintf(`
		UPDATE identity_schema.users
		SET %s
		WHERE id = $1
		RETURNING id, phone_hash, phone_enc, COALESCE(email_enc,''), name, locale, status,
		          created_at, updated_at, deleted_at`, set)

	var u User
	err := r.pool.QueryRow(ctx, q, args...).Scan(
		&u.ID, &u.PhoneHash, &u.PhoneEnc, &u.EmailEnc,
		&u.Name, &u.Locale, &u.Status,
		&u.CreatedAt, &u.UpdatedAt, &u.DeletedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrUserNotFound
	}
	return u, err
}

// SoftDeleteWithRevoke atomically soft-deletes the user and revokes all active refresh tokens.
func (r *PgxRepository) SoftDeleteWithRevoke(ctx context.Context, userID int64) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("identity repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	_, err = tx.Exec(ctx, `
		UPDATE identity_schema.users
		SET status = 'deleted', deleted_at = now(), updated_at = now()
		WHERE id = $1`,
		userID,
	)
	if err != nil {
		return fmt.Errorf("identity repo: soft delete user: %w", err)
	}

	_, err = tx.Exec(ctx, `
		UPDATE identity_schema.refresh_tokens
		SET revoked_at = now(), revoked_reason = 'admin'
		WHERE user_id = $1 AND revoked_at IS NULL`,
		userID,
	)
	if err != nil {
		return fmt.Errorf("identity repo: revoke tokens on delete: %w", err)
	}

	return tx.Commit(ctx)
}

// ── Devices ───────────────────────────────────────────────────────────────────

func (r *PgxRepository) CreateDevice(ctx context.Context, userID int64, info DeviceInfo) (Device, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return Device{}, fmt.Errorf("identity repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	// Revoke any existing active registration for the same FCM token (device re-registered).
	_, err = tx.Exec(ctx, `
		UPDATE identity_schema.devices
		SET revoked_at = now()
		WHERE fcm_token = $1 AND revoked_at IS NULL`,
		info.FCMToken,
	)
	if err != nil {
		return Device{}, fmt.Errorf("identity repo: revoke old device: %w", err)
	}

	var d Device
	err = tx.QueryRow(ctx, `
		INSERT INTO identity_schema.devices (user_id, fcm_token, device_model, os_version)
		VALUES ($1, $2, $3, $4)
		RETURNING id, user_id, fcm_token, device_model, os_version, registered_at, revoked_at`,
		userID, info.FCMToken, info.DeviceModel, info.OSVersion,
	).Scan(
		&d.ID, &d.UserID, &d.FCMToken, &d.DeviceModel, &d.OSVersion,
		&d.RegisteredAt, &d.RevokedAt,
	)
	if err != nil {
		return Device{}, fmt.Errorf("identity repo: insert device: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return Device{}, fmt.Errorf("identity repo: commit: %w", err)
	}
	return d, nil
}

// ── Address repository methods ────────────────────────────────────────────────

func (r *PgxRepository) ListAddresses(ctx context.Context, userID int64) ([]Address, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, label, name_enc, phone_enc, full_address_enc,
		        COALESCE(neighborhood_enc, ''), district, city,
		        COALESCE(postal_code, ''), is_default, created_at, updated_at
		FROM identity_schema.addresses
		WHERE user_id = $1
		ORDER BY is_default DESC, id ASC`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("identity repo: list addresses: %w", err)
	}
	defer rows.Close()

	var addrs []Address
	for rows.Next() {
		var a Address
		if err := rows.Scan(
			&a.ID, &a.UserID, &a.Label, &a.Name, &a.Phone, &a.FullAddress,
			&a.Neighborhood, &a.District, &a.City,
			&a.PostalCode, &a.IsDefault, &a.CreatedAt, &a.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("identity repo: scan address: %w", err)
		}
		addrs = append(addrs, a)
	}
	if addrs == nil {
		addrs = []Address{}
	}
	return addrs, rows.Err()
}

func (r *PgxRepository) ClearDefaultAddresses(ctx context.Context, userID int64) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE identity_schema.addresses SET is_default = FALSE WHERE user_id = $1`,
		userID,
	)
	if err != nil {
		return fmt.Errorf("identity repo: clear defaults: %w", err)
	}
	return nil
}

func (r *PgxRepository) InsertAddress(ctx context.Context, userID int64, a AddressRow) (Address, error) {
	var result Address
	err := r.pool.QueryRow(ctx,
		`INSERT INTO identity_schema.addresses
		    (user_id, label, name_enc, phone_enc, full_address_enc,
		     neighborhood_enc, district, city, postal_code, is_default)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULLIF($9, ''), $10)
		RETURNING id, user_id, label, name_enc, phone_enc, full_address_enc,
		          COALESCE(neighborhood_enc, ''), district, city,
		          COALESCE(postal_code, ''), is_default, created_at, updated_at`,
		userID, a.Label, a.NameEnc, a.PhoneEnc, a.FullAddressEnc,
		nullIfEmpty(a.NeighborhoodEnc), a.District, a.City, a.PostalCode, a.IsDefault,
	).Scan(
		&result.ID, &result.UserID, &result.Label, &result.Name, &result.Phone,
		&result.FullAddress, &result.Neighborhood, &result.District, &result.City,
		&result.PostalCode, &result.IsDefault, &result.CreatedAt, &result.UpdatedAt,
	)
	if err != nil {
		return Address{}, fmt.Errorf("identity repo: insert address: %w", err)
	}
	return result, nil
}

func (r *PgxRepository) GetAddress(ctx context.Context, userID, addressID int64) (Address, error) {
	var a Address
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, label, name_enc, phone_enc, full_address_enc,
		        COALESCE(neighborhood_enc, ''), district, city,
		        COALESCE(postal_code, ''), is_default, created_at, updated_at
		FROM identity_schema.addresses
		WHERE id = $1 AND user_id = $2`,
		addressID, userID,
	).Scan(
		&a.ID, &a.UserID, &a.Label, &a.Name, &a.Phone, &a.FullAddress,
		&a.Neighborhood, &a.District, &a.City,
		&a.PostalCode, &a.IsDefault, &a.CreatedAt, &a.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Address{}, ErrAddressNotFound
		}
		return Address{}, fmt.Errorf("identity repo: get address: %w", err)
	}
	return a, nil
}

func (r *PgxRepository) UpdateAddress(ctx context.Context, userID, addressID int64, a AddressRow) (Address, error) {
	var result Address
	err := r.pool.QueryRow(ctx,
		`UPDATE identity_schema.addresses
		SET label = $3, name_enc = $4, phone_enc = $5, full_address_enc = $6,
		    neighborhood_enc = $7, district = $8, city = $9,
		    postal_code = NULLIF($10, ''), is_default = $11, updated_at = now()
		WHERE id = $1 AND user_id = $2
		RETURNING id, user_id, label, name_enc, phone_enc, full_address_enc,
		          COALESCE(neighborhood_enc, ''), district, city,
		          COALESCE(postal_code, ''), is_default, created_at, updated_at`,
		addressID, userID,
		a.Label, a.NameEnc, a.PhoneEnc, a.FullAddressEnc,
		nullIfEmpty(a.NeighborhoodEnc), a.District, a.City, a.PostalCode, a.IsDefault,
	).Scan(
		&result.ID, &result.UserID, &result.Label, &result.Name, &result.Phone,
		&result.FullAddress, &result.Neighborhood, &result.District, &result.City,
		&result.PostalCode, &result.IsDefault, &result.CreatedAt, &result.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Address{}, ErrAddressNotFound
		}
		return Address{}, fmt.Errorf("identity repo: update address: %w", err)
	}
	return result, nil
}

func (r *PgxRepository) DeleteAddress(ctx context.Context, userID, addressID int64) error {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM identity_schema.addresses WHERE id = $1 AND user_id = $2`,
		addressID, userID,
	)
	if err != nil {
		return fmt.Errorf("identity repo: delete address: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrAddressNotFound
	}
	return nil
}

func nullIfEmpty(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}
