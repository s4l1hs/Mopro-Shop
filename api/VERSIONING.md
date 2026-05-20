# API Versioning Policy

## Summary

`api/openapi.yaml` is the authoritative contract for all Mopro Shop HTTP endpoints.
The current API version is `v1` (path prefix `/v1/`). This document defines what
constitutes a breaking change and how breaking changes are handled.

---

## Breaking vs. Non-Breaking Changes

### Non-breaking (deploy freely)

- Adding a **new optional field** to a response body.
- Adding a **new optional query parameter**.
- Adding a **new endpoint** under the existing `/v1/` prefix.
- Expanding an enum by adding new values (clients must handle unknown enum values gracefully).
- Improving error messages (same `code`, better `message`).
- Performance improvements with no behavioral change.

### Breaking (require versioning process below)

- Removing a field, endpoint, or query parameter.
- Renaming a field or endpoint path.
- Changing a field's type or format.
- Making an optional field required.
- Removing an enum value.
- Changing authentication requirements for an existing endpoint.
- Changing pagination style (page-based → cursor-based).
- Changing a 200 response to a 4xx/5xx (for the same input conditions).

---

## Breaking Change Process

1. **Add the new shape under `/v2/`** — implement the new endpoint alongside the v1 version.
2. **Dual-serve period**: v1 and v2 are served simultaneously for **at least 6 months**.
   During this window, the v1 endpoint is marked `deprecated: true` in the spec.
3. **Mobile release coordination**: a new mobile build must ship and reach ≥ 95% adoption
   before v1 removal is scheduled.
4. **Sunset header**: add `Sunset: <RFC 1123 date>` to v1 responses 60 days before removal.
5. **Remove v1**: after the dual-serve window AND adoption target is met, open a PR that
   removes the v1 endpoint from the spec and from all generated files. This PR requires
   explicit human approval from the product owner.

A breaking change that does not follow this process is a **production incident**.

---

## Additive Field Policy

Generated clients (Dart `mopro_api` package) must be written to ignore unknown JSON fields.
The Dart `json_serializable` generated code handles this by default via the `includeIfNull: false`
pattern — unknown keys are silently dropped.

Go handlers must not fail if they receive a response with extra fields. Always use
`json.Decoder` (not `json.Unmarshal` with strict mode) when decoding external responses.

---

## Spec Change Checklist

Before merging any change to `api/openapi.yaml`:

- [ ] `make api-lint` → 0 Spectral errors
- [ ] `make api-gen` → generated files updated and staged
- [ ] `make contract-test` → all contract tests pass
- [ ] If breaking: versioning process started (v2 endpoint added, v1 marked deprecated)
- [ ] PR description documents WHAT changed and WHY

---

*This document is part of the Mopro Shop architecture constitution. Changes require
explicit human approval.*
