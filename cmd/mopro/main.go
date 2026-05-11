package main

import (
	"fmt"
	"log"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: mopro <command> [args...]")
		fmt.Fprintln(os.Stderr, "commands: cashback, payout, calendar")
		os.Exit(1)
	}
	// TODO(mopro:placeholder): implement ops CLI subcommands
	// Unblocked by: Phase 3 (cashback engine) and Phase 4 (seller payout engine)
	log.Printf("mopro starting command=%s", os.Args[1])
}
