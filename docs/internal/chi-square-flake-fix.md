# Chi-square flake fix — `TestProperty_OTPCodeDistribution`

> Closes the PR #74 candidate flake: a chi-square goodness-of-fit test on OTP-code
> distribution false-fails at its alpha rate **by definition** — it isn't a code bug.
> Paths are `internal/identity/` (the prompt's `<file>` placeholders).

## 1. What the test actually tests

`generateOTPCode` (`internal/identity/service.go`):
```go
n, err := rand.Int(rand.Reader, big.NewInt(1_000_000)) // crypto/rand
return fmt.Sprintf("%06d", n.Int64()), nil
```
`crypto/rand.Int` is **uniform over [0, 1_000_000) by construction** — it uses rejection sampling, so
there is **no modulo bias** for the chi-square to catch. The only thing this package controls is the
**bound** (`1_000_000`) and the **zero-padded 6-digit format** (`%06d`). So a uniformity chi-square is
testing **crypto/rand's** uniformity (the stdlib's responsibility), not Mopro's logic — and a
goodness-of-fit at alpha=α false-fails ≈α of runs on a *perfectly* uniform source, independent of N.

## 2. Discovery found TWO copies (both skipped/flaky)

| File | Build tag | Pkg | Source | Threshold | Where it runs |
|---|---|---|---|---|---|
| `codegen_test.go` | `!integration` | `identity` (whitebox) | `generateOTPCode` ×100k | p=0.05 (crit 16.919) | **`make test`** (`go test -race ./...`) → **~5% flake** |
| `property_test.go` | `integration` | `identity_test` | `svc.RequestOTP` ×600 (bcrypt) | p=0.001 (crit 27.877) | `integration-identity`; `-skip`-excluded from the `-race` targets **for speed** (600 bcrypt calls ×10 slower) |

So the live gate flake is the **whitebox** one (in `make test`, p=0.05). The integration one is the slow
one the `-race` targets exclude (a speed exclusion, not a flake exclusion). Both are uniformity tests of
crypto/rand.

## 3. Decision — delete the statistical tests, replace with a deterministic format test (Outcome 3)

A fixed-seed rewrite (the prompt's default Outcome 1) doesn't fit: the randomness is `crypto/rand.Reader`
(not seed-injectable without a hook), and a seeded uniformity assertion is tautological (one PRNG
trajectory). The honest fix is to **stop testing crypto/rand** and **deterministically test what Mopro
owns** — the bound + format:

- Extract `formatOTP(n int64) string` (the `%06d` part) from `generateOTPCode` (pure, no behavior change).
- **`codegen_test.go` → `TestOTPCode_Format`** (whitebox, deterministic):
  - `formatOTP` boundary cases with exact expected strings — `0→"000000"`, `7→"000007"`, `999999→"999999"`,
    etc. This catches the real regression risk (a `%d` dropping leading zeros) — which a *random sample
    might never hit* (it may draw no low numbers). Deterministic ⇒ zero flake.
  - A live `generateOTPCode` smoke (×1000): every output is a 6-digit numeric string in `[0, 1e6)`. The
    assertion holds for **every** draw, so it never flakes (unlike chi-square).
- **`property_test.go`**: **delete** the integration chi-square — redundant (the format is now covered by
  the whitebox test; the `RequestOTP` flow by `integration_test.go`/`e2e_test.go`/`service_test.go`), and
  it's the slow 600-bcrypt one. Drop its now-unused `ratelimit` import + the orphaned `multiCaptureSMS`.

Uniformity is left to `crypto/rand` (its guarantee). If `generateOTPCode` ever switched to a biased
mapping (e.g. `randUint32 % 1e6`), *that* would be a code change warranting a dedicated bias test — but the
current `rand.Int` is unbiased by construction.

## 4. make verify

The `-skip 'OTPCodeDistribution'` on `integration-identity-race` + `soak` excluded the slow integration
test for speed. With that test deleted, the flag matches nothing → removed. Bonus: `integration-identity-race`
now runs the **whole** identity suite under `-race` (no exclusion) — closing the F-006 gap ("identity
concurrency never runs under `-race`"), since the slow test that forced the exclusion is gone.

The whitebox `TestOTPCode_Format` runs in `make test` (`go test -race ./...`) and is deterministic — proven
with `-count=10` (10/10).

## 5. Out of scope

OTP generation algorithm; OTP delivery/validation/rate-limiting; other property tests; adding `-race` to
`integration-identity` itself (the no-race main path stays — its rationale is now general bcrypt speed, not
the deleted test).

## 6. Commits

1. this doc + docs closure (TESTING_AUDIT F-006 resolved; ROADMAP/REPORT tails).
2. `formatOTP` extraction (`service.go`).
3. test rewrite (`codegen_test.go` → `TestOTPCode_Format`) + delete the integration chi-square (`property_test.go`).
4. drop the dead `-skip` from `make integration-identity-race` + `soak`.
