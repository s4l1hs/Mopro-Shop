package reconcile

import "errors"

// ErrDriftDetected is returned when a reconciliation invariant check finds a non-zero drift.
var ErrDriftDetected = errors.New("reconcile: invariant drift detected")
