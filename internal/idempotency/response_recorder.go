package idempotency

import (
	"bytes"
	"net/http"
)

// responseRecorder wraps an http.ResponseWriter, capturing the status code and
// body while forwarding all writes to the underlying writer simultaneously.
// This means the client receives the real response and the cache is populated
// in a single handler pass — no buffering delay.
type responseRecorder struct {
	http.ResponseWriter
	status int
	body   bytes.Buffer
}

func newResponseRecorder(w http.ResponseWriter) *responseRecorder {
	return &responseRecorder{ResponseWriter: w, status: http.StatusOK}
}

func (rr *responseRecorder) WriteHeader(status int) {
	rr.status = status
	rr.ResponseWriter.WriteHeader(status)
}

func (rr *responseRecorder) Write(b []byte) (int, error) {
	rr.body.Write(b) // capture; error here would also affect the real write
	return rr.ResponseWriter.Write(b)
}
