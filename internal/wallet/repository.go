package wallet

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/ledger"
)

type walletRepository struct {
	pool *pgxpool.Pool
}

// NewRepository constructs a Repository backed by pool.
// pool MUST point at PgBouncer (never direct to Postgres).
func NewRepository(pool *pgxpool.Pool) Repository {
	return &walletRepository{pool: pool}
}

// WithTx runs fn inside a transaction at the given isolation level.
// Retries up to 3 times on pgError 40001 (serialization failure).
func (r *walletRepository) WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	const maxRetries = 3
	for attempt := 0; attempt < maxRetries; attempt++ {
		tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: level})
		if err != nil {
			return fmt.Errorf("wallet: begin tx: %w", err)
		}
		err = fn(tx)
		if err != nil {
			_ = tx.Rollback(ctx)
			if isSerializationFailure(err) && attempt < maxRetries-1 {
				continue
			}
			return err
		}
		if commitErr := tx.Commit(ctx); commitErr != nil {
			if isSerializationFailure(commitErr) && attempt < maxRetries-1 {
				continue
			}
			return fmt.Errorf("wallet: commit tx: %w", commitErr)
		}
		return nil
	}
	return ErrMaxRetriesExceeded
}

// InsertTransaction inserts a wallet_schema.transactions row within tx.
// Returns (0, ledger.ErrDuplicateIdempotency) on UNIQUE constraint violation (23505).
// Uses a SAVEPOINT so that a 23505 error does not abort the outer transaction;
// the caller can then look up the existing txnID and commit the (no-op) tx cleanly.
func (r *walletRepository) InsertTransaction(ctx context.Context, tx pgx.Tx, txn ledger.Transaction) (int64, error) {
	var id int64
	var fxPairID *string
	if txn.FxPairID != "" {
		fxPairID = &txn.FxPairID
	}
	var reference *string
	if txn.Reference != "" {
		reference = &txn.Reference
	}

	if _, err := tx.Exec(ctx, "SAVEPOINT insert_txn"); err != nil {
		return 0, fmt.Errorf("wallet: savepoint: %w", err)
	}

	err := tx.QueryRow(ctx,
		`INSERT INTO wallet_schema.transactions (type, reference, fx_pair_id, idempotency_key)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id`,
		txn.Type, reference, fxPairID, txn.IdempotencyKey,
	).Scan(&id)
	if err != nil {
		// Always roll back to the savepoint to keep the outer tx healthy.
		_, _ = tx.Exec(ctx, "ROLLBACK TO SAVEPOINT insert_txn")
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return 0, ledger.ErrDuplicateIdempotency
		}
		return 0, fmt.Errorf("wallet: insert transaction: %w", err)
	}

	if _, err := tx.Exec(ctx, "RELEASE SAVEPOINT insert_txn"); err != nil {
		return 0, fmt.Errorf("wallet: release savepoint: %w", err)
	}
	return id, nil
}

// GetTransactionByIdempotencyKey reads the id of a committed transaction from the pool.
// Called after ErrDuplicateIdempotency to return the original txnID.
func (r *walletRepository) GetTransactionByIdempotencyKey(ctx context.Context, key string) (int64, error) {
	var id int64
	err := r.pool.QueryRow(ctx,
		`SELECT id FROM wallet_schema.transactions WHERE idempotency_key = $1`,
		key,
	).Scan(&id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, fmt.Errorf("wallet: transaction with key %q not found: %w", key, ErrAccountNotFound)
		}
		return 0, fmt.Errorf("wallet: get transaction by key: %w", err)
	}
	return id, nil
}

// InsertEntry inserts one wallet_schema.ledger_entries row within tx.
// The DEFERRABLE trigger fires at COMMIT — all D and C entries for txnID MUST be
// present before the caller commits.
func (r *walletRepository) InsertEntry(ctx context.Context, tx pgx.Tx, txnID int64, e ledger.Entry) error {
	_, err := tx.Exec(ctx,
		`INSERT INTO wallet_schema.ledger_entries (transaction_id, account_id, direction, amount_minor)
		 VALUES ($1, $2, $3, $4)`,
		txnID, e.AccountID, string(e.Direction), e.AmountMinor,
	)
	if err != nil {
		return fmt.Errorf("wallet: insert entry account=%d dir=%s: %w", e.AccountID, e.Direction, err)
	}
	return nil
}

// GetAccountCurrencies returns a map[accountID]currency for the given IDs.
// Reads from pool (not tx) to avoid snapshot isolation surprises with newly-created accounts.
// Returns a partial map if some IDs do not exist.
func (r *walletRepository) GetAccountCurrencies(ctx context.Context, accountIDs []int64) (map[int64]string, error) {
	if len(accountIDs) == 0 {
		return map[int64]string{}, nil
	}
	rows, err := r.pool.Query(ctx,
		`SELECT id, currency FROM wallet_schema.accounts WHERE id = ANY($1)`,
		accountIDs,
	)
	if err != nil {
		return nil, fmt.Errorf("wallet: get account currencies: %w", err)
	}
	defer rows.Close()
	result := make(map[int64]string, len(accountIDs))
	for rows.Next() {
		var id int64
		var cur string
		if err := rows.Scan(&id, &cur); err != nil {
			return nil, fmt.Errorf("wallet: scan account currency: %w", err)
		}
		result[id] = cur
	}
	return result, rows.Err()
}

// FindAccountByType looks up a platform account by (type, currency).
func (r *walletRepository) FindAccountByType(ctx context.Context, accountType, currency string) (Account, error) {
	var acct Account
	var ownerID *int64
	err := r.pool.QueryRow(ctx,
		`SELECT id, type, owner_type, owner_id, currency, status, created_at
		 FROM wallet_schema.accounts
		 WHERE type = $1 AND currency = $2
		   AND owner_type = 'platform' AND owner_id IS NULL
		 LIMIT 1`,
		accountType, currency,
	).Scan(&acct.ID, &acct.Type, &acct.OwnerType, &ownerID, &acct.Currency, &acct.Status, &acct.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Account{}, fmt.Errorf("wallet: FindAccountByType %q/%q: %w", accountType, currency, ErrAccountNotFound)
		}
		return Account{}, fmt.Errorf("wallet: FindAccountByType: %w", err)
	}
	acct.OwnerID = ownerID
	return acct, nil
}

// FindAccountByOwner looks up a per-entity account by (ownerType, ownerID, currency).
func (r *walletRepository) FindAccountByOwner(ctx context.Context, ownerType string, ownerID int64, currency string) (Account, error) {
	var acct Account
	var dbOwnerID *int64
	err := r.pool.QueryRow(ctx,
		`SELECT id, type, owner_type, owner_id, currency, status, created_at
		 FROM wallet_schema.accounts
		 WHERE owner_type = $1 AND owner_id = $2 AND currency = $3 AND status = 'active'
		 LIMIT 1`,
		ownerType, ownerID, currency,
	).Scan(&acct.ID, &acct.Type, &acct.OwnerType, &dbOwnerID, &acct.Currency, &acct.Status, &acct.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Account{}, ErrAccountNotFound
		}
		return Account{}, fmt.Errorf("wallet: FindAccountByOwner: %w", err)
	}
	acct.OwnerID = dbOwnerID
	return acct, nil
}

// FindAccountByOwnerAnyStatus looks up a per-entity account by (ownerType, ownerID, currency)
// without filtering by status. Returns ErrAccountNotFound if no row exists.
func (r *walletRepository) FindAccountByOwnerAnyStatus(ctx context.Context, ownerType string, ownerID int64, currency string) (Account, error) {
	var acct Account
	var dbOwnerID *int64
	err := r.pool.QueryRow(ctx,
		`SELECT id, type, owner_type, owner_id, currency, status, created_at
		 FROM wallet_schema.accounts
		 WHERE owner_type = $1 AND owner_id = $2 AND currency = $3
		 LIMIT 1`,
		ownerType, ownerID, currency,
	).Scan(&acct.ID, &acct.Type, &acct.OwnerType, &dbOwnerID, &acct.Currency, &acct.Status, &acct.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Account{}, ErrAccountNotFound
		}
		return Account{}, fmt.Errorf("wallet: FindAccountByOwnerAnyStatus: %w", err)
	}
	acct.OwnerID = dbOwnerID
	return acct, nil
}

// GetAccount fetches a wallet_schema.accounts row by primary key, regardless of status.
// Returns ErrAccountNotFound if no row exists.
func (r *walletRepository) GetAccount(ctx context.Context, accountID int64) (Account, error) {
	var acct Account
	var dbOwnerID *int64
	err := r.pool.QueryRow(ctx,
		`SELECT id, type, owner_type, owner_id, currency, status, created_at
		 FROM wallet_schema.accounts
		 WHERE id = $1`,
		accountID,
	).Scan(&acct.ID, &acct.Type, &acct.OwnerType, &dbOwnerID, &acct.Currency, &acct.Status, &acct.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Account{}, ErrAccountNotFound
		}
		return Account{}, fmt.Errorf("wallet: GetAccount id=%d: %w", accountID, err)
	}
	acct.OwnerID = dbOwnerID
	return acct, nil
}

// InsertAccount inserts a new per-entity account row within tx.
// Uses ON CONFLICT accounts_owner_currency_uq DO NOTHING for race safety.
// Returns (0, nil) when another goroutine already created the account (caller re-SELECTs).
func (r *walletRepository) InsertAccount(ctx context.Context, tx pgx.Tx, acct Account) (int64, error) {
	var id int64
	err := tx.QueryRow(ctx,
		`INSERT INTO wallet_schema.accounts (type, owner_type, owner_id, currency, status)
		 VALUES ($1, $2, $3, $4, $5)
		 ON CONFLICT (type, owner_type, owner_id, currency) WHERE owner_id IS NOT NULL
		 DO NOTHING
		 RETURNING id`,
		acct.Type, acct.OwnerType, acct.OwnerID, acct.Currency, acct.Status,
	).Scan(&id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// ON CONFLICT fired; concurrent goroutine already created the account.
			return 0, nil
		}
		return 0, fmt.Errorf("wallet: insert account: %w", err)
	}
	return id, nil
}

// GetBalanceMV reads balance_minor from the wallet_schema.balances materialized view.
// Returns 0 for accounts not yet included in the MV (newly created since last refresh).
func (r *walletRepository) GetBalanceMV(ctx context.Context, accountID int64) (int64, error) {
	var balance int64
	err := r.pool.QueryRow(ctx,
		`SELECT balance_minor FROM wallet_schema.balances WHERE account_id = $1`,
		accountID,
	).Scan(&balance)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, nil
		}
		return 0, fmt.Errorf("wallet: GetBalanceMV account=%d: %w", accountID, err)
	}
	return balance, nil
}

// GetBalanceStrict computes the live balance from wallet_schema.ledger_entries.
// Use only for withdrawal authorization paths (Phase 3+).
func (r *walletRepository) GetBalanceStrict(ctx context.Context, accountID int64) (int64, error) {
	var balance int64
	err := r.pool.QueryRow(ctx,
		`SELECT COALESCE(
		     SUM(CASE WHEN direction = 'C' THEN amount_minor ELSE -amount_minor END),
		     0)
		 FROM wallet_schema.ledger_entries
		 WHERE account_id = $1`,
		accountID,
	).Scan(&balance)
	if err != nil {
		return 0, fmt.Errorf("wallet: GetBalanceStrict account=%d: %w", accountID, err)
	}
	return balance, nil
}

func isSerializationFailure(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "40001"
}
