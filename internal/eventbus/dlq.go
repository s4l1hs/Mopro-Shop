package eventbus

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DLQThreshold is the number of failures (error + panic outcomes) for a single
// (stream, messageID, consumerGroup) triple that triggers DLQ insertion.
const DLQThreshold = 3

// DLQInsertResult categorises the outcome of DLQRepository.InsertIfThreshold.
type DLQInsertResult int

const (
	// DLQBelowThreshold: failure count < DLQThreshold; message stays in PEL for retry.
	DLQBelowThreshold DLQInsertResult = iota
	// DLQAlreadyExists: UNIQUE conflict — row was already inserted on a prior attempt
	// (typically because XACK failed after the first insert). Caller should retry XACK.
	DLQAlreadyExists
	// DLQInserted: first successful insertion. Caller must XACK and send Slack alert.
	DLQInserted
)

// ErrDLQNotOpen is returned when a MarkReplayed / MarkDismissed call targets a row
// that is not in status='open'. The caller should treat this as a no-op and warn.
var ErrDLQNotOpen = errors.New("dlq: row status is not 'open'")

// DLQRow represents one row in wallet_schema.event_dlq.
type DLQRow struct {
	ID                int64
	OriginalTopic     string
	OriginalMessageID string
	ConsumerGroup     string
	IdempotencyKey    string
	Payload           []byte // raw JSONB from DB (full Redis stream entry values)
	AttemptCount      int
	ErrorHistory      []byte // raw JSONB from DB ([{attempt_at,consumer_name,outcome,error?}])
	Status            string
	CreatedAt         time.Time
	ReplayedAt        *time.Time
	ReplayedBy        *string
	ReplayedMessageID *string
	DismissedAt       *time.Time
	DismissedBy       *string
	DismissalReason   *string
}

// DLQFilter narrows List queries.
type DLQFilter struct {
	Topic  string    // empty = all topics
	Since  time.Time // zero = no lower bound
	Status string    // empty = all statuses; "open" = hot path
}

// SlackPoster sends DLQ alert messages.
// Implemented by slackPosterAdapter (wrapping *pkg/slack.Client) in production
// and by stub types in tests.
type SlackPoster interface {
	PostDLQAlert(ctx context.Context, text string) error
}

// DLQRepository stores and queries wallet_schema.event_dlq rows.
// The InsertIfThreshold / CountInWindow methods are called on the wallet_user pool
// (fin-svc dispatch path). List / GetByID / MarkReplayed / MarkDismissed are called
// on the dlq_user pool (mopro CLI).
type DLQRepository interface {
	// InsertIfThreshold opens a READ COMMITTED transaction, selects prior attempt
	// rows for (stream, messageID, group) within the same transaction, builds
	// error_history (prior rows + currentAttempt), and inserts a DLQ row if the
	// total failure count >= DLQThreshold.
	//
	// Returns:
	//   (DLQBelowThreshold, 0, nil)          — count < threshold; no insert
	//   (DLQAlreadyExists, existingID, nil)   — UNIQUE conflict; XACK should be retried
	//   (DLQInserted, newID, nil)             — first insert; XACK + Slack required
	InsertIfThreshold(ctx context.Context, row DLQRow, current AttemptRow) (DLQInsertResult, int64, error)

	// CountInWindow returns the number of DLQ rows for topic created within the
	// last windowMin minutes. Used for SEV2 storm detection.
	CountInWindow(ctx context.Context, topic string, windowMin int) (int, error)

	// List returns DLQ rows matching filter, ordered by created_at ASC.
	List(ctx context.Context, filter DLQFilter) ([]DLQRow, error)

	// GetByID returns a single DLQ row. Returns pgx.ErrNoRows if not found.
	GetByID(ctx context.Context, dlqID int64) (DLQRow, error)

	// MarkReplayed transitions status 'open' → 'replayed'. Sets replayed_at,
	// replayed_by, replayed_message_id. Returns ErrDLQNotOpen if not in 'open'.
	MarkReplayed(ctx context.Context, dlqID int64, by, replayedMsgID string) error

	// MarkDismissed transitions status 'open' → 'dismissed'. Sets dismissed_at,
	// dismissed_by, dismissal_reason. Returns ErrDLQNotOpen if not in 'open'.
	MarkDismissed(ctx context.Context, dlqID int64, by, reason string) error
}

// pgxDLQRepository implements DLQRepository against postgres-ledger.
type pgxDLQRepository struct {
	pool *pgxpool.Pool
}

// NewPgxDLQRepository constructs a DLQRepository backed by pool.
// Pass the wallet_user pool for dispatch-path operations;
// pass the dlq_user pool for CLI operations.
func NewPgxDLQRepository(pool *pgxpool.Pool) DLQRepository {
	return &pgxDLQRepository{pool: pool}
}

// InsertIfThreshold opens a READ COMMITTED transaction to snapshot prior attempt
// rows, then inserts the DLQ row if failure count >= DLQThreshold.
//
// The currentAttempt row is appended to error_history even though it may not yet
// be committed to event_delivery_attempts (the async worker may not have flushed
// it). This avoids a missing-final-error race while keeping attempt_count as the
// authoritative failure count.
func (r *pgxDLQRepository) InsertIfThreshold(
	ctx context.Context,
	row DLQRow,
	current AttemptRow,
) (DLQInsertResult, int64, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.ReadCommitted})
	if err != nil {
		return DLQBelowThreshold, 0, fmt.Errorf("dlq: begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Select prior attempt rows within the same READ COMMITTED snapshot.
	priorRows, err := tx.Query(ctx, `
		SELECT attempt_at, consumer_name, outcome, COALESCE(error_message, '')
		FROM wallet_schema.event_delivery_attempts
		WHERE stream = $1 AND message_id = $2 AND consumer_group = $3
		ORDER BY attempt_at ASC
		LIMIT 10`,
		row.OriginalTopic, row.OriginalMessageID, row.ConsumerGroup,
	)
	if err != nil {
		return DLQBelowThreshold, 0, fmt.Errorf("dlq: select attempts: %w", err)
	}

	type histEntry struct {
		AttemptAt    string `json:"attempt_at"`
		ConsumerName string `json:"consumer_name"`
		Outcome      string `json:"outcome"`
		Error        string `json:"error,omitempty"`
	}

	var failureCount int
	var history []histEntry
	for priorRows.Next() {
		var (
			attemptAt    time.Time
			consumerName string
			outcome      string
			errMsg       string
		)
		if err := priorRows.Scan(&attemptAt, &consumerName, &outcome, &errMsg); err != nil {
			priorRows.Close()
			return DLQBelowThreshold, 0, fmt.Errorf("dlq: scan attempt: %w", err)
		}
		e := histEntry{
			AttemptAt:    attemptAt.UTC().Format(time.RFC3339),
			ConsumerName: consumerName,
			Outcome:      outcome,
		}
		if errMsg != "" {
			e.Error = errMsg
		}
		history = append(history, e)
		if outcome == "error" || outcome == "panic" {
			failureCount++
		}
	}
	priorRows.Close()
	if err := priorRows.Err(); err != nil {
		return DLQBelowThreshold, 0, fmt.Errorf("dlq: iterate attempts: %w", err)
	}

	// Append current attempt (not yet in DB due to async worker lag).
	history = append(history, histEntry{
		AttemptAt:    time.Now().UTC().Format(time.RFC3339),
		ConsumerName: current.ConsumerName,
		Outcome:      current.Outcome,
		Error:        current.ErrorMessage,
	})
	if current.Outcome == "error" || current.Outcome == "panic" {
		failureCount++
	}

	if failureCount < DLQThreshold {
		_ = tx.Rollback(ctx)
		return DLQBelowThreshold, 0, nil
	}

	histJSON, _ := json.Marshal(history)

	// INSERT with ON CONFLICT DO NOTHING — idempotent re-entry after failed XACK.
	var newID int64
	err = tx.QueryRow(ctx, `
		INSERT INTO wallet_schema.event_dlq
		    (original_topic, original_message_id, consumer_group, idempotency_key,
		     payload, attempt_count, error_history)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (consumer_group, original_message_id) DO NOTHING
		RETURNING id`,
		row.OriginalTopic, row.OriginalMessageID, row.ConsumerGroup, row.IdempotencyKey,
		json.RawMessage(row.Payload), failureCount, json.RawMessage(histJSON),
	).Scan(&newID)

	if err == pgx.ErrNoRows {
		// UNIQUE conflict: DLQ row already exists from a prior cycle.
		_ = tx.Rollback(ctx)
		var existingID int64
		_ = r.pool.QueryRow(ctx,
			`SELECT id FROM wallet_schema.event_dlq
			 WHERE consumer_group = $1 AND original_message_id = $2`,
			row.ConsumerGroup, row.OriginalMessageID,
		).Scan(&existingID)
		return DLQAlreadyExists, existingID, nil
	}
	if err != nil {
		return DLQBelowThreshold, 0, fmt.Errorf("dlq: insert: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return DLQBelowThreshold, 0, fmt.Errorf("dlq: commit: %w", err)
	}
	return DLQInserted, newID, nil
}

// CountInWindow returns the number of DLQ rows for topic created within the last windowMin minutes.
func (r *pgxDLQRepository) CountInWindow(ctx context.Context, topic string, windowMin int) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM wallet_schema.event_dlq
		WHERE original_topic = $1
		  AND created_at > now() - make_interval(mins => $2)`,
		topic, windowMin,
	).Scan(&count)
	return count, err
}

// List returns DLQ rows matching filter, ordered oldest-first.
func (r *pgxDLQRepository) List(ctx context.Context, filter DLQFilter) ([]DLQRow, error) {
	q := `SELECT id, original_topic, original_message_id, consumer_group,
	             idempotency_key, payload, attempt_count, error_history,
	             status, created_at,
	             replayed_at, replayed_by, replayed_message_id,
	             dismissed_at, dismissed_by, dismissal_reason
	      FROM wallet_schema.event_dlq WHERE 1=1`
	args := make([]any, 0, 3)
	n := 1
	if filter.Topic != "" {
		q += fmt.Sprintf(" AND original_topic = $%d", n)
		args = append(args, filter.Topic)
		n++
	}
	if !filter.Since.IsZero() {
		q += fmt.Sprintf(" AND created_at >= $%d", n)
		args = append(args, filter.Since)
		n++
	}
	if filter.Status != "" {
		q += fmt.Sprintf(" AND status = $%d", n)
		args = append(args, filter.Status)
	}
	q += " ORDER BY created_at ASC"

	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("dlq: list query: %w", err)
	}
	defer rows.Close()

	var result []DLQRow
	for rows.Next() {
		row, err := scanDLQRow(rows)
		if err != nil {
			return nil, err
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

// GetByID returns a single DLQ row. Returns pgx.ErrNoRows if not found.
func (r *pgxDLQRepository) GetByID(ctx context.Context, dlqID int64) (DLQRow, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT id, original_topic, original_message_id, consumer_group,
		       idempotency_key, payload, attempt_count, error_history,
		       status, created_at,
		       replayed_at, replayed_by, replayed_message_id,
		       dismissed_at, dismissed_by, dismissal_reason
		FROM wallet_schema.event_dlq WHERE id = $1`, dlqID)
	if err != nil {
		return DLQRow{}, fmt.Errorf("dlq: get by id query: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return DLQRow{}, err
		}
		return DLQRow{}, pgx.ErrNoRows
	}
	return scanDLQRow(rows)
}

// MarkReplayed updates the DLQ row lifecycle for a successful replay.
func (r *pgxDLQRepository) MarkReplayed(ctx context.Context, dlqID int64, by, replayedMsgID string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE wallet_schema.event_dlq
		SET status = 'replayed', replayed_at = now(), replayed_by = $2, replayed_message_id = $3
		WHERE id = $1 AND status = 'open'`,
		dlqID, by, replayedMsgID)
	if err != nil {
		return fmt.Errorf("dlq: mark replayed: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrDLQNotOpen
	}
	return nil
}

// MarkDismissed marks the DLQ row as permanently dismissed.
func (r *pgxDLQRepository) MarkDismissed(ctx context.Context, dlqID int64, by, reason string) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE wallet_schema.event_dlq
		SET status = 'dismissed', dismissed_at = now(), dismissed_by = $2, dismissal_reason = $3
		WHERE id = $1 AND status = 'open'`,
		dlqID, by, reason)
	if err != nil {
		return fmt.Errorf("dlq: mark dismissed: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrDLQNotOpen
	}
	return nil
}

// scanDLQRow reads a DLQRow from a pgx.Rows cursor.
func scanDLQRow(rows pgx.Rows) (DLQRow, error) {
	var row DLQRow
	err := rows.Scan(
		&row.ID,
		&row.OriginalTopic, &row.OriginalMessageID, &row.ConsumerGroup,
		&row.IdempotencyKey, &row.Payload, &row.AttemptCount, &row.ErrorHistory,
		&row.Status, &row.CreatedAt,
		&row.ReplayedAt, &row.ReplayedBy, &row.ReplayedMessageID,
		&row.DismissedAt, &row.DismissedBy, &row.DismissalReason,
	)
	if err != nil {
		return DLQRow{}, fmt.Errorf("dlq: scan row: %w", err)
	}
	return row, nil
}

// noopDLQRepository discards all DLQ operations; used when no DB is configured.
type noopDLQRepository struct{}

// NewNoopDLQRepository returns a DLQRepository that silently discards all calls.
func NewNoopDLQRepository() DLQRepository { return noopDLQRepository{} }

func (noopDLQRepository) InsertIfThreshold(_ context.Context, _ DLQRow, _ AttemptRow) (DLQInsertResult, int64, error) {
	return DLQBelowThreshold, 0, nil
}
func (noopDLQRepository) CountInWindow(_ context.Context, _ string, _ int) (int, error) {
	return 0, nil
}
func (noopDLQRepository) List(_ context.Context, _ DLQFilter) ([]DLQRow, error) { return nil, nil }
func (noopDLQRepository) GetByID(_ context.Context, _ int64) (DLQRow, error) {
	return DLQRow{}, pgx.ErrNoRows
}
func (noopDLQRepository) MarkReplayed(_ context.Context, _ int64, _, _ string) error  { return nil }
func (noopDLQRepository) MarkDismissed(_ context.Context, _ int64, _, _ string) error { return nil }
