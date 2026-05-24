# SECURITY.md — Mopro Shop Security Procedures v1

> This document covers operational security procedures for Phase 5+.
> It complements CLAUDE.md §6 (Security Rules) and INFRASTRUCTURE.md §5 (Secrets).

---

## 1. JWT Key Rotation (Phase 5 Procedure)

### 1.1 Background

`core-svc` signs all access tokens (15-minute TTL) and step-up tokens (5-minute TTL)
using a single HS256 key loaded from `JWT_SIGNING_KEY` at startup.

Rotation means: all **active** refresh tokens continue to work (they are opaque random
strings, not JWTs), but all **active** access tokens and step-up tokens issued with
the old key become invalid at rotation time. Clients will receive a 401 on their
next request and must transparently refresh to get a new access token.

This is an acceptable UX impact given the 15-minute TTL — most users will not notice.

### 1.2 When to Rotate

Rotate `JWT_SIGNING_KEY` when any of the following occur:

| Trigger | Priority |
|---|---|
| JWT_SIGNING_KEY suspected compromised | IMMEDIATE (<1 hour) |
| Key is older than 90 days | Scheduled maintenance window |
| Security audit finding | Per finding severity |
| Any team member with key access departs | Within 24 hours |

### 1.3 Pre-Rotation Checklist

- [ ] Confirm VDS SSH access is working (`ssh -p 4625 mopro@195.85.207.92`)
- [ ] Take a snapshot of active refresh-token count: `SELECT count(*) FROM identity_schema.refresh_tokens WHERE revoked_at IS NULL AND expires_at > now()`
- [ ] Notify on-call channel: "JWT key rotation starting in 5 minutes — expect brief 401 spike"
- [ ] Schedule rotation during low-traffic window (ideally 03:00–04:00 UTC)

### 1.4 Rotation Procedure

**Step 1 — Generate new key**

```bash
# On a secure machine (not the VDS), generate a 32-byte key:
openssl rand -base64 32
# Example output: xKj9mP3nQ7rT2vU5wY8zA1bC4dE6fG0hI/J+K=
```

**Step 2 — Update the secret on VDS**

```bash
ssh -p 4625 mopro@195.85.207.92

# Edit the production env file:
sudo nano /opt/mopro/.env
# Update JWT_SIGNING_KEY=<new_base64_value>
# Save and exit

# Verify the change (confirm correct character count):
grep JWT_SIGNING_KEY /opt/mopro/.env | wc -c
# Expected: ~55 chars (key + env var name + =)
```

**Step 3 — Rolling restart core-svc**

```bash
# On VDS:
cd /opt/mopro
docker compose pull core-svc   # no-op; just ensures latest image
docker compose up -d --no-deps core-svc   # recreate only core-svc
docker compose ps core-svc                # should be "running"
```

Docker Compose recreates the container with the new env, picking up the
new `JWT_SIGNING_KEY`. Active access tokens signed with the old key will
immediately return 401 on next use; clients refresh transparently.

**Step 4 — Verify**

```bash
# Smoke test: request OTP → verify → check token
curl -sf -X POST https://api.moproshop.com/auth/otp/request \
     -H "Content-Type: application/json" \
     -d '{"phone":"+905321234567"}' \
  && echo "OTP request OK"

# Verify logs show no JWT validation errors from the old key:
docker logs core-svc --since=2m 2>&1 | grep -i "jwt\|invalid\|signature"
# Expected: no output (or only successful verifications)
```

**Step 5 — Record the rotation**

Add an entry to `docs/key-rotations.md` (create if absent):

```markdown
| Date | Key fingerprint (first 8 chars of base64) | Reason | Operator |
|---|---|---|---|
| 2026-05-22 | xKj9mP3n | Scheduled 90-day | @salihsefer36 |
```

### 1.5 Emergency Rotation (Compromise)

If the key is suspected compromised:

1. **Immediately** follow Steps 1–3 above (no scheduled window).
2. Revoke ALL active refresh tokens (forces all users to re-login):
   ```sql
   UPDATE identity_schema.refresh_tokens
   SET revoked_at = now(), revoked_reason = 'admin'
   WHERE revoked_at IS NULL;
   ```
   ```bash
   docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
     "UPDATE identity_schema.refresh_tokens SET revoked_at=now(),revoked_reason='admin' WHERE revoked_at IS NULL;"
   ```
3. Notify users via in-app push (jobs-svc FCM) that they need to re-login.
4. File an internal incident report.

---

## 2. PII Encryption Key (PII_KEK_BASE64)

`PII_KEK_BASE64` is the AES-256-GCM key used by `pkg/crypto.EncryptPII`/`DecryptPII`
to encrypt phone numbers, emails, and other PII at rest.

### 2.1 Rotation is destructive — requires re-encryption

Unlike JWT key rotation, rotating `PII_KEK_BASE64` requires decrypting every encrypted
column with the old key and re-encrypting with the new key. This is a **data migration**,
not a restart.

**Do NOT rotate PII_KEK_BASE64 casually.** Only rotate when:
- Key is suspected compromised
- Mandatory compliance audit requires it

### 2.2 Re-encryption procedure (Phase 5+)

A dedicated `cmd/mopro` CLI command will be added in Phase 5:

```bash
# Planned — not yet implemented:
./mopro pii re-encrypt --old-kek $OLD_KEK --new-kek $NEW_KEK --dry-run
./mopro pii re-encrypt --old-kek $OLD_KEK --new-kek $NEW_KEK --confirm
```

Until Phase 5, PII key rotation requires a manual script. Contact the platform
engineering lead before attempting.

---

## 3. OTP Security Notes

- OTP codes are 6-digit, generated from `crypto/rand` (cryptographically secure).
- Bcrypt cost=10 is used for OTP code storage (same security level as passwords).
- Rate limiting: 3 requests per 10 min per phone, 10 per hour per IP (via Redis Lua).
- 10 consecutive failed verifications lock the phone for 1 hour.
- `DEV_OTP_ACCEPT_ANY=true` is a development backdoor. The service **panics at startup**
  if this env is set with `ENV=production`.

---

## 4. Refresh Token Security

- Refresh tokens are 64-character opaque hex strings, stored only as SHA-256 hashes.
- Token rotation: every use of a refresh token issues a new one and revokes the old.
- **Theft detection**: if a revoked token is reused, the entire token family is revoked.
  This forces all devices for that user to re-authenticate.
- Refresh token TTL: 30 days. Stale tokens are cleaned hourly by the cleanup worker.

---

## 5. Secrets Management Rules (Operations)

| Secret | Location | Rotation |
|---|---|---|
| `JWT_SIGNING_KEY` | `/opt/mopro/.env` | 90 days or on compromise |
| `PII_KEK_BASE64` | `/opt/mopro/.env` | Only on compromise |
| `PII_PEPPER` | `/opt/mopro/.env` | Never (changing breaks all phone lookups) |
| `ECOM_DB_PASSWORD` | `/opt/mopro/.env` + PgBouncer | Annually |
| `LEDGER_DB_PASSWORD` | `/opt/mopro/.env` + PgBouncer | Annually |
| `REDIS_PASSWORD` | `/opt/mopro/.env` | Annually |

**PII_PEPPER must NEVER be rotated after first use.** Changing it invalidates all
existing `phone_hash` values, making every user unfindable by phone. If the pepper
is compromised, all users must re-register (catastrophic). Store it with maximum security.

---

## 6. CloudFlare WAF Notes

Mopro routes all traffic through CloudFlare (Free tier). The VDS does NOT accept
direct connections from non-CloudFlare IPs (Caddy validates via `CF-Connecting-IP`).

If CloudFlare is bypassed (direct IP access), the identity service still works
correctly — CloudFlare is a defence-in-depth layer, not the primary auth mechanism.

---

**End of SECURITY.md.** For architecture decisions affecting security, see CLAUDE.md §6.
For key storage on the VDS, see INFRASTRUCTURE.md §5.
