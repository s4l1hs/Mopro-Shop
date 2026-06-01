package attachments

import "errors"

var (
	ErrNotFound      = errors.New("media: attachment not found")
	ErrNotOwned      = errors.New("media: attachment not owned by user or already attached")
	ErrLimitExceeded = errors.New("media: per-entity photo limit exceeded")
	ErrInvalidEntity = errors.New("media: invalid entity type")
)
