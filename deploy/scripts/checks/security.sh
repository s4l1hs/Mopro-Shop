#!/usr/bin/env bash
# Section B — Security
# Sourced by launch-readiness.sh; uses pass/fail/warn and vds_get/vds_int.

check_security() {
  local SEC="B"

  # B1: Env file present on VDS
  local ef; ef=$(vds_int ENV_FILE_EXISTS)
  if [[ "$ef" -eq 1 ]]; then
    pass "$SEC" "env-file-exists" "/opt/mopro/.env present"
  else
    fail "$SEC" "env-file-exists" "/opt/mopro/.env missing — run init-secrets.sh"
  fi

  # B2: JWT_SIGNING_KEY length >= 32 chars
  local jl; jl=$(vds_int JWT_KEY_LEN)
  if [[ "$jl" -ge 32 ]]; then
    pass "$SEC" "jwt-key-length" "${jl} chars (≥32)"
  else
    fail "$SEC" "jwt-key-length" "${jl} chars (want ≥32) — regenerate JWT_SIGNING_KEY"
  fi

  # B3: PII_KEK_BASE64 length >= 32 chars
  local kl; kl=$(vds_int PII_KEK_LEN)
  if [[ "$kl" -ge 32 ]]; then
    pass "$SEC" "pii-kek-length" "${kl} chars (≥32)"
  else
    fail "$SEC" "pii-kek-length" "${kl} chars (want ≥32) — regenerate PII_KEK_BASE64"
  fi

  # B4: PII_PEPPER length >= 32 chars
  local pl; pl=$(vds_int PII_PEPPER_LEN)
  if [[ "$pl" -ge 32 ]]; then
    pass "$SEC" "pii-pepper-length" "${pl} chars (≥32)"
  else
    fail "$SEC" "pii-pepper-length" "${pl} chars (want ≥32) — regenerate PII_PEPPER"
  fi

  # B5: RESTIC_PASSWORD length >= 16 chars
  local rl; rl=$(vds_int RESTIC_PASS_LEN)
  if [[ "$rl" -ge 16 ]]; then
    pass "$SEC" "restic-pass-length" "${rl} chars (≥16)"
  else
    fail "$SEC" "restic-pass-length" "${rl} chars (want ≥16) — regenerate RESTIC_PASSWORD"
  fi

  # B6: No CHANGE_ME placeholders left in .env
  local cm; cm=$(vds_int CHANGE_ME_COUNT)
  if [[ "$cm" -eq 0 ]]; then
    pass "$SEC" "no-change-me" "0 CHANGE_ME placeholders"
  else
    fail "$SEC" "no-change-me" "${cm} CHANGE_ME value(s) still in .env — fill them in"
  fi

  # B7: TLS certificate > 30 days (local check via openssl)
  local tls_days=-1
  tls_days=$(python3 - <<'PY' 2>/dev/null || echo -1
import datetime, ssl, socket
try:
    ctx = ssl.create_default_context()
    with ctx.wrap_socket(socket.socket(), server_hostname='api.moproshop.com') as s:
        s.settimeout(5)
        s.connect(('api.moproshop.com', 443))
        cert = s.getpeercert()
        exp = datetime.datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z')
        print((exp - datetime.datetime.utcnow()).days)
except Exception:
    print(-1)
PY
  )
  if [[ "$tls_days" -ge 30 ]]; then
    pass "$SEC" "tls-cert-expiry" "${tls_days} days remaining (≥30)"
  elif [[ "$tls_days" -ge 0 ]]; then
    fail "$SEC" "tls-cert-expiry" "${tls_days} days remaining (want ≥30) — renew cert NOW"
  else
    warn "$SEC" "tls-cert-expiry" "Could not verify TLS cert (offline or DNS issue)"
  fi

  # B8: fin-svc:8081 in Caddyfile (not the wrong port)
  local finsvc; finsvc=$(vds_get CADDYFILE_FINSVC)
  if [[ "$finsvc" == "fin-svc:8081" ]]; then
    pass "$SEC" "caddyfile-finsvc-port" "fin-svc:8081 confirmed in Caddyfile"
  elif [[ "$finsvc" == "missing" ]]; then
    fail "$SEC" "caddyfile-finsvc-port" "Caddyfile not found on VDS"
  else
    fail "$SEC" "caddyfile-finsvc-port" "got '${finsvc}' — fin-svc must proxy to port 8081"
  fi
}
