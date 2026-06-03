# `payment.Service` (provider registry/factory) — discovery (F-002 slice)

The only REAL module among F-002's "search/media/sizefinder/payment" entries (the other
three are 12-LOC stubs). Small + pure-logic (no DB) → unit-test-only slice.

## Real path
`internal/payment/service.go` (91 LOC). Not a PSP *implementation* — a **selector**:
- `providerRegistry map[string]ProviderFactory` (package global).
- `RegisterProvider(name, fn)` — each PSP sub-package registers itself from `init()`
  (e.g. `internal/payment/sipay` registers `"sipay"`; `main.go` imports it with `_`).
- `NewService(cfg, repo) Service` — dispatches on the `PSP_PROVIDER` env var.

## Behaviour (the test surface)
| `PSP_PROVIDER` | Result |
|---|---|
| `sipay`, factory registered | returns `fn(cfg, repo)` |
| `sipay`, **not** registered | **panics** with a wiring hint (forgot the `_` import) |
| `craftgate` | `craftgateStub{}` — every method returns `ErrProviderNotImplemented` |
| `iyzico` | `iyzicoStub{}` — every method returns `ErrProviderNotImplemented` |
| `""` (unset) | `log.Fatal` — startup invariant (process exit) |
| unknown value | `log.Fatalf` — startup invariant (process exit) |

## Notes for tests
- `providerRegistry` is mutable package state → tests save/restore it.
- The `sipay` sub-package is NOT imported by `package payment` (sipay imports payment), so
  in white-box tests the registry starts empty unless a fake is registered — which is exactly
  what lets us test both the registered and not-registered paths.
- The two `log.Fatal` paths exit the process; tested via the standard re-exec-subprocess idiom.
- No DB, no external calls, no transactions, no user-state — **unit tests only; no integration
  suite** (nothing to integrate).
- Stubs craftgate/iyzico are intentional placeholders (v1 = sipay only); their uniform
  `ErrProviderNotImplemented` is the contract, not a gap.
