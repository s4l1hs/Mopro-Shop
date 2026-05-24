package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

func main() {
	dbFlag := flag.String("db", "", "database target: ecom | ledger")
	flag.Parse()

	if *dbFlag == "" && flag.NArg() >= 1 {
		// Support positional: migrate-tool --db ecom up  OR  migrate-tool ecom up (legacy).
		*dbFlag = flag.Arg(0)
	}

	args := flag.Args()
	cmd := ""
	switch {
	case *dbFlag != "" && len(args) >= 1:
		cmd = args[0]
	case *dbFlag != "" && len(args) == 0:
		usageAndExit()
	default:
		usageAndExit()
	}

	dsn := dsnForDB(*dbFlag)
	if dsn == "" {
		fmt.Fprintf(os.Stderr, "migrate-tool: no DSN env var for db=%q\n", *dbFlag)
		fmt.Fprintln(os.Stderr, "  ecom   → ECOM_DATABASE_URL or NOTIFICATION_DATABASE_URL")
		fmt.Fprintln(os.Stderr, "  ledger → LEDGER_DATABASE_URL")
		os.Exit(1)
	}

	migrationsDir := migrationsPath(*dbFlag)
	sourceURL := "file://" + migrationsDir

	m, err := migrate.New(sourceURL, pgxDSN(dsn))
	if err != nil {
		fmt.Fprintf(os.Stderr, "migrate-tool: init failed: %v\n", err)
		os.Exit(1)
	}
	defer func() { _, _ = m.Close() }()

	switch cmd {
	case "up":
		if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
			fmt.Fprintf(os.Stderr, "migrate-tool: up failed: %v\n", err)
			os.Exit(1)
		}
		ver, dirty, _ := m.Version()
		fmt.Printf("migrate-tool: up complete db=%s version=%d dirty=%v\n", *dbFlag, ver, dirty)

	case "down":
		if err := m.Steps(-1); err != nil && !errors.Is(err, migrate.ErrNoChange) {
			fmt.Fprintf(os.Stderr, "migrate-tool: down failed: %v\n", err)
			os.Exit(1)
		}
		ver, dirty, _ := m.Version()
		fmt.Printf("migrate-tool: down complete db=%s version=%d dirty=%v\n", *dbFlag, ver, dirty)

	case "status":
		ver, dirty, err := m.Version()
		switch {
		case errors.Is(err, migrate.ErrNilVersion):
			fmt.Printf("migrate-tool: status db=%s version=none (no migrations applied)\n", *dbFlag)
		case err != nil:
			fmt.Fprintf(os.Stderr, "migrate-tool: status error: %v\n", err)
			os.Exit(1)
		default:
			fmt.Printf("migrate-tool: status db=%s version=%d dirty=%v\n", *dbFlag, ver, dirty)
		}

	default:
		fmt.Fprintf(os.Stderr, "migrate-tool: unknown command %q (want: up|down|status)\n", cmd)
		os.Exit(1)
	}
}

// dsnForDB returns the Postgres DSN for the named logical database.
func dsnForDB(db string) string {
	switch db {
	case "ecom":
		if v := os.Getenv("ECOM_DATABASE_URL"); v != "" {
			return v
		}
		// jobs-svc uses NOTIFICATION_DATABASE_URL for the same postgres-ecom cluster.
		return os.Getenv("NOTIFICATION_DATABASE_URL")
	case "ledger":
		return os.Getenv("LEDGER_DATABASE_URL")
	default:
		return ""
	}
}

// migrationsPath returns the absolute path to the migrations directory for db.
// Walks up from the binary's directory to find the repo root (contains go.mod).
func migrationsPath(db string) string {
	// If MIGRATIONS_DIR is set (CI / Docker), use it directly.
	if base := os.Getenv("MIGRATIONS_DIR"); base != "" {
		return filepath.Join(base, db)
	}
	// Walk up from the binary location to find repo root.
	exe, err := os.Executable()
	if err != nil {
		exe = os.Args[0]
	}
	dir := filepath.Dir(exe)
	for i := 0; i < 6; i++ {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil { //nolint:gosec // G703: path joined from binary location, not user input
			return filepath.Join(dir, "migrations", db)
		}
		dir = filepath.Dir(dir)
	}
	// Fallback: relative to caller source (works when run via `go run`).
	_, file, _, _ := runtime.Caller(0)
	root := filepath.Join(filepath.Dir(file), "..", "..")
	return filepath.Join(root, "migrations", db)
}

// pgxDSN converts a standard postgres:// DSN to pgx5:// for the migrate driver.
func pgxDSN(dsn string) string {
	const pgPrefix = "postgres://"
	const pgxPrefix = "pgx5://"
	if len(dsn) >= len(pgPrefix) && dsn[:len(pgPrefix)] == pgPrefix {
		return pgxPrefix + dsn[len(pgPrefix):]
	}
	return dsn
}

func usageAndExit() {
	fmt.Fprintln(os.Stderr, "usage: migrate-tool --db <ecom|ledger> <up|down|status>")
	fmt.Fprintln(os.Stderr, "       ECOM_DATABASE_URL or LEDGER_DATABASE_URL must be set")
	os.Exit(1)
}
