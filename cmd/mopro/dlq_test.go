package main

// White-box unit tests for the mopro dlq CLI helpers.
// Uses package main access to call unexported functions directly with stub repos
// — no real Postgres or Redis required.

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/eventbus"
)

// ── stubs ─────────────────────────────────────────────────────────────────────

type stubCLIDLQRepo struct {
	rows         []eventbus.DLQRow
	getByIDErr   error
	markReplayed []int64
	markDismiss  []int64
	markDismErr  error
}

func (s *stubCLIDLQRepo) InsertIfThreshold(_ context.Context, _ eventbus.DLQRow, _ eventbus.AttemptRow) (eventbus.DLQInsertResult, int64, error) {
	return eventbus.DLQBelowThreshold, 0, nil
}
func (s *stubCLIDLQRepo) CountInWindow(_ context.Context, _ string, _ int) (int, error) {
	return 0, nil
}
func (s *stubCLIDLQRepo) List(_ context.Context, _ eventbus.DLQFilter) ([]eventbus.DLQRow, error) {
	return s.rows, nil
}
func (s *stubCLIDLQRepo) GetByID(_ context.Context, id int64) (eventbus.DLQRow, error) {
	if s.getByIDErr != nil {
		return eventbus.DLQRow{}, s.getByIDErr
	}
	for _, r := range s.rows {
		if r.ID == id {
			return r, nil
		}
	}
	return eventbus.DLQRow{}, pgx.ErrNoRows
}
func (s *stubCLIDLQRepo) MarkReplayed(_ context.Context, id int64, _, _ string) error {
	s.markReplayed = append(s.markReplayed, id)
	return nil
}
func (s *stubCLIDLQRepo) MarkDismissed(_ context.Context, id int64, _, _ string) error {
	if s.markDismErr != nil {
		return s.markDismErr
	}
	s.markDismiss = append(s.markDismiss, id)
	return nil
}

// sampleRow builds a representative DLQRow for table / JSON tests.
func sampleRow() eventbus.DLQRow {
	payload, _ := json.Marshal(map[string]string{"order_id": "42"})
	errHistory, _ := json.Marshal([]map[string]string{{"error": "timeout"}})
	return eventbus.DLQRow{
		ID:                7,
		OriginalTopic:     "ecom.order.delivered.v1",
		OriginalMessageID: "1715856930000-0",
		ConsumerGroup:     "cashback-engine",
		IdempotencyKey:    "idem-cashback-001",
		Payload:           payload,
		ErrorHistory:      errHistory,
		AttemptCount:      3,
		Status:            "open",
		CreatedAt:         time.Date(2026, 1, 15, 10, 0, 0, 0, time.UTC),
	}
}

// ── Test 1: printDLQTable renders expected columns ────────────────────────────

func TestDLQCLI_List_TextFormat(t *testing.T) {
	var buf bytes.Buffer
	rows := []eventbus.DLQRow{sampleRow()}
	printDLQTable(&buf, rows)

	out := buf.String()
	for _, want := range []string{"ID", "TOPIC", "GROUP", "STATUS", "ATTEMPTS", "7", "cashback-engine", "open"} {
		if !strings.Contains(out, want) {
			t.Errorf("table output missing %q:\n%s", want, out)
		}
	}
}

// ── Test 2: dlqRowsToJSON serialises required fields ─────────────────────────

func TestDLQCLI_List_JSONFormat(t *testing.T) {
	rows := []eventbus.DLQRow{sampleRow()}
	jsonRows := dlqRowsToJSON(rows)

	if len(jsonRows) != 1 {
		t.Fatalf("expected 1 JSON row, got %d", len(jsonRows))
	}
	m := jsonRows[0]

	checkField := func(key string, want interface{}) {
		t.Helper()
		got, ok := m[key]
		if !ok {
			t.Errorf("missing key %q in JSON output", key)
			return
		}
		// Convert both to string for simple equality check.
		if fmt.Sprint(got) != fmt.Sprint(want) {
			t.Errorf("key %q: want %v, got %v", key, want, got)
		}
	}
	checkField("id", int64(7))
	checkField("original_topic", "ecom.order.delivered.v1")
	checkField("consumer_group", "cashback-engine")
	checkField("status", "open")
	checkField("attempt_count", 3)
	if _, ok := m["payload"]; !ok {
		t.Error("JSON row missing 'payload' key")
	}
}

// ── Test 3: replaySingle dry-run prints preview and makes no writes ───────────

func TestDLQCLI_Replay_DryRun_NoWrites(t *testing.T) {
	repo := &stubCLIDLQRepo{rows: []eventbus.DLQRow{sampleRow()}}

	var out, errOut bytes.Buffer
	replaySingle(context.Background(), repo, 7, "tester", true, &out, &errOut)

	if errOut.Len() > 0 {
		t.Errorf("unexpected stderr output: %q", errOut.String())
	}
	got := out.String()
	for _, want := range []string{"DRY RUN", "7", "ecom.order.delivered.v1", "No changes made"} {
		if !strings.Contains(got, want) {
			t.Errorf("dry-run output missing %q:\n%s", want, got)
		}
	}
	// No writes should have been made.
	if len(repo.markReplayed) != 0 {
		t.Errorf("dry-run must not call MarkReplayed; got %v", repo.markReplayed)
	}
}

// ── Test 4: replaySingle rejects a non-open row and writes to errOut ──────────

func TestDLQCLI_Replay_AlreadyReplayed_Errors(t *testing.T) {
	replayedBy := "ops"
	replayedMsgID := "99-0"
	row := sampleRow()
	row.Status = "replayed"
	row.ReplayedBy = &replayedBy
	row.ReplayedMessageID = &replayedMsgID

	repo := &stubCLIDLQRepo{rows: []eventbus.DLQRow{row}}

	// Intercept osExit so the test process does not actually exit.
	orig := osExit
	var capturedCode int
	osExit = func(code int) { capturedCode = code }
	defer func() { osExit = orig }()

	var out, errOut bytes.Buffer
	replaySingle(context.Background(), repo, 7, "tester", false, &out, &errOut)

	if capturedCode != 1 {
		t.Errorf("want osExit(1), got osExit(%d)", capturedCode)
	}
	if !strings.Contains(errOut.String(), "not 'open'") {
		t.Errorf("errOut missing 'not open' message: %q", errOut.String())
	}
	if len(repo.markReplayed) != 0 {
		t.Errorf("MarkReplayed must not be called for non-open row")
	}
}

// ── Test 5: runDLQDismissCore calls MarkDismissed and prints success ──────────

func TestDLQCLI_Dismiss_SetsFields(t *testing.T) {
	repo := &stubCLIDLQRepo{}

	var out, errOut bytes.Buffer
	runDLQDismissCore(context.Background(), 42, "ops-user", "known flaky", repo, &out, &errOut)

	if errOut.Len() > 0 {
		t.Errorf("unexpected stderr: %q", errOut.String())
	}
	got := out.String()
	if !strings.Contains(got, "dismissed DLQ #42") {
		t.Errorf("stdout missing success message: %q", got)
	}
	if !strings.Contains(got, "known flaky") {
		t.Errorf("stdout missing reason: %q", got)
	}
	if len(repo.markDismiss) != 1 || repo.markDismiss[0] != 42 {
		t.Errorf("MarkDismissed must be called with id=42; got %v", repo.markDismiss)
	}
}
