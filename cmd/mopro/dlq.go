package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"strconv"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/eventbus"
)

// osExit is a testable seam so CLI unit tests can intercept os.Exit calls.
var osExit = os.Exit

// runDLQ is the top-level dispatcher for `mopro dlq <subcommand>`.
func runDLQ(ctx context.Context, args []string) {
	if len(args) == 0 {
		dlqUsage(os.Stderr)
		os.Exit(1)
	}
	switch args[0] {
	case "list":
		runDLQList(ctx, args[1:], os.Stdout, os.Stderr)
	case "inspect":
		runDLQInspect(ctx, args[1:], os.Stdout, os.Stderr)
	case "replay":
		runDLQReplay(ctx, args[1:], os.Stdout, os.Stderr)
	case "dismiss":
		runDLQDismiss(ctx, args[1:], os.Stdout, os.Stderr)
	default:
		fmt.Fprintf(os.Stderr, "unknown dlq command: %s\n", args[0])
		dlqUsage(os.Stderr)
		os.Exit(1)
	}
}

// runDLQList prints a tabular or JSON listing of DLQ rows.
func runDLQList(ctx context.Context, args []string, out, _ io.Writer) {
	fs := flag.NewFlagSet("dlq list", flag.ExitOnError)
	topic := fs.String("topic", "", "filter by original_topic")
	since := fs.String("since", "", "filter rows created within duration (e.g. 1h, 30m, 7d)")
	status := fs.String("status", "open", "row status filter: open|replayed|dismissed|all")
	asJSON := fs.Bool("json", false, "output as JSON array")
	if err := fs.Parse(args); err != nil {
		log.Fatalf("dlq list: %v", err)
	}

	filter := eventbus.DLQFilter{Topic: *topic}
	if *since != "" {
		d, err := parseDuration(*since)
		if err != nil {
			log.Fatalf("dlq list --since: %v", err)
		}
		filter.Since = time.Now().Add(-d)
	}
	if *status != "all" {
		filter.Status = *status
	}

	repo := newDLQRepo(ctx)
	rows, err := repo.List(ctx, filter)
	if err != nil {
		log.Fatalf("dlq list: %v", err)
	}

	if *asJSON {
		enc := json.NewEncoder(out)
		enc.SetIndent("", "  ")
		if err := enc.Encode(dlqRowsToJSON(rows)); err != nil {
			log.Fatalf("dlq list json: %v", err)
		}
		return
	}

	printDLQTable(out, rows)
}

// runDLQInspect prints full details for a single DLQ row.
func runDLQInspect(ctx context.Context, args []string, out, errOut io.Writer) {
	fs := flag.NewFlagSet("dlq inspect", flag.ExitOnError)
	asJSON := fs.Bool("json", false, "output as JSON")
	if err := fs.Parse(args); err != nil {
		log.Fatalf("dlq inspect: %v", err)
	}
	if fs.NArg() == 0 {
		fmt.Fprintln(errOut, "usage: mopro dlq inspect <dlq_id> [--json]")
		os.Exit(1)
	}
	dlqID, err := strconv.ParseInt(fs.Arg(0), 10, 64)
	if err != nil {
		log.Fatalf("dlq inspect: invalid id %q: %v", fs.Arg(0), err)
	}

	repo := newDLQRepo(ctx)
	row, err := repo.GetByID(ctx, dlqID)
	if err == pgx.ErrNoRows {
		fmt.Fprintf(errOut, "dlq row %d not found\n", dlqID)
		os.Exit(1)
	}
	if err != nil {
		log.Fatalf("dlq inspect: %v", err)
	}

	if *asJSON {
		enc := json.NewEncoder(out)
		enc.SetIndent("", "  ")
		if err := enc.Encode(dlqRowToJSON(row)); err != nil {
			log.Fatalf("dlq inspect json: %v", err)
		}
		return
	}

	printDLQInspect(out, row)
}

// runDLQReplay re-publishes one or more DLQ rows to their original Redis stream.
// Single-row form: mopro dlq replay <id> [--dry-run] [--by user]
// Bulk form:       mopro dlq replay --topic <t> --since <d> --confirm [--dry-run] [--by user]
func runDLQReplay(ctx context.Context, args []string, out, errOut io.Writer) {
	fs := flag.NewFlagSet("dlq replay", flag.ExitOnError)
	dryRun := fs.Bool("dry-run", false, "print what would be replayed without making changes")
	by := fs.String("by", dlqActor(), "operator identifier recorded in replayed_by")
	topic := fs.String("topic", "", "bulk mode: topic filter")
	since := fs.String("since", "", "bulk mode: created_at window (e.g. 1h)")
	confirm := fs.Bool("confirm", false, "bulk mode: required safety gate")
	if err := fs.Parse(args); err != nil {
		log.Fatalf("dlq replay: %v", err)
	}

	repo := newDLQRepo(ctx)

	// Detect mode: if a positional int arg is given → single-row replay.
	if fs.NArg() > 0 {
		dlqID, err := strconv.ParseInt(fs.Arg(0), 10, 64)
		if err != nil {
			log.Fatalf("dlq replay: invalid id %q: %v", fs.Arg(0), err)
		}
		replaySingle(ctx, repo, dlqID, *by, *dryRun, out, errOut)
		return
	}

	// Bulk mode: requires --topic, --since, --confirm.
	if *topic == "" || *since == "" {
		fmt.Fprintln(errOut, "usage: mopro dlq replay --topic <name> --since <duration> --confirm [--dry-run] [--by <user>]")
		fmt.Fprintln(errOut, "or:    mopro dlq replay <dlq_id> [--dry-run] [--by <user>]")
		os.Exit(1)
	}
	if !*confirm && !*dryRun {
		fmt.Fprintln(errOut, "error: bulk replay requires --confirm flag (or --dry-run for preview)")
		os.Exit(1)
	}

	d, err := parseDuration(*since)
	if err != nil {
		log.Fatalf("dlq replay --since: %v", err)
	}
	filter := eventbus.DLQFilter{
		Topic:  *topic,
		Since:  time.Now().Add(-d),
		Status: "open",
	}
	rows, err := repo.List(ctx, filter)
	if err != nil {
		log.Fatalf("dlq replay list: %v", err)
	}
	if len(rows) == 0 {
		fmt.Fprintln(out, "no open DLQ rows match the filter")
		return
	}
	fmt.Fprintf(out, "replaying %d row(s) for topic %s\n", len(rows), *topic)
	for _, row := range rows {
		replaySingle(ctx, repo, row.ID, *by, *dryRun, out, errOut)
	}
}

// replaySingle handles the XADD-first, MarkReplayed-second replay sequence.
func replaySingle(ctx context.Context, repo eventbus.DLQRepository, dlqID int64, by string, dryRun bool, out, errOut io.Writer) {
	row, err := repo.GetByID(ctx, dlqID)
	if err == pgx.ErrNoRows {
		fmt.Fprintf(errOut, "dlq row %d not found\n", dlqID)
		osExit(1)
		return
	}
	if err != nil {
		log.Fatalf("dlq replay get: %v", err)
	}
	if row.Status != "open" {
		fmt.Fprintf(errOut, "dlq row %d status=%s (not 'open'); use --force to override\n", dlqID, row.Status)
		osExit(1)
		return
	}

	// Reconstruct Redis stream entry values from stored payload JSON.
	var values map[string]interface{}
	if err := json.Unmarshal(row.Payload, &values); err != nil {
		log.Fatalf("dlq replay: unmarshal payload for row %d: %v", dlqID, err)
	}

	if dryRun {
		fmt.Fprintf(out, "DRY RUN — DLQ #%d\n", dlqID)
		fmt.Fprintf(out, "  Would XADD to:    %s\n", row.OriginalTopic)
		fmt.Fprintf(out, "  Idempotency key:  %s\n", row.IdempotencyKey)
		fmt.Fprintf(out, "  Payload size:     %d bytes\n", len(row.Payload))
		fmt.Fprintf(out, "  No changes made.\n")
		return
	}

	// Step 1: XADD first — idempotency_key in payload deduplicates at handler level.
	rc := newRedisClient()
	newMsgID, err := rc.XAdd(ctx, &redis.XAddArgs{
		Stream: row.OriginalTopic,
		MaxLen: 10000,
		Approx: true,
		Values: values,
	}).Result()
	if err != nil {
		log.Fatalf("dlq replay XADD row %d: %v", dlqID, err)
	}

	// Step 2: MarkReplayed — records the new Redis message_id.
	if err := repo.MarkReplayed(ctx, dlqID, by, newMsgID); err != nil {
		// DLQ row updated to replayed but XADD succeeded: log for operator awareness.
		fmt.Fprintf(errOut, "warning: dlq row %d MarkReplayed: %v (XADD succeeded with msg_id=%s)\n",
			dlqID, err, newMsgID)
	}
	_ = rc.Close()
	fmt.Fprintf(out, "replayed DLQ #%d → stream %s message_id=%s\n", dlqID, row.OriginalTopic, newMsgID)
}

// runDLQDismiss marks a DLQ row as permanently dismissed.
func runDLQDismiss(ctx context.Context, args []string, out, errOut io.Writer) {
	fs := flag.NewFlagSet("dlq dismiss", flag.ExitOnError)
	reason := fs.String("reason", "", "dismissal reason (required)")
	by := fs.String("by", dlqActor(), "operator identifier")
	if err := fs.Parse(args); err != nil {
		log.Fatalf("dlq dismiss: %v", err)
	}
	if fs.NArg() == 0 {
		fmt.Fprintln(errOut, "usage: mopro dlq dismiss <dlq_id> --reason <text>")
		os.Exit(1)
	}
	if *reason == "" {
		fmt.Fprintln(errOut, "error: --reason is required")
		os.Exit(1)
	}
	dlqID, err := strconv.ParseInt(fs.Arg(0), 10, 64)
	if err != nil {
		log.Fatalf("dlq dismiss: invalid id %q: %v", fs.Arg(0), err)
	}
	runDLQDismissCore(ctx, dlqID, *by, *reason, newDLQRepo(ctx), out, errOut)
}

// runDLQDismissCore is the testable inner implementation of runDLQDismiss.
func runDLQDismissCore(ctx context.Context, dlqID int64, by, reason string, repo eventbus.DLQRepository, out, errOut io.Writer) {
	if err := repo.MarkDismissed(ctx, dlqID, by, reason); err != nil {
		if err == eventbus.ErrDLQNotOpen {
			fmt.Fprintf(errOut, "dlq row %d is not 'open' — already replayed or dismissed\n", dlqID)
			osExit(1)
			return
		}
		log.Fatalf("dlq dismiss: %v", err)
	}
	fmt.Fprintf(out, "dismissed DLQ #%d (reason: %s)\n", dlqID, reason)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// newDLQRepo connects to postgres-ledger as dlq_user.
// Uses DLQ_DATABASE_URL; falls back to LEDGER_DATABASE_URL if not set.
func newDLQRepo(ctx context.Context) eventbus.DLQRepository {
	dsn := os.Getenv("DLQ_DATABASE_URL")
	if dsn == "" {
		dsn = mustEnv("LEDGER_DATABASE_URL")
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		log.Fatalf("mopro dlq: connect postgres-ledger: %v", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		log.Fatalf("mopro dlq: ping postgres-ledger: %v", err)
	}
	return eventbus.NewPgxDLQRepository(pool)
}

// newRedisClient connects to Redis using REDIS_ADDR env var.
func newRedisClient() *redis.Client {
	addr := mustEnv("REDIS_ADDR")
	return redis.NewClient(&redis.Options{Addr: addr})
}

// dlqActor returns the actor string for lifecycle columns (operator identity).
// Uses --by flag value; falls back to $USER env.
func dlqActor() string {
	if u := os.Getenv("USER"); u != "" {
		return u
	}
	return "unknown"
}

// parseDuration parses durations like "1h", "30m", "7d" (days not supported by stdlib).
func parseDuration(s string) (time.Duration, error) {
	s = strings.TrimSpace(s)
	if strings.HasSuffix(s, "d") {
		n, err := strconv.Atoi(strings.TrimSuffix(s, "d"))
		if err != nil {
			return 0, fmt.Errorf("invalid duration %q", s)
		}
		return time.Duration(n) * 24 * time.Hour, nil
	}
	return time.ParseDuration(s)
}

// printDLQTable renders a tabwriter-aligned summary table.
func printDLQTable(w io.Writer, rows []eventbus.DLQRow) {
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "ID\tTOPIC\tGROUP\tIDEMPOTENCY_KEY\tATTEMPTS\tCREATED\tSTATUS")
	for _, r := range rows {
		idem := r.IdempotencyKey
		if len(idem) > 30 {
			idem = idem[:27] + "..."
		}
		topic := r.OriginalTopic
		if len(topic) > 28 {
			topic = topic[:25] + "..."
		}
		fmt.Fprintf(tw, "%d\t%s\t%s\t%s\t%d\t%s\t%s\n",
			r.ID, topic, r.ConsumerGroup, idem,
			r.AttemptCount, r.CreatedAt.Format("2006-01-02T15:04:05Z"),
			r.Status,
		)
	}
	tw.Flush()
}

// printDLQInspect prints a human-readable detail view of one DLQ row.
func printDLQInspect(w io.Writer, row eventbus.DLQRow) {
	fmt.Fprintf(w, "DLQ #%d\n", row.ID)
	fmt.Fprintf(w, "  Topic:           %s\n", row.OriginalTopic)
	fmt.Fprintf(w, "  Consumer Group:  %s\n", row.ConsumerGroup)
	fmt.Fprintf(w, "  Message ID:      %s\n", row.OriginalMessageID)
	fmt.Fprintf(w, "  Idempotency Key: %s\n", row.IdempotencyKey)
	fmt.Fprintf(w, "  Status:          %s\n", row.Status)
	fmt.Fprintf(w, "  Attempts:        %d\n", row.AttemptCount)
	fmt.Fprintf(w, "  Created:         %s\n", row.CreatedAt.Format(time.RFC3339))
	if row.ReplayedAt != nil {
		fmt.Fprintf(w, "  Replayed At:     %s by %s (msg_id: %s)\n",
			row.ReplayedAt.Format(time.RFC3339),
			strPtrOr(row.ReplayedBy, "unknown"),
			strPtrOr(row.ReplayedMessageID, "?"))
	}
	if row.DismissedAt != nil {
		fmt.Fprintf(w, "  Dismissed At:    %s by %s (reason: %s)\n",
			row.DismissedAt.Format(time.RFC3339),
			strPtrOr(row.DismissedBy, "unknown"),
			strPtrOr(row.DismissalReason, ""))
	}

	fmt.Fprintf(w, "\nPayload:\n")
	var payload map[string]interface{}
	if err := json.Unmarshal(row.Payload, &payload); err == nil {
		b, _ := json.MarshalIndent(payload, "  ", "  ")
		fmt.Fprintf(w, "  %s\n", b)
	} else {
		fmt.Fprintf(w, "  %s\n", row.Payload)
	}

	fmt.Fprintf(w, "\nError History:\n")
	var history []map[string]interface{}
	if err := json.Unmarshal(row.ErrorHistory, &history); err == nil {
		for i, e := range history {
			errStr, _ := e["error"].(string)
			fmt.Fprintf(w, "  [%d] %v  %v  %v",
				i+1, e["attempt_at"], e["consumer_name"], e["outcome"])
			if errStr != "" {
				fmt.Fprintf(w, "  %s", errStr)
			}
			fmt.Fprintln(w)
		}
	}
}

// ── JSON serialization helpers ────────────────────────────────────────────────

func dlqRowToJSON(row eventbus.DLQRow) map[string]interface{} {
	m := map[string]interface{}{
		"id":                  row.ID,
		"original_topic":      row.OriginalTopic,
		"original_message_id": row.OriginalMessageID,
		"consumer_group":      row.ConsumerGroup,
		"idempotency_key":     row.IdempotencyKey,
		"attempt_count":       row.AttemptCount,
		"status":              row.Status,
		"created_at":          row.CreatedAt.Format(time.RFC3339),
	}
	var payload, errorHistory interface{}
	_ = json.Unmarshal(row.Payload, &payload)
	_ = json.Unmarshal(row.ErrorHistory, &errorHistory)
	m["payload"] = payload
	m["error_history"] = errorHistory
	if row.ReplayedAt != nil {
		m["replayed_at"] = row.ReplayedAt.Format(time.RFC3339)
		m["replayed_by"] = row.ReplayedBy
		m["replayed_message_id"] = row.ReplayedMessageID
	}
	if row.DismissedAt != nil {
		m["dismissed_at"] = row.DismissedAt.Format(time.RFC3339)
		m["dismissed_by"] = row.DismissedBy
		m["dismissal_reason"] = row.DismissalReason
	}
	return m
}

func dlqRowsToJSON(rows []eventbus.DLQRow) []map[string]interface{} {
	out := make([]map[string]interface{}, len(rows))
	for i, r := range rows {
		out[i] = dlqRowToJSON(r)
	}
	return out
}

func strPtrOr(p *string, fallback string) string {
	if p == nil {
		return fallback
	}
	return *p
}

func dlqUsage(w io.Writer) {
	fmt.Fprintln(w, "usage: mopro dlq <subcommand>")
	fmt.Fprintln(w, "subcommands:")
	fmt.Fprintln(w, "  list    [--topic <name>] [--since <duration>] [--status open|replayed|dismissed|all] [--json]")
	fmt.Fprintln(w, "  inspect <dlq_id> [--json]")
	fmt.Fprintln(w, "  replay  <dlq_id> [--dry-run] [--by <user>]")
	fmt.Fprintln(w, "  replay  --topic <name> --since <duration> --confirm [--dry-run] [--by <user>]")
	fmt.Fprintln(w, "  dismiss <dlq_id> --reason <text> [--by <user>]")
}
