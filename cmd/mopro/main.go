package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"log/slog"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/wallet"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}
	ctx := context.Background()
	switch os.Args[1] {
	case "set-read-only":
		fs := flag.NewFlagSet("set-read-only", flag.ExitOnError)
		reason := fs.String("reason", "", "reason for enabling read-only mode (required)")
		if err := fs.Parse(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, "error:", err)
			os.Exit(1)
		}
		if *reason == "" {
			fmt.Fprintln(os.Stderr, "error: --reason is required")
			os.Exit(1)
		}
		runWithWallet(ctx, func(svc wallet.Service) error {
			return svc.SetReadOnly(ctx, *reason)
		})
	case "clear-read-only":
		runWithWallet(ctx, func(svc wallet.Service) error {
			return svc.ClearReadOnly(ctx)
		})
	case "dlq":
		runDLQ(ctx, os.Args[2:])
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		usage()
		os.Exit(1)
	}
}

func runWithWallet(ctx context.Context, fn func(wallet.Service) error) {
	dsn := mustEnv("LEDGER_DATABASE_URL")
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		log.Fatalf("mopro: connect to postgres-ledger: %v", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		log.Fatalf("mopro: ping postgres-ledger: %v", err)
	}
	// outboxRepo is nil: CLI only calls SetReadOnly/ClearReadOnly, never PostInTx.
	repo := wallet.NewRepository(pool)
	svc := wallet.NewService(repo, nil /* outboxRepo intentionally nil for CLI */, slog.Default())
	if err := fn(svc); err != nil {
		pool.Close()
		slog.Error("mopro: command failed", "err", err)
		os.Exit(1)
	}
	pool.Close()
	fmt.Println("ok")
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: mopro <command> [args]")
	fmt.Fprintln(os.Stderr, "commands:")
	fmt.Fprintln(os.Stderr, "  set-read-only --reason <text>   enable wallet read-only mode")
	fmt.Fprintln(os.Stderr, "  clear-read-only                  clear wallet read-only mode")
	fmt.Fprintln(os.Stderr, "  dlq <subcommand>                 dead-letter queue operations (run 'mopro dlq' for help)")
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("mopro: required env %s is not set", key)
	}
	return v
}
