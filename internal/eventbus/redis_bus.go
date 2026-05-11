package eventbus

import "github.com/redis/go-redis/v9"

// redisBus is the Redis Streams implementation of Bus.
// All XADD calls MUST go through the outbox publisher (internal/outbox), not directly here.
// TODO(mopro:placeholder): implement Redis Streams publish/consume using go-redis/v9
// Unblocked by: Phase 1 (infrastructure wiring) and Phase 0.3 (Redis config)
type redisBus struct {
	client *redis.Client
}
