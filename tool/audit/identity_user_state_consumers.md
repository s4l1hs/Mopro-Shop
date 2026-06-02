# Identity User-State-Consumer Sweep

Branch `fix/identity-getme-deleted-user-guard`. Base `main@8bfb224a` (PR #48 merged).
Closes the (B) classification from the `DeleteMe_BlocksSubsequentLogin` triage — but the
sweep found the `StatusDeleted` discipline is applied at only **3 of ~12** consumers, and one
gap (`VerifyEmail`) is **higher-severity than GetMe** (session issuance, not a read).

## §2.4 Repository-vs-service responsibility
`repo.GetUser` (`repository.go:45`) is `SELECT … WHERE id=$1` — **no `deleted_at` filter, by design**:
the repository is a dumb store; the **service layer owns the deleted-user policy**. (Correct — admin/
audit/recovery flows need to read deleted rows.) The guard belongs at the service layer, per-consumer.

## §2.2 Classification table

| # | Function | service.go | Returns/issues to caller | `StatusDeleted` guard | Class / severity |
|---|----------|-----------|--------------------------|------------------------|------------------|
| 1 | `VerifyOTP` | 121 (chk 172) | session (TokenPair) | **YES (inline)** | already-guards |
| 2 | `RefreshTokens` | 216 (chk 228) | session | **YES (inline)** | already-guards |
| 3 | `LoginEmail` | 498 (chk 518) | session / MFA-challenge | **YES (inline)** | already-guards |
| 4 | **`GetMe`** | 254 | **User profile** | **NO** | **GAP — moderate** (deleted user reads own profile via live access token; the failing test) |
| 5 | **`VerifyEmail`** | 572 | **session** (`issueTokensForUser`; the `if user.EmailVerified { … }` branch issues a session for an already-verified deleted user with no code check) | **NO** | **GAP — HIGH** (effective **login bypass for deleted email users** → fresh session/refresh; more severe than GetMe) |
| 6 | `VerifyStepUpOTP` | 295 | step-up token (capability) | **NO** | GAP — moderate (TTL-bounded; needs live access token via authenticated `RequestStepUpOTP`) |
| 7 | `UpdateMe` | 258 | updated User | **NO** | GAP — low (TTL-bounded write+read) |
| 8 | `RequestStepUpOTP` | 283 | sends OTP | NO | GAP — low (TTL-bounded action) |
| 9 | `ChangePassword` | 674 | sets password | NO | GAP — low (TTL-bounded, authenticated) |
| 10 | `EnrollMFA` | 703 | enrolls MFA | NO | GAP — low (TTL-bounded) |
| 11 | `ForgotPassword` | 627 | sends reset email | NO | minor (login still blocked by guard #3) |
| 12 | `ResendVerification` | 608 | sends email | NO | minor |
| 13 | `ResetPassword` | 647 | sets password (no session) | NO | minor (login still blocked) |
| 14 | `Register` | 459 (474) | existence/dedup check (`FindUserByEmailHash`) | n/a | not a state-return |
| 15 | `VerifyMFAChallenge` | 747 | session | NO inline, **upstream-gated by `LoginEmail`#518** | by-design (unreachable for deleted: a deleted user can't obtain an MFA challenge) |

## Key structural facts
- The shared session helper **`issueTokensForUser` (769) does NOT guard `Status`** — guards are inline
  per entry-flow. So adding a guard *there* is a single **choke point** covering `VerifyEmail` +
  `VerifyMFAChallenge` + any future session path (defense-in-depth; harmless redundancy for the
  already-guarded flows that don't route through it).
- `LoginEmail` (518) gates MFA-challenge creation → `VerifyMFAChallenge` is unreachable for deleted users.
- All deletion invariants the triage relied on hold: `SoftDeleteWithRevoke` revokes refresh tokens;
  refresh (#2) re-checks Status. The residual exposure for the low-severity gaps (#6–#13) is bounded by
  the access-token TTL, EXCEPT **#5 VerifyEmail**, which mints a *new* session (a fresh refresh token)
  for a deleted user — the one gap that escapes the TTL-window framing.

## §1.6 trigger #1 — FIRED
3+ gaps beyond GetMe, and **#5 `VerifyEmail` is meaningfully more severe** (login bypass for deleted
email users, not a TTL-bounded read). Per §1.6 #1 + §2.3 this is surfaced to the user to decide:
escalate the session-issuance gap to a focused security PR vs. fix inline here. The low-severity
action-func gaps (#6–#13) apply the same one-line discipline and can be swept together or Backlogged.
