package main

import (
	"fmt"
	"log"
	"os"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: migrate-tool <ecom|ledger> <up|down|status>")
		os.Exit(1)
	}
	db := os.Args[1]
	cmd := os.Args[2]
	// TODO(mopro:placeholder): implement migration runner using golang-migrate/migrate/v4
	// Unblocked by: Phase 0.2 (DB init scripts) and Phase 1 (DB connectivity)
	log.Printf("migrate-tool starting db=%s cmd=%s", db, cmd)
}
