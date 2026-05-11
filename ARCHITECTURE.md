# ARCHITECTURE.md — System Topology v7

This document is the source of truth for the runtime topology. Read before any infrastructure or networking change. Reflects PRD v6.0 (perpetual cashback) + v7 detail packs (PSP & kargo API'ları, mobil 30+ ekran, anti-fraud ML, TR e-fatura/e-arşiv/GİB).

---

## 1. Bird's-Eye View

```
[ Mobile Flutter app ]                                                        ┐
        │ HTTPS                                                                │ TR launch:
        ▼                                                                      │ - tr-TR locale
[ CloudFlare ]                  (CDN + WAF + DDoS + DNS, Free tier)            │ - TRY currency
        │ HTTPS to api.moproshop.com                                           │ - TRY_COIN cashback
        ▼                                                                      │ - MARKET=TR
[ VDS public IP ]               (single 6c/24GB/120GB)                         │
        │ ports 80, 443, 58022 (UFW enforced; 58022 is SSH)                    │ Future markets:
        ▼                                                                      │ - de-DE / EUR / EUR_COIN
[ Caddy 2 ]                     (reverse proxy, TLS, rate limit)               │ - en-US / USD / USD_COIN
        ├──► core-svc:8080      (HTTP/JSON)                                    │ - ar-AE / AED / AED_COIN
        ├──► fin-svc:8080       (HTTP/JSON, wallet/cashback/payout read)       │ Same backend, config-only
        └──► jobs-svc:8080      (HTTP/JSON)                                    ┘
                │
                ▼
[ PgBouncer ]   (transaction mode)
        ├──► pgbouncer-ecom   → postgres-ecom    (mopro-net)
        └──► pgbouncer-ledger → postgres-ledger  (mopro-fin-net)

[ Redis 7 ]        cache + sessions + Streams (event bus)
[ Meilisearch ]    search (TR + EN + DE + AR aware)
[ Backblaze B2 ]   backup target (over Internet)
[ Grafana Cloud ]  logs/metrics/traces (over Internet)
```

---

## 2. Two Docker Networks

### 2.1 mopro-net (e-commerce side)

Members: `caddy`, `core-svc`, `jobs-svc`, `pgbouncer-ecom`, `postgres-ecom`, `redis`, `meilisearch`, `grafana-agent`. fin-svc also joins for Redis access only.

### 2.2 mopro-fin-net (FinTech isolation)

Members: `fin-svc`, `pgbouncer-ledger`, `postgres-ledger`. NO TCP path from core-svc/jobs-svc to postgres-ledger.

### 2.3 Network rules

- core-svc and jobs-svc MUST NOT have `mopro-fin-net` membership.
- fin-svc is on BOTH networks.
- postgres-ledger is on `mopro-fin-net` ONLY.

Verification:
```bash
docker exec core-svc nc -zv postgres-ledger 5432    # MUST FAIL
docker exec fin-svc  nc -zv postgres-ledger 5432    # MUST SUCCEED
docker exec fin-svc  nc -zv redis 6379              # MUST SUCCEED
```

---

## 3. Three Binaries — Why Not Microservices

### 3.1 The decision

Earlier drafts proposed 12+ microservices (one per module). The decision is **3 binaries** because:

1. **Operational cost.** A 2–3 person team cannot reliably operate 12+ deployable units (12 dashboards, 12 build pipelines, 12 alert routes) on a single VDS.
2. **In-process latency.** Within core-svc, modules talk via Go function calls (0 ms). Splitting them adds 5–15 ms HTTP round-trip per inter-module call. The order checkout flow alone makes ~6 inter-module calls; that is 30–90 ms wasted per request.
3. **Debug ergonomics.** A single Go stack trace beats 7 distributed traces every time, especially for a small team.
4. **FinTech isolation preserved.** fin-svc stays separate (its own binary, its own DB, its own network). The compliance argument is intact.

### 3.2 What stayed the same

- Module boundaries (identity, catalog, order, wallet, cashback, sellerpayout, etc.) are unchanged. They are now Go packages instead of binaries.
- DB schema-per-module is unchanged.
- Event-driven communication between core-svc and fin-svc is unchanged.
- Path to true microservices is open: depguard enforces module boundaries; any module is one day's work to extract later.

### 3.3 What changed

- Inter-module communication inside core-svc became in-memory function calls.
- core-svc → fin-svc communication is the ONLY mandatory async boundary.
- Number of containers dropped from ~16 to ~9.

---

## 4. Process Layout Inside Each Binary

### 4.1 core-svc

```
core-svc binary
├── HTTP server (Caddy-facing) :8080
├── Metrics server :9090
├── Background workers
│   └── outbox-publisher (ecom-side outbox topics)
└── Modules
    ├── identity     (auth, OTP, KYC, locale)
    ├── catalog      (multi-currency, multi-language, category + commission_pct snapshot)
    ├── cart
    ├── order        (saga orchestrator; emits ecom.order.delivered.v1 with delivered_at)
    ├── payment      (PSP adapter — Sipay/Craftgate/iyzico/Stripe/...)
    ├── seller       (seller panel; transparency endpoint /api/v1/seller/orders/:id/breakdown)
    └── search       (Meilisearch wrapper)
```

### 4.2 fin-svc

```
fin-svc binary
├── HTTP server :8080 (admin / wallet read / cashback read / payout read)
├── Metrics server :9090
├── Background workers
│   ├── outbox-publisher              (Redis Streams XADD from postgres-ledger.outbox)
│   ├── event-consumer                (Redis Streams XREADGROUP for ecom.* topics)
│   ├── ledger-reconcile-worker       (hourly per-currency)
│   ├── cashback-monthly-cron         (1st of month 02:00 UTC: pay due cashback installments)
│   ├── seller-payout-daily-cron      (every day 02:30 UTC: pay due seller payouts)
│   ├── treasury-monitor              (daily: track central bank rates, raise alerts)
│   └── balance-mv-refresh            (hourly: REFRESH MATERIALIZED VIEW wallet_balances)
└── Modules
    ├── wallet            (ledger I/O, balance API)
    ├── commission        (commission rules read from ref_schema, accruals, settlements)
    ├── treasury          (float yield, FX, bank reconciliation)
    ├── cashback          (plan generation + freeze + monthly payment cron)
    └── sellerpayout      (NEW v5: net amount calc + delivered+3BD payout cron)
```

### 4.3 jobs-svc

```
jobs-svc binary
├── HTTP server :8080
├── Metrics server :9090
├── Workers
│   ├── notification-sender       (FCM, APNs, SMS, email)
│   ├── support-ai-router         (AI intent → article or ticket)
│   ├── media-resize-worker       (image resize → Backblaze B2)
│   ├── antifraud-inference       (v7: ONNX models — NLP + vision classifiers)
│   └── einvoice-submitter        (v7: GİB e-fatura/e-arşiv submission worker)
└── Modules
    ├── notification
    ├── support
    ├── media
    ├── sizefinder
    ├── antifraud_inference       (v7: serves /internal/v1/antifraud/score)
    └── einvoice                  (v7: GİB integration via bulut sağlayıcı)
```

Note: `antifraud_inference` runs ONNX models on CPU. The **decision module**
(`/internal/antifraud/`) lives in core-svc; jobs-svc only does inference. This
keeps the heavy ML libs out of the latency-critical core-svc binary.

Note: `einvoice` module submits invoices through a Bulut e-Fatura provider
(Logo Software, Foriba, Uyumsoft, Mikro, GİB Portal). Mopro is the issuer; the
provider routes to GİB. See § 8.7 for provider comparison.

---

## 5. Data Flow — Order Completion + Cashback Plan + Seller Payout

End-to-end happy path:

```
1. POST /v1/orders/checkout (mobile) ───► Caddy
2. Caddy ───► core-svc:8080
3. core-svc.order calls cart, catalog (commission_pct snapshot), payment (in-memory)
4. core-svc.payment calls PSP (HTTPS egress through CloudFlare to Sipay/Craftgate)
5. core-svc.order writes orders + order_items (with commission_pct_bps snapshot) +
   order_outbox row in postgres-ecom (one tx)
6. ecom outbox-publisher XADDs ecom.payment.captured.v1 to Redis Streams
7. fin-svc.commission XREADGROUPs the event
8. fin-svc.commission writes accrual rows in postgres-ledger
9. (later, when delivery confirmed) Kargo webhook → core-svc.order
10. core-svc.order updates order status='delivered', records delivered_at, writes outbox
    ecom.order.delivered.v1 with {order_id, delivered_at, market, items[]}
11. fin-svc.cashback XREADGROUPs ecom.order.delivered.v1 (v6 PERPETUAL):
    a. Computes unlock_at = pkg/timex.AddBusinessDays(delivered_at, 3, "TR")
    b. Computes monthly_amount = (Σ commission_amount_minor × ref_rate(5000bps)) / 10000 / 12
    c. INSERTS cashback_schema.plans row (frozen via plans_immutable trigger; perpetual — no end date)
    d. NO ledger move at plan creation. Mopro's commission cash already in equity:retained_commission:TRY
       from order capture; the perpetual model recognizes coin distribution period-by-period.
12. fin-svc.sellerpayout XREADGROUPs the SAME ecom.order.delivered.v1
    a. Computes seller_net_minor (gross - commission - KDV) per item
    b. Computes unlock_at = pkg/timex.AddBusinessDays(delivered_at, 3, "TR")
    c. INSERTS commission_schema.seller_payouts row, status='scheduled'
13. Cashback monthly cron (1st of each month, 02:00 UTC) — v6 PERPETUAL:
    - SELECT active plans WHERE start_date <= today (plan-driven, not pre-seeded payments)
    - For each: INSERT cashback_schema.payments row for current period_yyyymm,
      then write ledger_entries (single transaction):
        D equity:cashback_distribution:TRY_COIN  amount=plan.monthly_amount_minor
        C liability:wallet:user_<id>:TRY_COIN     amount=plan.monthly_amount_minor
    - Mark payment row status='paid', record ledger_transaction_id
    - Outbox event fin.cashback.payment.posted.v1
14. Seller payout daily cron (every day, 02:30 UTC):
    - SELECT seller_payouts WHERE unlock_at <= today AND status='scheduled'
    - For each: PSP transfer initiate (psp_transfer_id stored)
    - Ledger move: D liability:seller_payable:TRY
                   C asset:bank:escrow:TRY
    - Mark payout status='paid', paid_at=now()
    - Outbox event fin.seller.payout.posted.v1
15. jobs-svc.notification consumes fin.cashback.payment.posted.v1 → push notification
    "Bu ay X Mopro Coin kazandın!"
    AND fin.seller.payout.posted.v1 → seller email/push
    "Sipariş #ABC için ₺Y net ödemen yapıldı"
```

Every step is idempotent. Every event has a `trace_id` linking them in Grafana Tempo. Every event carries `market` and `currency` labels.

---

## 6. Public DNS

| Hostname | Target | Purpose |
|---|---|---|
| `api.moproshop.com` | CloudFlare → VDS | Mobile API |
| `seller.moproshop.com` | CloudFlare → VDS | Seller web panel (transparency, payouts, orders) |
| `img.moproshop.com` | CloudFlare → Backblaze B2 | Public media |

CloudFlare proxy ON (orange cloud) for all three. SSL/TLS mode: Full (strict).

---

## 7. Multi-Market Readiness

Initial deployment serves a single market (TR). Future markets are activated by:

1. Adding rows to `ref_schema.currencies`, `ref_schema.countries`, `ref_schema.locales`, `ref_schema.business_calendars`, `ref_schema.commission_rules`.
2. Seeding the new market's currency in the wallet chart of accounts (e.g., `equity:cashback_distribution:EUR_COIN`, `liability:wallet:user_<id>:EUR_COIN`).
3. Adding translation files under `/mobile/assets/translations/<locale>.json`.
4. Optionally adding region-specific subdomains (`de.api.moproshop.com` → same backend).
5. Configuring a market-appropriate PSP adapter (e.g., Stripe Connect for EU).
6. Configuring market-appropriate KYC level and tax engine.
7. Seeding business holidays for the new market in `ref_schema.business_calendars` so the 3-business-day delay calculation is accurate.

NO code change is required for a new market. Configuration only. This is enforced by the `MARKET` env label and depguard rules that forbid hardcoded currency/market strings in business logic.

The cashback engine reads `commission_pct_bps` snapshotted on `order_items` (always single source of truth at order time). The seller payout engine reads the same snapshot.

---

## 8. Regulatory & Payment Provider Strategy

### 8.1 Coin Issuance Jurisdiction

Mopro Coin is TL-pegged but its legal issuance jurisdiction is **NOT Türkiye**. Candidate jurisdictions:

| Jurisdiction | License Type | Advantage | Disadvantage |
|---|---|---|---|
| Dubai (UAE) | VARA Cat 1 (Issuer) | Crypto-friendly, 3-6 month process, tax advantage, MENA proximity | New regulation (limited precedent), banking onboarding takes time |
| Lithuania | EMI (Electronic Money Institution) | EU passport (27 countries), mature process (~6 months), low capital (€350K) | EU regulatory load, MiCA compliance |
| Estonia | EMI / VASP | Digital nomad friendly, fast setup (weeks) | Banking acceptance harder, strict AML |
| Malta | MFSA EMI / VFA | Mature regulation, EU passport, crypto experience | Expensive (€500K+ capital), slow (12+ months) |

Final choice is made before launch. Architectural impact: jurisdiction selection determines data residency, KYC tiers, and reporting format. Code impact is **minimal**; PII encryption, audit log retention, and KYC tier configuration are env-driven.

During the licensing window (months 1-6 post-launch), Mopro Coin is positioned as a **loyalty point** in TR; coin → fiat conversion is DISABLED. After license activation, conversion goes live for retroactive balances.

### 8.2 PSP Adapter Strategy

Türkiye launch PSP selection criteria:

1. **Marketplace / sub-merchant API** mandatory (split payment, seller-level accounting, outbound transfer for the daily payout cron).
2. **Lowest commission** at scale (negotiable as volume grows).
3. **3DS Secure** and broad bank coverage.

Candidate providers (May 2026 baseline; rates are negotiation starting points):

| Provider | Commission | Marketplace Maturity | Notes |
|---|---|---|---|
| Sipay | %1.69-2.29 + KDV | Medium-High | **Recommended primary**: best commission + sub-merchant balance + outbound transfer API |
| Craftgate | %1.79-2.49 + KDV | High (leader) | **Recommended backup**: most mature marketplace API |
| iyzico | %1.99-2.49 + KDV | High | PayPal subsidiary, brand trust |
| Param | %1.49-1.99 + 0.30 TL | Medium | Lowest commission, marketplace evolving |

Future EU expansion (Phase 7+) adapters: **Stripe Connect**, **Mollie**, **Adyen Marketplace**, **PayPal Commerce**.

All providers sit behind the `payment.Service` and `sellerpayout` adapter interfaces. Provider selection is env-driven (`PSP_PROVIDER=sipay`); code never changes.

### 8.3 Data Residency

- Türkiye launch: VDS in `eu-central-1` (Frankfurt) — KVKK compatible, low latency to TR.
- EU license scenario: same region, no change.
- Dubai license scenario: licensed entity (issuer/custodian) is in Dubai; application and data can stay in `eu-central-1` since VARA does not mandate data residency.
- New market expansion: regional CDN nodes via CloudFlare are automatic; the application stays in a single region until 200K+ users/hour threshold.

### 8.4 Shipping Adapter Strategy

TR launch shipping carriers (each with its own API/webhook adapter):

```
/internal/shipping/aras/
/internal/shipping/yurtici/
/internal/shipping/surat/
/internal/shipping/mng/
/internal/shipping/hepsijet/
/internal/shipping/ptt/
```

`shipping.Service` interface exposes: `CreateLabel`, `TrackShipment`, `CreateReturnLabel`, `HandleWebhook`. Seller selects preferred carrier per store or per product. Trendyol-style three modes: bedava kargo (satıcı yüklenir), standart kargo (alıcı öder), eşik üstü bedava.

Webhook receipt of "delivered" status is the ONE source of truth for `delivered_at`. The 3-business-day delay starts from this timestamp (using TR business calendar for launch).

See § 8.6 for per-carrier API endpoint reference.

### 8.5 PSP API Reference (TR launch)

| Provider | Sandbox URL | Auth | Notable Endpoints | Webhook Signature |
|---|---|---|---|---|
| **Sipay** (primary) | `https://provisioning.sipay.com.tr/ccpayment` | Token (`/api/token` w/ merchant_key+app_id+app_secret); cache 30 min | `/api/paySmart3D`, `/api/refund`, `/api/checkstatus`, `/sub_merchant_register`, `/sub_merchant_pay`, `/sub_merchant_settlement` | `hash_key` header = `base64(hmacSha256(rawBody, app_secret))` |
| **Craftgate** (backup) | `https://sandbox-api.craftgate.io` | HMAC-SHA256 per request (`x-api-key`, `x-rnd-key`, `x-signature`) | `/payment/v1/payments`, `/payment/v1/init-3ds`, `/payment/v1/complete-3ds`, `/onboarding/v1/sub-merchants`, `/payout/v1/payout` | `x-craftgate-signature` = `hmacSha256(rawBody, webhook_secret)` |
| **iyzico** (fallback) | `https://sandbox-api.iyzipay.com` | HMAC-SHA1 + Base64 (`Authorization: IYZWS <key>:<hash>`) | `/payment/3dsecure/initialize`, `/payment/3dsecure/auth`, `/payment/refund`, `/payment/cancel`, `/onboarding/sub-merchant`, `/payment/iyzipos/marketplace/payout` | (callback URL only, no header signature; verify via `paymentId` lookup) |

**PSP fee comparison (May 2026 negotiated baseline; per transaction):**

| Provider | Base commission | Marketplace fee | Sub-merchant transfer | Notes |
|---|---|---|---|---|
| Sipay | %1.69 + KDV | included | 1.50 TL flat | Best at scale; min monthly 5K TL |
| Craftgate | %1.79 + KDV | %0.10 add | 1.20 TL flat | Most mature marketplace API |
| iyzico | %1.99 + KDV | included | 2.00 TL flat | PayPal subsidiary; brand trust |
| Param | %1.49 + 0.30 TL | extra | varies | Cheapest; marketplace evolving |

Switching providers is env-driven (`PSP_PROVIDER`) — no code change. In-flight payments retain the original provider's `providerRef` and complete on that provider.

**PCI-DSS scope:** Mopro NEVER touches raw card numbers; all 3DS flows render the PSP's hosted card form (HPP). Mopro is SAQ-A scope (lowest tier).

**Sandbox setup:** Apply for sandbox credentials via:
- Sipay: integration@sipay.com.tr (1-2 weeks)
- Craftgate: support@craftgate.io (3-5 days)
- iyzico: developer.iyzipay.com self-serve

### 8.6 Kargo API Reference (TR launch)

Six carriers behind a single `shipping.Service` interface. Each adapter implements: `CreateLabel`, `TrackShipment`, `CreateReturnLabel`, `HandleWebhook`, `CalculateRate`.

| Carrier | API style | Sandbox URL / Test mode | Auth | Notable Endpoints | Webhook |
|---|---|---|---|---|---|
| **Aras Kargo** | SOAP (legacy) + REST (new) | `https://test-customerservices.araskargo.com.tr/aras-rest-api/test/` | Basic auth (username + password + customer_code) | `POST /api/v1/shipment` (create), `GET /api/v1/shipment/{trackingNo}` (track), `POST /api/v1/shipment/{trackingNo}/cancel` | Polling-based (no native webhook); poll every 5 min via cron |
| **Yurtiçi Kargo** | SOAP | `https://testservis.yurticikargo.com/KOPSWebServices/services/ShippingOrderServiceV2` | WS-Security UsernameToken | `createShippingOrder`, `queryShipment`, `cancelShippingOrder` | Polling; subscribe to status webhook in admin panel for prod |
| **Sürat Kargo** | REST | `https://uatxapi.suratkargo.com.tr` | Bearer JWT (`POST /api/auth/login`) | `POST /api/shipment/create`, `GET /api/tracking/{barcode}`, `POST /api/return/create` | Webhook to our `/v1/shipping/webhook/surat`; signature: `X-Surat-Sign` = `hmacSha256(body, secret)` |
| **MNG Kargo** | REST | `https://testapi.mngkargo.com.tr/mngapi` | API-Key header + JWT | `POST /api/standardcmdapi/createOrder`, `GET /api/cargotracking/{trackingNo}` | Webhook to `/v1/shipping/webhook/mng`; HMAC-SHA256 |
| **HepsiJet** | REST | `https://api-test.hepsijet.com` | OAuth2 client_credentials | `POST /v1/shipments`, `GET /v1/shipments/{id}`, `POST /v1/shipments/{id}/return` | Webhook to `/v1/shipping/webhook/hepsijet`; bearer-token validated |
| **PTT Kargo** | SOAP | `https://wstest.ptt.gov.tr/MusteriHizmetleriWS/services` | Basic auth + customer_code | `BarkodOlustur`, `KargoTakip`, `IadeOlustur` | No native webhook; daily batch reconcile |

**Carrier selection:** Per-product or per-shop default. Buyer at checkout can override with available alternatives. Free shipping rules per `ref_schema.shipping_rules` (threshold + carrier).

**Standard internal payload (normalized across carriers):**

```go
type ShipmentInput struct {
    OrderID             int64
    SellerAddressRef    int64           // pickup
    BuyerAddressRef     int64           // delivery
    PackageWeightGrams  int
    PackageDimensionsCM struct{ L, W, H int }
    DeclaredValueMinor  int64
    DeclaredValueCurr   string
    ServiceLevel        string          // 'standard' | 'express' | 'same_day'
    InsuranceWanted     bool
    CashOnDelivery      bool            // KAPIDA ÖDEME (rare in v1)
    Notes               string
}

type ShipmentResult struct {
    CarrierName       string
    TrackingNumber    string
    LabelPDFBase64    string            // print-ready
    EstimatedDelivery time.Time
    CostMinor         int64
    Currency          string
}
```

**Failover:** If primary carrier API is down for > 5 min, system auto-failsover to next-cheapest carrier in seller's allowed list. Logged as `mopro_shipping_failover_total{from,to}`.

**Sandbox onboarding (May 2026):**
- Aras: integration@araskargo.com.tr (corporate contract required first; 2-3 weeks)
- Yurtiçi: kurumsal@yurticikargo.com (corporate; 1-2 weeks)
- Sürat: digital@surat.com.tr (1 week)
- MNG: bilgi@mngkargo.com.tr (corporate; 1-2 weeks)
- HepsiJet: hepsijet@hepsiburada.com (online; 3-5 days)
- PTT: kep@hs02.kep.tr (formal application; 3-4 weeks)

### 8.7 TR Vergi Entegrasyonu — e-Fatura / e-Arşiv / GİB

Mopro her satışta **iki türlü fatura** kesmek zorundadır (TR mevzuat — Mali İdare):

| Fatura türü | Kim için | Yıllık ciro eşiği | Mopro'da kullanım |
|---|---|---|---|
| **e-Fatura** | B2B (mükellef → mükellef) | Mopro 5M TL+ ciroyla otomatik mükellef | Satıcı şirketten Mopro'ya kesilen komisyon faturası; Mopro'dan satıcı şirketine kesilen komisyon faturası (mükellef satıcılar için) |
| **e-Arşiv Fatura** | B2C (mükellef → tüketici) | Mopro 5M TL+ ciroyla otomatik mükellef | Mopro'dan tüketici alıcıya kesilen satış faturası (üründen aldığı şahsen) — ama Mopro satıcı değil! Bu bir karmaşıklık (aşağıda) |
| **e-SMM** (serbest meslek makbuzu) | Mopro KAPSAM DIŞI | — | Mopro tüketici hizmeti vermiyor |

**Marketplace fatura mantığı (TR):**

Mopro bir **marketplace operatörü**dür, satılan ürünün satıcısı DEĞİLDİR. Yasal akış:

1. **Satıcı → Alıcı:** Ürün faturası satıcı tarafından alıcıya kesilir (e-fatura B2B ise satıcının VKN'si, B2C ise e-arşiv). Satıcı kendi mükellefidir; e-fatura altyapısı kendi sorumluluğundadır.
2. **Mopro → Satıcı:** Komisyon faturası Mopro tarafından satıcıya kesilir (e-fatura, mükellef satıcı için; mükellef olmayan küçük satıcılar için gider pusulası). KDV %20 dahil.
3. **Satıcı (ürün) faturası API ile Mopro'ya iletilir** — Mopro sipariş geçmişinde alıcıya gösterir (görüntüleme amacıyla; Mopro'nun mali sorumluluğu yok).

**Bulut e-Fatura Sağlayıcı Karşılaştırması (May 2026):**

| Sağlayıcı | Tip | Aylık ücret | Per-fatura | API kalitesi | Notlar |
|---|---|---|---|---|---|
| **GİB Portal** | Devlet | 0 TL | 0 TL | API yok (sadece manuel) | Düşük hacim için; otomasyon imkansız → Mopro için UYGUN DEĞİL |
| **Logo Yazılım** | Özel entegratör | 1.500 TL | 0.40-0.80 TL | İyi REST API + WSDL | Pazar lideri; doküman bol |
| **Mikro Yazılım** | Özel entegratör | 1.200 TL | 0.35-0.70 TL | REST API | Mid-market |
| **Foriba** | Özel entegratör | 2.500 TL | 0.30-0.60 TL | En zengin REST API + webhooks | Enterprise; Trendyol kullanır |
| **Uyumsoft** | Özel entegratör | 1.000 TL | 0.50 TL | REST API | Bütçe dostu |
| **NES (Nesbilgi)** | Özel entegratör | 1.800 TL | 0.45 TL | REST API + Java SDK | Logo'ya alternatif |

**Mopro lansman seçimi:** Foriba (öneri sebebi: REST API olgun, webhook desteği var, marketplace-style yüksek hacme uygun, doğru e-arşiv akışı). Aylık tahmini maliyet 1000 sipariş/ay × 0.45 TL + 2.500 TL = ~2.950 TL/ay.

**Foriba API endpoint'leri (özet):**
- Auth: `POST /auth/login` → JWT (24h TTL)
- Send invoice: `POST /einvoice/send` (UBL-TR XML payload)
- Send e-arşiv: `POST /earsiv/send`
- Status check: `GET /invoice/status/{id}`
- Cancel: `POST /einvoice/cancel/{id}` (sadece 8 gün içinde + onay gerekir)
- Webhook: `POST /your-webhook` ← signed payload ile teslim/red bildirimi

**Mopro entegrasyon noktaları:**

- **Sipariş tamamlandığında (delivered):** `einvoice-submitter` worker tetiklenir.
  - Satıcı mükellef ise: Mopro adına satıcının `einvoice` modülü çağrılır (tedarikçi entegrasyonu — Phase 2). Ama bu Mopro'nun değil satıcının sorumluluğudur; Mopro yalnızca SATICIYA komisyon faturası keser.
  - Mopro → Satıcı komisyon faturası: `POST /einvoice/send` (tutar = komisyon brüt + KDV; mükellef satıcı VKN'sine).
- **Aylık fatura özeti:** Satıcıya ay sonunda toplu komisyon faturası (tek dokümanda tüm siparişler) — yine Foriba üzerinden.
- **e-Arşiv Phase 5'te aktive olur:** Mopro doğrudan tüketiciye satış yapmaya başladığında (own-seller yan iş kolu, kullanıcı önerisi).
- **KDV beyanı (aylık):** Mopro tahsil ettiği komisyon KDV'sini ay sonunda devlete (GİB) öder. Muhasebe yazılımı Mopro'nun komisyon gelirini + alınan KDV'yi otomatik aggreğe eder.

**Schema gereksinimleri (DATA_DICTIONARY.md § 11 — yeni):**
- `einvoice_schema.invoices` (id, order_id, seller_id, type='commission'|'sale', amount_minor, kdv_minor, total_minor, currency, foriba_invoice_id, foriba_uuid, status, raw_xml_b2_key, ettn, created_at, sent_at, delivered_at, cancelled_at)
- `einvoice_schema.invoice_history` (audit trail of state changes)

**Failure modes:**
- **Foriba API down:** worker DLQ'ya alır, on-call sayfa, GİB beyan tarihi yaklaştığında kritik (her ay 26'sı).
- **GİB rejection (XML invalid):** worker hatayı loglar, manuel düzeltme + replay; reviewer e-fatura admin paneli üzerinden.
- **Iptal isteği 8 günü geçti:** GİB iptal kabul etmez; muhasebede credit note (ters fatura) ile düzeltilir.

**Sandbox kayıt:**
- Foriba sandbox: bilgi@foriba.com (kurumsal başvuru, 1-2 hafta)
- GİB test ortamı: efaturatest.gib.gov.tr (KEP adresi gerekir; 2-3 hafta)

**Hukuki:**
- Mopro VKN almak zorunda (Şirketleşme tamamlanınca otomatik) — ilk fatura kesmeden önce mali müşavirle kontrol.
- Mopro'nun e-fatura mükellefliği: 5M TL+ ciro eşiği aşılınca otomatik; aşağı seviyede gönüllü mükellef olunabilir (Mopro lansmandan itibaren gönüllü mükellef olmalı çünkü marketplace operatörü).
- KEP (Kayıtlı Elektronik Posta) adresi gereklidir — PTT KEP'ten alınır (~700 TL/yıl).

---

## 9. Failure Domains

| Failure | Blast radius | Mitigation |
|---|---|---|
| One Go module panics | The whole binary it lives in restarts | Health checks, restart policy `unless-stopped` |
| postgres-ecom down | core-svc + jobs-svc broken; fin-svc independent | Restart, restore from B2 |
| postgres-ledger down | fin-svc broken; both crons pause; orders queue in outbox | Restart, restore from B2 |
| redis down | Cache cold + Streams unavailable; events queue in outbox | Restart, AOF replay |
| Caddy down | All ingress lost | Restart |
| Whole VDS down | Everything | Restore on new VDS from B2; RTO 4h |
| Disk full | Postgres halts | Panic mode at 92%: read-only switch (see DISASTER_RECOVERY.md) |
| PSP outage | New orders fail; outbound payouts queue; existing cashback unaffected | Multi-PSP failover via `PSP_PROVIDER` switch |
| Cashback monthly cron failure | Users don't receive monthly coin | Cron retry × 3, then DLQ + page on-call (SEV2) |
| Seller payout daily cron failure | Seller waits 24h+ extra; complaints | Cron retry × 3, then DLQ + page on-call (SEV2) |

---

## 10. Communication Path Reference

| From → To | Mechanism | Synchronous? |
|---|---|---|
| Mobile → Caddy | HTTPS (CloudFlare) | Sync |
| Caddy → core-svc | HTTP/JSON | Sync |
| Caddy → fin-svc | HTTP/JSON (admin + wallet/cashback/payout read) | Sync |
| Caddy → jobs-svc | HTTP/JSON | Sync |
| core-svc.module → core-svc.module | In-memory function call | Sync |
| core-svc → fin-svc | Redis Streams events | **Async only** |
| fin-svc → core-svc | Redis Streams events | **Async only** |
| core-svc / fin-svc → jobs-svc | HTTP or Redis Streams | Both allowed |
| Any service → Postgres | TCP via PgBouncer | Sync |
| outbox-publisher → Redis | XADD | Sync inside tx of publisher |
| Cashback monthly cron → ledger | DB tx + outbox | Sync within fin-svc |
| Seller payout daily cron → ledger + PSP | DB tx + outbox + outbound HTTPS | Sync within fin-svc |

---

## 11. Change Procedure

Any change to this topology (network membership, binary boundaries, DB cluster split, new module, new PSP, new market, change from the perpetual cashback model, change to the 3-business-day delay, or change to the %50 reference interest rate) requires:

1. ADR file in `/docs/adr/NNNN-<title>.md` describing decision and consequences.
2. Update of this `ARCHITECTURE.md`.
3. Update of `INFRASTRUCTURE.md` resource budgets if footprint changes.
4. Update of `LEDGER_GUIDE.md` if accounting moves change.
5. Human approval.

---

**End of ARCHITECTURE.md.** See DATA_DICTIONARY.md for schemas, LEDGER_GUIDE.md for financial code rules, INFRASTRUCTURE.md for resource limits.
