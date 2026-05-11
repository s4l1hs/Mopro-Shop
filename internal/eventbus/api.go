// Package eventbus defines the Redis Streams event bus interface used for cross-binary communication.
// core-svc → fin-svc and fin-svc → core-svc communicate ONLY via this interface.
package eventbus

// Bus defines the publish/consume interface for Redis Streams events.
type Bus interface{}

// Repository defines the storage interface for eventbus metadata.
type Repository interface{}
