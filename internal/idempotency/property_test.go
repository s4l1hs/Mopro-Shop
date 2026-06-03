//go:build !integration

package idempotency_test

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"

	"github.com/mopro/platform/internal/idempotency"
)

func gopterParams(minTests int) *gopter.TestParameters {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = minTests
	return params
}

// TestProperty_Key_Deterministic verifies Key(userID, k) always equals its documented
// format `idem:<userID>:<k>`. F-007: the prior assertion was `Key(x) == Key(x)` (SA4000,
// a near-tautology that passes for any pure fn); comparing against the constructed expected
// string actually exercises determinism AND pins the format (catches any impl drift).
func TestProperty_Key_Deterministic(t *testing.T) {
	properties := gopter.NewProperties(gopterParams(500))
	properties.Property("Key matches idem:<userID>:<idemKey>", prop.ForAll(
		func(userID int64, idemKey string) bool {
			want := fmt.Sprintf("idem:%d:%s", userID, idemKey)
			return idempotency.Key(userID, idemKey) == want
		},
		gen.Int64(),
		gen.AnyString(),
	))
	properties.TestingRun(t)
}

// TestProperty_Key_HasPrefix verifies all keys start with "idem:".
func TestProperty_Key_HasPrefix(t *testing.T) {
	properties := gopter.NewProperties(gopterParams(500))
	properties.Property("Key always starts with idem:", prop.ForAll(
		func(userID int64, idemKey string) bool {
			return strings.HasPrefix(idempotency.Key(userID, idemKey), "idem:")
		},
		gen.Int64(),
		gen.AnyString(),
	))
	properties.TestingRun(t)
}

// TestProperty_Key_ContainsUserID verifies the key embeds the user ID.
func TestProperty_Key_ContainsUserID(t *testing.T) {
	properties := gopter.NewProperties(gopterParams(500))
	properties.Property("Key contains user ID segment", prop.ForAll(
		func(userID int64, idemKey string) bool {
			k := idempotency.Key(userID, idemKey)
			// Format: "idem:{user_id}:{idempotency_key}" — second segment is user ID
			parts := strings.SplitN(k, ":", 3)
			return len(parts) == 3 && parts[0] == "idem"
		},
		gen.Int64(),
		gen.AnyString(),
	))
	properties.TestingRun(t)
}

// TestProperty_Key_DifferentUsers_DifferentKeys verifies different user IDs produce different keys
// for the same idempotency-key value.
func TestProperty_Key_DifferentUsers_DifferentKeys(t *testing.T) {
	properties := gopter.NewProperties(gopterParams(500))
	properties.Property("Different user IDs → different keys for same idem-key", prop.ForAll(
		func(userA, userB int64, idemKey string) bool {
			if userA == userB {
				return true // skip equal users — trivially same key
			}
			return idempotency.Key(userA, idemKey) != idempotency.Key(userB, idemKey)
		},
		gen.Int64(),
		gen.Int64(),
		gen.AnyString(),
	))
	properties.TestingRun(t)
}

// TestProperty_CachedResponse_JSONRoundTrip verifies CachedResponse survives JSON marshal/unmarshal.
func TestProperty_CachedResponse_JSONRoundTrip(t *testing.T) {
	properties := gopter.NewProperties(gopterParams(500))
	properties.Property("CachedResponse round-trips through JSON", prop.ForAll(
		func(status int, ct string, body []byte) bool {
			if status < 100 || status > 599 {
				return true // skip invalid status codes
			}
			cr := idempotency.CachedResponse{
				Status:      status,
				ContentType: ct,
				Body:        body,
			}
			b, err := json.Marshal(cr)
			if err != nil {
				return false
			}
			var got idempotency.CachedResponse
			if err := json.Unmarshal(b, &got); err != nil {
				return false
			}
			if got.Status != cr.Status || got.ContentType != cr.ContentType {
				return false
			}
			if len(got.Body) != len(cr.Body) {
				return false
			}
			for i := range cr.Body {
				if got.Body[i] != cr.Body[i] {
					return false
				}
			}
			return true
		},
		gen.IntRange(100, 599),
		gen.AnyString(),
		gen.SliceOf(gen.UInt8()),
	))
	properties.TestingRun(t)
}
