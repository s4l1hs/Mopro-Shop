# Returns Batch — RT-02 · RT-03 · RT-05 (scoping)

Three banked returns items in one lane (shared returns surface). Scope re-derived
from the DEFER rationale in `docs/audits/TRENDYOL_PARITY_RETURNS_AUDIT.md`,
`docs/internal/returns-ui.md`, `docs/internal/returns-probable-resolution.md`, and
`CUTOVER_LEDGER.md` §4n. Built on the RT-01 settlement foundation (#188) — its
refund invariants are **untouched**.

## §4 / §12 money-path assessment (do this first)

**None of RT-02/03/05 is a money-path change.** The refund amount is computed once
at `CreateReturn` (`resolveLines` → `refundMinor`, unchanged) and settled by the
RT-01 path (`SellerApprove` → refund-as-coin mint, idempotent, balanced). RT-02 is
logistics (a return cargo code), RT-03 is evidence (photos), RT-05 is per-line
metadata (reason/note). **No refund recompute, no ledger write added, no §12/ADR
trigger.** The §4 invariants are preserved by *not touching* the settlement path;
a contract test re-asserts CreateReturn's refund block is unchanged.

## Discovery: the mobile returns flow is hand-written raw-Dio

`mobile/lib/features/order/data/return_dto.dart` carries **hand-written** DTOs for
both create (`CreateReturnRequest.toJson`) and detail (`ReturnDetailDto.fromJson`,
matching `GET /returns/{id}` — which is **not in the OpenAPI spec**). The mobile
does **not** use the codegen client for returns. So:
- The **return detail** response (RT-02 shipping, RT-03 photo urls, RT-05 per-line
  reason) is hand-written on both ends → **no codegen** for the detail.
- The **CreateReturn request** IS specced (`ReturnRequest`); to keep the spec
  truthful we add the new request fields there + regen (this lane's wave slot),
  even though the mobile sends them via its own DTO.

## Per-item scope + footprint

### RT-05 — per-item reasons — backend + codegen, **migration 0103**
- **Deferred scope:** the flow collects a per-item reason+note but the contract
  folds to a single header reason (first item's) + notes→description.
- **Plan:** migration 0103 adds `return_items.reason` + `return_items.note`
  (additive; reason nullable/defaulted). `ReturnItemInput`/`ReturnItem` gain
  Reason+Note; `CreateReturn` stores per-line reason (falls back to the header
  reason when a line omits one — e.g. full-order returns); `returnJSON` already
  serializes `ReturnItem` so the detail surfaces them automatically. Spec
  `ReturnRequest.items[]` += `reason`,`note` (codegen). Mobile: un-fold —
  `ReturnItemDto`+`reason`/`note`, send per line, detail shows per-line reason.

### RT-03 — return photos — backend + codegen, **migration 0104**
- **Deferred scope:** damage/wrong-item evidence on the request; reuse the existing
  `POST /uploads/photos` pipeline (product-photo carrier).
- **Plan:** migration 0104 adds `order_schema.return_photos` (return_id FK,
  photo_key, sort_rank). `ReturnInput`+`PhotoKeys`; `CreateReturn` inserts photos;
  `GetReturn` returns CDN urls (`mediaurl.CDNUrl`) → `returnJSON` += `photo_urls`.
  Spec `ReturnRequest.photo_keys[]` (codegen). Mobile: photo picker in the return
  form (reuse the upload pipeline → keys), detail renders the photos. **§6:** photos
  are user evidence; uploaded via the existing pipeline (no new PII surface here —
  keys, not raw bytes, transit the return API).

### RT-02 — return shipping (cargo code / drop-off) — backend (derived) + FE, **no migration, no codegen**
- **Deferred scope:** a return cargo code / drop-off / label so the buyer can send
  the item back (today the confirm shows the return *id* as a fake "tracking_no").
- **Discovery / honesty:** a **deterministic return cargo code** derived from the
  return id (a real, stable identifier *we* own) + a configured return **carrier**
  + i18n **drop-off instructions** — surfaced on the (hand-written) detail response.
  This is NOT a live carrier-API label/tracking integration (that remains a
  follow-up cargo-adapter vertical); it is not fabricated carrier data — it's our
  own return code, clearly labelled "İade Kargo Kodu". **No fee computed** → not a
  money path. No migration (derived), no codegen (detail not specced).

## Footprint summary (run matrix)

| Item | Backend | Codegen | Migration | Money path |
|---|---|---|---|---|
| RT-02 shipping code | derived (handler) | no | **none** | no |
| RT-03 photos | yes | **yes** (`ReturnRequest.photo_keys`) | **0104** | no |
| RT-05 per-item reasons | yes | **yes** (`ReturnRequest.items[].reason/note`) | **0103** | no |

- **Migrations: 0103 (RT-05), 0104 (RT-03)** — both additive, `order_schema`.
- **Codegen: `ReturnRequest` only** (request fields); detail responses stay
  hand-written. The mobile consumes via its own `return_dto.dart`.
- **§12 triggers: none.** RT-01 refund invariants preserved (not touched).
- **i18n:** `returns.*`; RT-02 drop-off + any refund/money copy gets DE/AR, the
  rest TR/EN (the #218 precedent).
