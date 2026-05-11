// Package outbox implements the transactional outbox pattern for reliable event publishing.
// Financial events MUST be written to the outbox table within the SAME DB transaction as the ledger write.
package outbox

// Publisher defines the interface for the outbox relay worker.
type Publisher interface{}

// Repository defines the storage interface for the outbox table.
type Repository interface{}
