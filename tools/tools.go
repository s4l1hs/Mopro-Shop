//go:build tools

// Package tools tracks build-time and test-time tool dependencies so that
// go mod tidy keeps them in go.mod / go.sum.
package tools

import (
	_ "github.com/golang-migrate/migrate/v4"
	_ "github.com/leanovate/gopter"
)
