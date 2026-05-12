package cart

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	cartKeyPrefix        = "mopro:cart:user_"
	stockKeyPrefix       = "mopro:stock:"
	reservationKeyPrefix = "mopro:reservation:"

	cartTTLSec = int64(30 * 24 * 3600) // 30 days
)

// reserveLua atomically checks stock, decrements it, and records the reservation item.
//
// KEYS[1] = stock key          (mopro:stock:{variantID})
// KEYS[2] = reservation item   (mopro:reservation:{reservationID}:{variantID})
// ARGV[1] = qty to reserve
// ARGV[2] = TTL for reservation item in seconds
// ARGV[3] = user_id string
//
// Returns: {'OK', remaining} or {'OUT_OF_STOCK', current}
const reserveLua = `
local current = tonumber(redis.call('GET', KEYS[1]) or '0')
local qty = tonumber(ARGV[1])
if current < qty then
    return { 'OUT_OF_STOCK', tostring(current) }
end
local remaining = current - qty
redis.call('SET', KEYS[1], remaining)
redis.call('SETEX', KEYS[2], tonumber(ARGV[2]),
           cjson.encode({ user_id = ARGV[3], qty = qty, variant_id_key = KEYS[1] }))
return { 'OK', tostring(remaining) }
`

type redisRepository struct {
	rc         *redis.Client
	reserveSHA string
}

// NewRepository returns a Repository backed by Redis.
// The Lua reservation script is loaded via SCRIPT LOAD during construction.
func NewRepository(ctx context.Context, rc *redis.Client) (Repository, error) {
	sha, err := rc.ScriptLoad(ctx, reserveLua).Result()
	if err != nil {
		return nil, fmt.Errorf("cart.repo: SCRIPT LOAD: %w", err)
	}
	return &redisRepository{rc: rc, reserveSHA: sha}, nil
}

func cartKey(userID int64) string {
	return cartKeyPrefix + strconv.FormatInt(userID, 10)
}

func stockKey(variantID int64) string {
	return stockKeyPrefix + strconv.FormatInt(variantID, 10)
}

func manifestKey(reservationID string) string {
	return reservationKeyPrefix + reservationID
}

func itemKey(reservationID string, variantID int64) string {
	return reservationKeyPrefix + reservationID + ":" + strconv.FormatInt(variantID, 10)
}

func (r *redisRepository) SetItem(ctx context.Context, userID, variantID int64, qty int) error {
	key := cartKey(userID)
	field := strconv.FormatInt(variantID, 10)
	if err := r.rc.HSet(ctx, key, field, qty).Err(); err != nil {
		return fmt.Errorf("cart.repo: SetItem HSet: %w", err)
	}
	if err := r.rc.Expire(ctx, key, time.Duration(cartTTLSec)*time.Second).Err(); err != nil {
		return fmt.Errorf("cart.repo: SetItem Expire: %w", err)
	}
	return nil
}

func (r *redisRepository) RemoveItem(ctx context.Context, userID, variantID int64) error {
	key := cartKey(userID)
	field := strconv.FormatInt(variantID, 10)
	if err := r.rc.HDel(ctx, key, field).Err(); err != nil {
		return fmt.Errorf("cart.repo: RemoveItem HDel: %w", err)
	}
	// Best-effort TTL renewal; failure just means cart expires sooner — acceptable.
	_ = r.rc.Expire(ctx, key, time.Duration(cartTTLSec)*time.Second).Err()
	return nil
}

func (r *redisRepository) GetItems(ctx context.Context, userID int64) ([]CartItem, error) {
	data, err := r.rc.HGetAll(ctx, cartKey(userID)).Result()
	if err != nil {
		return nil, fmt.Errorf("cart.repo: GetItems HGetAll: %w", err)
	}
	items := make([]CartItem, 0, len(data))
	for variantIDStr, qtyStr := range data {
		variantID, errP := strconv.ParseInt(variantIDStr, 10, 64)
		if errP != nil {
			continue
		}
		qty, errQ := strconv.Atoi(qtyStr)
		if errQ != nil {
			continue
		}
		items = append(items, CartItem{VariantID: variantID, Qty: qty})
	}
	return items, nil
}

func (r *redisRepository) TryReserve(ctx context.Context, variantID int64, qty int, reservationID string, userID int64, ttlSec int64) (bool, int, error) {
	sKey := stockKey(variantID)
	iKey := itemKey(reservationID, variantID)

	raw, err := r.rc.EvalSha(ctx, r.reserveSHA,
		[]string{sKey, iKey},
		qty, ttlSec, userID,
	).Result()
	if err != nil {
		return false, 0, fmt.Errorf("cart.repo: TryReserve EvalSha: %w", err)
	}

	parts, ok := raw.([]interface{})
	if !ok || len(parts) < 2 {
		return false, 0, fmt.Errorf("cart.repo: TryReserve unexpected result shape: %v", raw)
	}
	status, _ := parts[0].(string)
	valStr, _ := parts[1].(string)
	val, _ := strconv.Atoi(valStr)

	if status == "OUT_OF_STOCK" {
		return false, val, nil
	}
	return true, val, nil
}

func (r *redisRepository) SetManifest(ctx context.Context, reservationID string, items []CartItem, ttlSec int64) error {
	if len(items) == 0 {
		return nil
	}
	key := manifestKey(reservationID)
	args := make([]interface{}, 0, len(items)*2)
	for _, item := range items {
		args = append(args, strconv.FormatInt(item.VariantID, 10), item.Qty)
	}
	if err := r.rc.HSet(ctx, key, args...).Err(); err != nil {
		return fmt.Errorf("cart.repo: SetManifest HSet: %w", err)
	}
	if err := r.rc.Expire(ctx, key, time.Duration(ttlSec)*time.Second).Err(); err != nil {
		return fmt.Errorf("cart.repo: SetManifest Expire: %w", err)
	}
	return nil
}

func (r *redisRepository) ReleaseReservation(ctx context.Context, reservationID string) error {
	mKey := manifestKey(reservationID)

	data, err := r.rc.HGetAll(ctx, mKey).Result()
	if err != nil {
		return fmt.Errorf("cart.repo: ReleaseReservation HGetAll: %w", err)
	}
	if len(data) == 0 {
		return ErrReservationNotFound
	}

	for variantIDStr, qtyStr := range data {
		variantID, errP := strconv.ParseInt(variantIDStr, 10, 64)
		if errP != nil {
			continue
		}
		qty, errQ := strconv.ParseInt(qtyStr, 10, 64)
		if errQ != nil {
			continue
		}
		if err := r.rc.IncrBy(ctx, stockKey(variantID), qty).Err(); err != nil {
			return fmt.Errorf("cart.repo: ReleaseReservation IncrBy variant %d: %w", variantID, err)
		}
		if err := r.rc.Del(ctx, itemKey(reservationID, variantID)).Err(); err != nil {
			return fmt.Errorf("cart.repo: ReleaseReservation Del item %d: %w", variantID, err)
		}
	}

	if err := r.rc.Del(ctx, mKey).Err(); err != nil {
		return fmt.Errorf("cart.repo: ReleaseReservation Del manifest: %w", err)
	}
	return nil
}

func (r *redisRepository) SeedStock(ctx context.Context, variantID int64, stock int) error {
	if err := r.rc.Set(ctx, stockKey(variantID), stock, 0).Err(); err != nil {
		return fmt.Errorf("cart.repo: SeedStock Set: %w", err)
	}
	return nil
}
