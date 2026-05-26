// Package buildinfo exposes build-time metadata injected via ldflags.
//
// Inject at build time with:
//
//	-ldflags "-X github.com/mopro/platform/internal/buildinfo.SHA=<sha> \
//	           -X github.com/mopro/platform/internal/buildinfo.BuiltAt=<timestamp>"
//
// When empty, callers should fall back to debug.ReadBuildInfo() VCS metadata.
package buildinfo

// SHA is the 40-char git commit SHA, injected via -ldflags at build time.
var SHA = ""

// BuiltAt is the RFC-3339 build timestamp, injected via -ldflags at build time.
var BuiltAt = ""
