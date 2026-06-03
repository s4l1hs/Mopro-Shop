# Config injection — discovery + A-003 migration plan

Discovery for **ARCHITECTURE_AUDIT A-003** (modules read `os.Getenv` directly).
Re-verified on this branch — the audit's "7" is now fewer (A4-1/#74 already removed
`payment/service.go`'s read), and one entry is a documented design, not a violation.

## Current `os.Getenv` reads in `internal/` (non-test)
```
$ git grep -nE 'os\.Getenv' -- internal/ ':!*_test.go'
```
| Module | Site(s) | What it reads | Verdict |
|---|---|---|---|
| `payment/service.go` | line 25 | (none — a *comment* "no os.Getenv", A4-1) | already migrated (#74) |
| `eventbus/redis_bus.go` | `maxLenFor` 671, `envInt` 768 | `REDIS_STREAM_MAXLEN_<topic>` per-stream override (default 10000); int tuning knobs | **INTENTIONAL — not migrated** |
| `payment/sipay/client.go` | `validateConfig` 200 | `GO_ENV == "production"` prod-safety guard | **MIGRATE** (the A4-1-deferred invariant) |
| `shipping/service.go` | `NewService` 29 | `GO_ENV == "production"` prod-safety guard | **MIGRATE** |
| `storage/s3.go` + `storage.go` | 23–29, 30/39/40 | `STORAGE_*` config + `Enabled()`/backend select | **MIGRATE** |
| `identity/service.go` | `NewService` 62 (panic guard) + `RequestOTP` 131 (dev backdoor) | `DEV_OTP_ACCEPT_ANY`, `ENV` | **MIGRATE** (low-cascade via functional option) |

### eventbus is NOT an A-003 violation (§2.2)
`maxLenFor`/`envInt` read **optional runtime tuning overrides with defaults**, documented
in **ADR-0003** + `.env.example` (per-stream MAXLEN). That's the intended operational-tuning
pattern, not startup config that should be injected — and it's already testable (defaults apply
when env is unset). Reclassified as intentional; left as-is.

## Migration pattern (per A4-1's precedent)
Per-module `Config` struct + `LoadConfigFromEnv() (Config, error)` helper; the env-read moves to
the binary entry (`cmd/*/main.go`); the constructor takes the config and returns/validates via a
**typed error**, not `log.Fatal`/`panic`/`os.Getenv`. No config library (plain struct + helpers).
A tiny shared `pkg/config` helper is added only if ≥2 modules need the same parse (assessed below).

### sipay (financial — the A4-1-deferred one)
`SipayConfig` already flows from `cmd/core-svc/main.go`. Add `SipayConfig.Environment string`;
`validateConfig` reads `cfg.Environment == "production"` instead of `os.Getenv("GO_ENV")`. The
prod-safety semantics are **preserved verbatim** (refuse sandbox keys/URLs in production); only the
*source* of the environment value moves to the caller. **Cascade: ~0** (the struct already flows).

### storage (1 caller)
`storage.Config{Enabled, Backend, Endpoint, Bucket, Region, AccessKey, SecretKey, FSPath}` +
`LoadConfigFromEnv`; `New(cfg) (PhotoStorage, error)`. Only `cmd/core-svc/main.go` constructs it.

### shipping (3 callers)
`NewService` gains an `inProduction bool` (read once in main); the `GO_ENV` guard becomes
`if inProduction { … }`. Behaviour identical (KARGO_DEFAULT required in prod). Cascade: main + 2 tests.

### identity (auth core — low-cascade via functional options)
`DEV_OTP_ACCEPT_ANY` (dev backdoor) + the `ENV=production` panic guard. To avoid an 8-caller
signature cascade on the auth core, use a **variadic functional option**:
`NewService(..., opts ...Option)` with `WithDevOTPBypass(enabled, inProduction bool)`. Existing 8
callers are unchanged (no option = bypass off, the safe default); `cmd/core-svc/main.go` reads the
env vars and passes the option. The dev backdoor reads the captured field, not `os.Getenv`, per call.
**Security invariant preserved exactly:** dev-bypass + production → panic at construction.

## Behavior-preservation contract (verified in the PR description)
Every env var keeps its name, default, required-vs-optional, and failure mode (process death on a
fatal misconfig still happens — at the caller). The sipay + identity prod-safety guards are locked
in by new typed-error / panic-equivalent tests.

## Out of scope
eventbus (intentional, above); cron-sim; idempotency-surface analyzer; any non-listed module.
