# LEDGER_GUIDE.md — Financial Code Rules v7

> **WARNING:** Code in this domain controls real seller money AND user cashback obligations totaling millions of TL of liability. A bug here is not a UX issue — it is a business-ending event. Treat every change with paranoia.

Reflects PRD v6.0 (perpetual cashback) + v7 detail packs (PSP & kargo API'ları, mobil 30+ ekran, anti-fraud ML, TR e-fatura/e-arşiv/GİB).

---

## 1. Mental Model

The ledger uses **double-entry accounting**, append-only, denominated in integer minor units (`amount_minor BIGINT`) of a configurable currency. Initial launch operates two currencies: `TRY` (real fiat held in PSP escrow / bank outbound) and `TRY_COIN` (Mopro Coin liability to users).

The schema supports multiple currencies; **each account has exactly ONE currency, and each transaction's entries MUST all share that currency**. Cross-currency moves are explicit FX transactions with dedicated FX accounts.

Every transaction touches at least two accounts: one debited (D), one credited (C). The sum of debits within a transaction MUST equal the sum of credits (per currency). Violations are blocked at the database level by a `DEFERRABLE INITIALLY DEFERRED` constraint trigger.

---

## 2. Chart of Accounts — v6 (perpetual cashback model)

| Account name pattern | Type | Owner | Purpose |
|---|---|---|---|
| `asset:bank:escrow:<CUR>` | asset | platform | Real fiat held in PSP escrow account |
| `asset:bank:outbound_pending:<CUR>` | asset | platform | Real fiat reserved for pending withdrawals |
| `liability:bank_outbound:<CUR>` | liability | platform | Counterparty: pending payouts to sellers/users |
| `liability:seller_payable:<CUR>` | liability | seller | Per-seller pending net payout (delivered + 3BD) |
| `liability:wallet:user_<id>:<COIN>` | liability | user | Per-user wallet balance in coin |
| `equity:cashback_distribution:<COIN>` | equity | platform | Counter-equity to wallet credit each month (perpetual; no upfront provision) |
| `equity:retained_commission:<CUR>` | equity | platform | Net commission retained as Mopro's working capital (NEVER repaid; perpetual asset) |
| `equity:retained_float_income:<CUR>` | equity | platform | Float yield (3BD delay yield) reclassified as company income |
| `equity:fx_gain_loss:<CUR>` | equity | platform | Realized FX P&L from coin/fiat conversions |
| `liability:kdv_payable:<CUR>` | liability | platform | KDV (VAT) collected from sellers, owed to state |

Account naming convention: `<type>:<owner_class>:<asset_class>[:<id>]:<currency>`. The currency suffix is **mandatory** for every account. NEVER seed an account without specifying its currency.

### 2.1 v6 Perpetual Model — No Upfront Cashback Obligation

In v6 (perpetual model) there is **NO finite cashback obligation pre-allocated at plan creation**. Because the plan never ends, there is no upper bound to the future liability — pre-provisioning would either be infinite or arbitrary. Instead:

- At plan creation (delivered+3BD): plan record is INSERTed in `cashback_schema.plans`. **No ledger move yet.** Mopro's commission cash already sits in `equity:retained_commission:TRY` (recorded at order capture).
- At each monthly cron tick (1st of month 02:00 UTC): for each active plan, ONE coin transaction is posted: `D equity:cashback_distribution:TRY_COIN ← → C liability:wallet:user_<id>:TRY_COIN` (TRY_COIN-only).
- The matching TRY-side recognition (Mopro's expense for the period) is recorded daily by Treasury into `equity:fx_gain_loss:TRY` with FX rate snapshot, since coin distribution is denominated in TRY_COIN but the economic reality is interest paid in TL.

Treasury's monthly reconcile validates: `Σ(cashback_distribution:TRY_COIN) over period` equals `Σ(plans[i].monthly_amount_minor for active plans)`. Any divergence beyond ±0.1% triggers a SEV2 alert.

**Key insight:** The commission principal in `equity:retained_commission:TRY` is NEVER drawn down by cashback. It accumulates forever as Mopro's permanent capital. Only `equity:cashback_distribution:TRY_COIN` decreases each month (the interest yield Mopro earns on the principal is what's distributed).

### 2.2 KDV Akışı — v7

Mopro her komisyondan KDV de tahsil eder (Mayıs 2026 itibarıyla KDV oranı %20). Akış:

**Order capture'da (PSP'den para escrow'a geldiğinde):**
```
D asset:bank:escrow:TRY            amount = total       (alıcının tüm ödediği)
C liability:seller_payable:TRY     amount = seller_net  (satıcıya gidecek)
C equity:retained_commission:TRY   amount = commission  (Mopro'nun komisyon geliri, KDV hariç)
C liability:kdv_payable:TRY        amount = kdv         (Mopro KDV'yi devlete iletecek)
```

Bu transaction tek-currency (TRY), trigger geçer. Toplam D = C garantilidir.

**Aylık KDV beyanı (her ay 26'sında):**
```
D liability:kdv_payable:TRY        amount = period_kdv_total
C asset:bank:escrow:TRY            amount = period_kdv_total
```
Bu hareket GİB'e yapılan banka transferiyle eşleşmelidir (treasury daily reconcile).

**Mopro'nun gider KDV'si (ofis, hosting, vs.) ay sonu beyanda mahsup edilir:**
```
D asset:bank:outbound_pending:TRY  amount = mopro_expense_total (faturalardan)
D equity:retained_commission:TRY   amount = -kdv_paid_to_us     (gider KDV'si negatif gelir)
C asset:bank:escrow:TRY            amount = mopro_expense_total
C liability:kdv_payable:TRY        amount = -kdv_paid_to_us     (kollektif gider KDV'si net'i azaltır)
```
NOT: Bu ikinci akış muhasebe yazılımı düzeyinde (Foriba) takip edilir; ledger sadece banka transferini görür.

**iade (cancel) durumunda:**
```
D liability:kdv_payable:TRY        amount = kdv_to_refund
D equity:retained_commission:TRY   amount = commission_to_refund
D liability:seller_payable:TRY     amount = seller_net_to_refund (eğer ödenmediyse)
C asset:bank:escrow:TRY            amount = total_refund
```

---

## 3. Schema (postgres-ledger / wallet_schema)

```sql
CREATE SCHEMA wallet_schema AUTHORIZATION wallet_user;

CREATE TABLE wallet_schema.accounts (
    id          BIGSERIAL PRIMARY KEY,
    type        TEXT NOT NULL,
    owner_type  TEXT,                   -- 'platform' | 'user' | 'seller' | 'fx'
    owner_id    BIGINT,
    -- currency is the account's single supported currency code.
    -- Examples: 'TRY' (fiat), 'TRY_COIN' (Mopro Coin), 'EUR_COIN' (future).
    -- An account never holds mixed currencies; cross-currency moves use FX accounts.
    currency    TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'active',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX accounts_owner_idx ON wallet_schema.accounts(owner_type, owner_id);
CREATE INDEX accounts_type_currency_idx ON wallet_schema.accounts(type, currency);

CREATE TABLE wallet_schema.transactions (
    id              BIGSERIAL PRIMARY KEY,
    type            TEXT NOT NULL,                  -- 'commission_accrual', 'cashback_plan_create', 'cashback_payment', 'seller_payout', 'withdraw', 'fx', 'reversal'
    reference       TEXT,
    fx_pair_id      TEXT,                           -- links the two halves of a cross-currency move
    idempotency_key TEXT NOT NULL UNIQUE,
    status          TEXT NOT NULL DEFAULT 'posted',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE wallet_schema.ledger_entries (
    id              BIGSERIAL PRIMARY KEY,
    transaction_id  BIGINT NOT NULL REFERENCES wallet_schema.transactions(id),
    account_id      BIGINT NOT NULL REFERENCES wallet_schema.accounts(id),
    direction       CHAR(1) NOT NULL CHECK (direction IN ('D','C')),
    amount_minor    BIGINT NOT NULL CHECK (amount_minor > 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ledger_entries_account_idx ON wallet_schema.ledger_entries(account_id);
CREATE INDEX ledger_entries_txn_idx     ON wallet_schema.ledger_entries(transaction_id);
CREATE INDEX ledger_entries_created_idx ON wallet_schema.ledger_entries(created_at);

-- Append-only enforcement
CREATE RULE no_update_ledger AS
    ON UPDATE TO wallet_schema.ledger_entries DO INSTEAD NOTHING;
CREATE RULE no_delete_ledger AS
    ON DELETE FROM wallet_schema.ledger_entries DO INSTEAD NOTHING;
CREATE RULE no_update_transactions AS
    ON UPDATE TO wallet_schema.transactions DO INSTEAD NOTHING;
CREATE RULE no_delete_transactions AS
    ON DELETE FROM wallet_schema.transactions DO INSTEAD NOTHING;

-- Materialized view for fast balance reads (refreshed hourly by balance-mv-refresh worker)
CREATE MATERIALIZED VIEW wallet_schema.balances AS
  SELECT a.id AS account_id,
         a.currency,
         a.owner_type,
         a.owner_id,
         COALESCE(SUM(CASE WHEN le.direction='C' THEN le.amount_minor ELSE -le.amount_minor END), 0)
           AS balance_minor
  FROM wallet_schema.accounts a
  LEFT JOIN wallet_schema.ledger_entries le ON le.account_id = a.id
  GROUP BY a.id;
CREATE UNIQUE INDEX balances_account_uq ON wallet_schema.balances(account_id);
```

---

## 4. Multi-Currency Aware D=C Trigger (CRITICAL)

```sql
CREATE OR REPLACE FUNCTION wallet_schema.enforce_double_entry()
RETURNS TRIGGER AS $$
DECLARE
    txn_currencies TEXT[];
    debit_total  BIGINT;
    credit_total BIGINT;
BEGIN
    -- (1) Multi-currency safety: all entries in this transaction must share currency
    SELECT array_agg(DISTINCT a.currency)
    INTO txn_currencies
    FROM wallet_schema.ledger_entries le
    JOIN wallet_schema.accounts a ON a.id = le.account_id
    WHERE le.transaction_id = NEW.transaction_id;

    IF array_length(txn_currencies, 1) > 1 THEN
        RAISE EXCEPTION
            'Mixed currencies in transaction %: %',
            NEW.transaction_id, txn_currencies
            USING ERRCODE = 'check_violation';
    END IF;

    -- (2) D=C check (single-currency at this point)
    SELECT
        COALESCE(SUM(amount_minor) FILTER (WHERE direction='D'), 0),
        COALESCE(SUM(amount_minor) FILTER (WHERE direction='C'), 0)
    INTO debit_total, credit_total
    FROM wallet_schema.ledger_entries
    WHERE transaction_id = NEW.transaction_id;

    IF debit_total != credit_total THEN
        RAISE EXCEPTION
            'Double-entry violation: txn=% debit=% credit=%',
            NEW.transaction_id, debit_total, credit_total
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER ledger_balance_check
AFTER INSERT ON wallet_schema.ledger_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION wallet_schema.enforce_double_entry();
```

### 4.1 How `DEFERRABLE INITIALLY DEFERRED` works

Within a transaction you can `INSERT` multiple `ledger_entries` rows that temporarily violate the invariant; the trigger evaluates **at COMMIT**. If invariant holds at commit, transaction commits. If not, the WHOLE transaction is rolled back.

**This means agent code MUST insert all D and C rows for a transaction inside a SINGLE SQL transaction.** Splitting across SQL transactions = guaranteed ROLLBACK at commit.

### 4.2 Cross-Currency (FX) Transactions

An FX move (e.g., user converts TRY_COIN to TRY for withdrawal, AFTER coin license activation) is **TWO transactions linked by `fx_pair_id`**:

```sql
-- Transaction A: TRY_COIN side
INSERT INTO wallet_schema.transactions (type, fx_pair_id, idempotency_key)
  VALUES ('fx_outbound', 'fx-uuid-1', 'fx-uuid-1:try_coin');
-- D wallet:user_42:TRY_COIN, C asset:fx_pool:TRY_COIN

-- Transaction B: TRY side
INSERT INTO wallet_schema.transactions (type, fx_pair_id, idempotency_key)
  VALUES ('fx_inbound', 'fx-uuid-1', 'fx-uuid-1:try');
-- D asset:fx_pool:TRY, C asset:bank:outbound_pending:TRY (later → user's bank)
```

The trigger validates each transaction independently (single-currency). The `fx_pair_id` ties them together for audit and reconciliation.

---

## 5. Outbox Table (Same DB as Ledger)

```sql
CREATE TABLE wallet_schema.outbox (
    id              BIGSERIAL PRIMARY KEY,
    aggregate       TEXT NOT NULL,
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    trace_id        TEXT,
    span_id         TEXT,
    market          TEXT NOT NULL,
    currency        TEXT NOT NULL,
    published_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX outbox_unpublished_idx
    ON wallet_schema.outbox(created_at) WHERE published_at IS NULL;
```

A separate worker (`outbox-publisher`) drains this table to Redis Streams. Worker uses `SELECT ... FOR UPDATE SKIP LOCKED` for safe concurrent operation.

---

## 6. Mandatory Write Pattern

EVERY ledger-touching code path MUST follow this template:

```go
func (s *walletService) Apply(ctx context.Context, in Input) error {
    // 1. Validate
    if in.IdempotencyKey == "" { return ErrIdempotencyKeyRequired }
    if in.AmountMinor <= 0    { return ErrInvalidAmount }
    if in.Currency == ""      { return ErrCurrencyRequired }
    // All entries in this transaction MUST share in.Currency.
    // The DB trigger enforces this; service-side check is defensive.

    // 2. Single SQL tx with SERIALIZABLE
    return s.repo.WithTx(ctx, sql.LevelSerializable, func(tx pgx.Tx) error {
        // 2a. Insert transaction (UNIQUE on idempotency_key handles double-apply)
        txnID, err := s.repo.InsertTransaction(ctx, tx, ledger.Transaction{
            Type:           in.Type,
            Reference:      in.Reference,
            IdempotencyKey: in.IdempotencyKey,
        })
        if errors.Is(err, ledger.ErrDuplicateIdempotency) {
            return nil // idempotent no-op
        }
        if err != nil { return err }

        // 2b. Insert all D and C entries (BOTH MUST BE PRESENT, single currency)
        for _, e := range in.Entries {
            if err := s.repo.InsertEntry(ctx, tx, ledger.Entry{
                TransactionID: txnID,
                AccountID:     e.AccountID,    // an account row whose .currency == in.Currency
                Direction:     e.Direction,
                AmountMinor:   e.AmountMinor,
            }); err != nil { return err }
        }

        // 2c. Insert outbox row in SAME tx
        return s.outbox.Insert(ctx, tx, outbox.Row{
            Aggregate:      in.Aggregate,
            EventType:      in.EventType,
            Payload:        marshal(in),
            IdempotencyKey: in.IdempotencyKey,
            TraceID:        traceIDFromCtx(ctx),
            SpanID:         spanIDFromCtx(ctx),
            Market:         in.Market,
            Currency:       in.Currency,
        })
        // Trigger validates D=C + single-currency at COMMIT. If invalid: full rollback.
    })
}
```

### 6.1 FORBIDDEN patterns

```go
// ❌ Single-direction write (will rollback at commit)
db.Exec("INSERT INTO ledger_entries ...")  // only D, no C

// ❌ Mixed currency in one transaction (will rollback)
//   tx { INSERT D wallet:TRY, INSERT C wallet:TRY_COIN } → ROLLBACK

// ❌ Update existing entry (rule blocks)
db.Exec("UPDATE ledger_entries SET amount_minor = ?")

// ❌ Float for money (always BIGINT)
type BadEntry struct { Amount float64 }

// ❌ Skipping idempotency
if err := repo.Insert(...); err != nil { /* ignore */ }

// ❌ Direct Redis publish without outbox
redis.XAdd(ctx, &redis.XAddArgs{Stream: "fin.wallet.credited.v1", ...})

// ❌ Splitting D and C across separate SQL transactions
tx1 := beginTx(); writeD(tx1); tx1.Commit()
tx2 := beginTx(); writeC(tx2); tx2.Commit()  // first commit rolls back

// ❌ Hardcoded currency
ledger.Entry{Direction: "D", AmountMinor: 100, Currency: "TRY_COIN"}  // currency on account, not entry

// ❌ Mutating an existing cashback plan
db.Exec("UPDATE cashback_schema.plans SET monthly_amount_minor = ?")  // trigger blocks

// ❌ Mutating an existing seller payout
db.Exec("UPDATE commission_schema.seller_payouts SET amount_minor = ?")  // trigger blocks

// ❌ Hardcoding the 3-day delay as calendar days
unlockAt := delivered.AddDate(0,0,3)  // wrong! must use timex.AddBusinessDays

// ❌ Hardcoding fixed-term cashback in v6 (perpetual model)
plan.TotalMonths = 24                 // wrong in v6! No total_months column.
plan.TotalAmountMinor = 200_00        // wrong in v6! No total_amount column.
```

---

## 7. Cashback Engine — Plan Generation and Monthly Payment (v6 PERPETUAL)

### 7.1 Plan Generation (on `ecom.order.delivered.v1` event)

When an order is delivered, the cashback engine generates a perpetual plan. Plan creation itself happens immediately (so the buyer can see "starts in N days" in the app). The first instalment is paid by the monthly cron whose `start_date <= today`, where `start_date = delivered_at + 3 business days`. **This operation is deterministic and idempotent.**

```go
// /internal/cashback/engine.go
const ReferenceInterestRateBpsConst = 5000  // v6: %50.00 — the snapshotted reference per plan.

func (s *engineService) CreatePlanForOrder(ctx context.Context, ev OrderDeliveredEvent) error {
    // 1. Idempotency: if a plan exists for this order, no-op
    existing, _ := s.repo.FindPlanByOrderID(ctx, ev.OrderID)
    if existing != nil { return nil }

    // 2. Sum commission across items from snapshots (single source of truth = order_items)
    commissionMinor := int64(0)
    for _, it := range ev.Items {
        commissionMinor += it.CommissionAmountMinor
    }
    if commissionMinor == 0 { return nil } // no cashback eligible

    // 3. Compute monthly coin amount (v6 PERPETUAL formula):
    //    monthly = (commission * reference_rate) / 12
    //    Done in integer minor-unit math via basis points.
    yearlyYieldMinor := commissionMinor * int64(ReferenceInterestRateBpsConst) / 10000
    monthlyMinor := yearlyYieldMinor / 12
    if monthlyMinor == 0 { return nil } // amount too small to pay (rare; sub-kuruş)

    // 4. Compute first instalment unlock = delivered_at + 3 business days
    cal, err := s.calendars.For(ctx, ev.Market)  // pkg/timex
    if err != nil { return err }
    unlockAt := s.timex.AddBusinessDays(ev.DeliveredAt, 3, cal)

    return s.repo.WithTx(ctx, sql.LevelSerializable, func(tx pgx.Tx) error {
        // 5. Insert plan (frozen by trigger after this insert; only `status` mutable)
        coinCurrency := coinCurrencyFor(ev.Market)  // 'TRY_COIN' for TR
        planID, err := s.repo.InsertPlan(ctx, tx, cashback.Plan{
            OrderID:                  ev.OrderID,
            UserID:                   ev.UserID,
            MonthlyAmountMinor:       monthlyMinor,
            Currency:                 coinCurrency,
            ReferenceInterestRateBps: ReferenceInterestRateBpsConst,
            StartDate:                unlockAt,
            // No EndDate — perpetual.
            Status:                   "active",
            DeliveredAt:              ev.DeliveredAt,
            Market:                   ev.Market,
            CommissionSnapshot:       marshalItems(ev.Items),
            IdempotencyKey:           fmt.Sprintf("cashback:plan:order_%d", ev.OrderID),
        })
        if err != nil { return err }

        // 6. NO ledger move at plan creation (v6 perpetual model).
        //    Cashback distribution is recognized period-by-period in the monthly cron.
        //    Mopro's commission cash already sits in equity:retained_commission:TRY (from order capture).

        // 7. Outbox: notify the rest of the system the plan exists.
        return s.outbox.Insert(ctx, tx, outbox.Row{
            Aggregate:      "cashback",
            EventType:      "fin.cashback.plan.created.v1",
            Payload:        marshalPlanCreatedEvent(planID, ev),
            IdempotencyKey: fmt.Sprintf("cashback:plan:order_%d:created", ev.OrderID),
            Market:         ev.Market,
            Currency:       coinCurrency,
        })
    })
}
```

### 7.2 Monthly Payment Cron

Runs on the 1st of each month at 02:00 UTC. **Idempotent via UNIQUE `(plan_id, period_yyyymm)`**. The cron creates a new payment row for each active plan whose `start_date <= today`, then immediately posts the ledger move and marks the payment paid.

```go
// /internal/cashback/cron.go
func (s *engineService) RunMonthlyPayments(ctx context.Context, runDate time.Time) error {
    period := yyyymm(runDate)  // e.g., 202607
    plans, err := s.repo.FindActivePlansDue(ctx, runDate, 1000)  // batch of plans whose start_date <= runDate
    if err != nil { return err }

    for _, plan := range plans {
        if err := s.payOnce(ctx, plan, period); err != nil {
            s.logger.Error("cashback_payment_failed", "plan_id", plan.ID, "period", period, "err", err)
            // Failure of ONE plan does not abort the batch; record attempt for visibility.
            s.repo.RecordAttempt(ctx, plan.ID, period, err.Error())
            continue
        }
    }
    return nil
}

func (s *engineService) payOnce(ctx context.Context, plan cashback.Plan, period int) error {
    return s.repo.WithTx(ctx, sql.LevelSerializable, func(tx pgx.Tx) error {
        // 1. INSERT payment row for this period (UNIQUE on plan_id+period_yyyymm makes this idempotent)
        idempKey := fmt.Sprintf("cashback:plan_%d:period_%d", plan.ID, period)
        scheduledDate := firstOfMonth(period)
        paymentID, err := s.repo.InsertPayment(ctx, tx, cashback.Payment{
            PlanID:         plan.ID,
            PeriodYYYYMM:   period,
            ScheduledDate:  scheduledDate,
            AmountMinor:    plan.MonthlyAmountMinor,
            Status:         "scheduled",
            IdempotencyKey: idempKey,
        })
        if errors.Is(err, repo.ErrDuplicateUnique) { return nil } // already paid this period
        if err != nil { return err }

        // 2. Ledger move (v6: D distribution / C user wallet, both TRY_COIN)
        distAccountID, _ := s.wallet.FindAccount(ctx, "equity:cashback_distribution", plan.Currency)
        userWalletID,  _ := s.wallet.OpenOrFindUserWallet(ctx, plan.UserID, plan.Currency)

        txnID, err := s.wallet.PostInTx(ctx, tx, ledger.PostInput{
            Type:           "cashback_payment",
            Reference:      fmt.Sprintf("plan_%d:period_%d", plan.ID, period),
            IdempotencyKey: idempKey,
            Market:         plan.Market,
            Currency:       plan.Currency,
            Entries: []ledger.Entry{
                {AccountID: distAccountID, Direction: "D", AmountMinor: plan.MonthlyAmountMinor},
                {AccountID: userWalletID,  Direction: "C", AmountMinor: plan.MonthlyAmountMinor},
            },
        })
        if err != nil { return err }

        // 3. Mark payment 'paid' in same tx
        if err := s.repo.MarkPaid(ctx, tx, paymentID, txnID); err != nil { return err }

        // 4. Outbox notification
        return s.outbox.Insert(ctx, tx, outbox.Row{
            Aggregate:      "cashback",
            EventType:      "fin.cashback.payment.posted.v1",
            Payload:        marshalPaymentEvent(plan.ID, period, plan.MonthlyAmountMinor, txnID),
            IdempotencyKey: idempKey,
            Market:         plan.Market,
            Currency:       plan.Currency,
        })
    })
}
```

### 7.3 Cashback FORBIDDEN Patterns (v6)

```go
// ❌ Modify an existing plan (DB trigger blocks)
db.Exec("UPDATE cashback_schema.plans SET monthly_amount_minor = ?")

// ❌ Pay a scheduled payment without idempotency-key
ledger.Post(...)  // missing IdempotencyKey field

// ❌ Pay across currencies in one ledger transaction
//   D distribution:TRY_COIN, C user_wallet:EUR_COIN → trigger rollback

// ❌ Skip the FindPlanByOrderID idempotency check at plan creation
// (if cashback engine receives the same delivery event twice → would create duplicate plan)

// ❌ Pre-allocate a finite cashback obligation in v6 (perpetual model)
db.Exec("INSERT INTO cashback_schema.plans (... total_amount_minor, total_months ...)")  // wrong! v6 has neither

// ❌ Use calendar days for the 3-day delay (must be business days)
unlockAt := deliveredAt.AddDate(0, 0, 3)  // wrong! use timex.AddBusinessDays

// ❌ Recompute commission from current ref_schema.commission_rules at plan time
// (must read snapshot from order_items.commission_pct_bps)

// ❌ Use a different reference interest rate than ReferenceInterestRateBpsConst at plan creation
plan.ReferenceInterestRateBps = 4500  // wrong! v6 uses 5000 (%50). Adjust the constant via ADR + new constitution version.
```

### 7.4 Cashback Cancellation (Refund or Order Cancel)

When an order is cancelled or fully refunded:

```go
func (s *engineService) CancelPlan(ctx context.Context, planID int64, reason string) error {
    plan, _ := s.repo.GetPlan(ctx, planID)
    if plan.Status != "active" { return nil }

    return s.repo.WithTx(ctx, sql.LevelSerializable, func(tx pgx.Tx) error {
        // v6 PERPETUAL: there is no upfront obligation/provision — only past paid amounts to reverse.
        // Future months stop simply by setting status='cancelled' (cron skips non-active plans).

        // 1. Sum coin already paid this plan
        paidMinor, _ := s.repo.SumPaidAmount(ctx, planID)

        distAccountID, _ := s.wallet.FindAccount(ctx, "equity:cashback_distribution", plan.Currency)
        userWalletID,  _ := s.wallet.OpenOrFindUserWallet(ctx, plan.UserID, plan.Currency)

        // 2. Reverse already-paid coin from user wallet back to distribution equity
        if paidMinor > 0 {
            _, err := s.wallet.PostInTx(ctx, tx, ledger.PostInput{
                Type:           "cashback_reversal",
                Reference:      fmt.Sprintf("plan_%d:cancel", planID),
                IdempotencyKey: fmt.Sprintf("cashback:plan_%d:cancel", planID),
                Market:         plan.Market,
                Currency:       plan.Currency,
                Entries: []ledger.Entry{
                    {AccountID: userWalletID,    Direction: "D", AmountMinor: paidMinor},
                    {AccountID: distAccountID,   Direction: "C", AmountMinor: paidMinor},
                },
            })
            if err != nil { return err }
        }

        // 3. Mark plan cancelled (status field is mutable; rest is not)
        //    Future cron runs SKIP this plan because they SELECT WHERE status='active'.
        //    Mopro's commission principal in equity:retained_commission:TRY is implicitly
        //    "released" by virtue of no longer paying interest on it; bookkeeping needs no extra entry.
        return s.repo.UpdatePlanStatus(ctx, tx, planID, "cancelled")
    })
}
```

---

## 8. Seller Payout Engine — v6 (unchanged from v5)

### 8.1 Payout Schedule (on `ecom.order.delivered.v1` event)

The `sellerpayout` module subscribes to the SAME `ecom.order.delivered.v1` event as the cashback engine. It computes the seller's net amount from the snapshotted commission/KDV in `order_items` and schedules the payout for `delivered_at + 3 business days`.

```go
// /internal/sellerpayout/engine.go
const PayoutDelayBusinessDays = 3  // v6 LOCKED (unchanged from v5).

func (s *payoutService) SchedulePayoutForOrder(ctx context.Context, ev OrderDeliveredEvent) error {
    // 1. Idempotency check: per (order_id, seller_id) tuple
    //    An order may have items from multiple sellers → one payout per seller.
    sellerNets := aggregateBySeller(ev.Items)  // map[seller_id]int64
    cal, err := s.calendars.For(ctx, ev.Market)
    if err != nil { return err }
    unlockAt := s.timex.AddBusinessDays(ev.DeliveredAt, PayoutDelayBusinessDays, cal)

    return s.repo.WithTx(ctx, sql.LevelSerializable, func(tx pgx.Tx) error {
        for sellerID, netMinor := range sellerNets {
            if netMinor <= 0 { continue }

            idempKey := fmt.Sprintf("payout:order_%d:seller_%d", ev.OrderID, sellerID)
            existing, _ := s.repo.FindPayoutByKey(ctx, idempKey)
            if existing != nil { continue }

            _, err := s.repo.InsertPayout(ctx, tx, sellerpayout.Payout{
                OrderID:        ev.OrderID,
                SellerID:       sellerID,
                AmountMinor:    netMinor,
                Currency:       fiatCurrencyFor(ev.Market),  // 'TRY' for TR
                DeliveredAt:    ev.DeliveredAt,
                UnlockAt:       unlockAt,
                Status:         "scheduled",
                Market:         ev.Market,
                IdempotencyKey: idempKey,
            })
            if err != nil { return err }
        }
        return nil
    })
}
```

Note: At schedule time, NO ledger move happens. The PSP escrow already holds the funds (credited at order capture). The ledger move happens at payout cron time, when funds actually leave Mopro's books toward the seller.

### 8.2 Daily Payout Cron

Runs every day at 02:30 UTC. **Idempotent.**

```go
// /internal/sellerpayout/cron.go
func (s *payoutService) RunDailyPayouts(ctx context.Context, runDate time.Time) error {
    payouts, err := s.repo.FindDuePayouts(ctx, runDate, 1000)
    if err != nil { return err }

    for _, p := range payouts {
        if err := s.payOnce(ctx, p); err != nil {
            s.logger.Error("seller_payout_failed", "payout_id", p.ID, "err", err)
            s.repo.RecordAttempt(ctx, p.ID, err.Error())
            continue
        }
    }
    return nil
}

func (s *payoutService) payOnce(ctx context.Context, p sellerpayout.Payout) error {
    // 1. Initiate PSP transfer (outside tx; PSP idempotency-key = p.IdempotencyKey)
    transferRef, err := s.psp.InitiateTransfer(ctx, psp.TransferRequest{
        SellerID:       p.SellerID,
        AmountMinor:    p.AmountMinor,
        Currency:       p.Currency,
        IdempotencyKey: p.IdempotencyKey,
    })
    if err != nil { return err }

    // 2. Ledger move + payout row update in single tx
    return s.repo.WithTx(ctx, sql.LevelSerializable, func(tx pgx.Tx) error {
        sellerPayableID, _ := s.wallet.FindOrOpenSellerPayable(ctx, p.SellerID, p.Currency)
        bankEscrowID, _    := s.wallet.FindAccount(ctx, "asset:bank:escrow", p.Currency)

        txnID, err := s.wallet.PostInTx(ctx, tx, ledger.PostInput{
            Type:           "seller_payout",
            Reference:      fmt.Sprintf("payout_%d", p.ID),
            IdempotencyKey: p.IdempotencyKey,
            Market:         p.Market,
            Currency:       p.Currency,
            Entries: []ledger.Entry{
                {AccountID: sellerPayableID, Direction: "D", AmountMinor: p.AmountMinor},
                {AccountID: bankEscrowID,    Direction: "C", AmountMinor: p.AmountMinor},
            },
        })
        if err != nil { return err }

        // 3. Mark payout as processing (becomes 'paid' on PSP webhook confirmation)
        if err := s.repo.MarkProcessing(ctx, tx, p.ID, txnID, transferRef); err != nil { return err }

        return s.outbox.Insert(ctx, tx, outbox.Row{
            Aggregate:      "sellerpayout",
            EventType:      "fin.seller.payout.posted.v1",
            Payload:        marshalPayoutEvent(p, txnID, transferRef),
            IdempotencyKey: p.IdempotencyKey,
            Market:         p.Market,
            Currency:       p.Currency,
        })
    })
}
```

### 8.3 Seller Transparency Endpoint

```go
// /internal/seller/handler.go (in core-svc)
// GET /api/v1/seller/orders/:order_id/breakdown
func (h *sellerHandler) GetOrderBreakdown(c *gin.Context) {
    orderID := mustParseInt64(c.Param("order_id"))

    // Read directly from order_items (snapshots)
    items, err := h.orderSvc.GetItemsBySeller(c, orderID, h.currentSellerID(c))
    if err != nil { c.AbortWithStatusJSON(404, gin.H{"error": err.Error()}); return }

    var grossSum, commissionSum, kdvSum, netSum int64
    var rows []breakdownRow
    for _, it := range items {
        gross := it.UnitPriceMinor * int64(it.Qty)
        rows = append(rows, breakdownRow{
            ItemID:           it.ID,
            VariantID:        it.VariantID,
            Qty:              it.Qty,
            GrossMinor:       gross,
            CommissionPctBps: it.CommissionPctBps,
            CommissionMinor:  it.CommissionAmountMinor,
            KdvPctBps:        it.KdvPctBps,
            KdvMinor:         it.KdvAmountMinor,
            ServiceFeeMinor:  0,                         // MOPRO HAS NONE
            NetMinor:         it.SellerNetMinor,
        })
        grossSum += gross
        commissionSum += it.CommissionAmountMinor
        kdvSum += it.KdvAmountMinor
        netSum += it.SellerNetMinor
    }

    c.JSON(200, gin.H{
        "currency":          items[0].UnitPriceCurrency,
        "rows":              rows,
        "gross_total":       grossSum,
        "commission_total":  commissionSum,
        "kdv_total":         kdvSum,
        "service_fee_total": 0,
        "net_total":         netSum,
        "trendyol_compare":  computeTrendyolCompareRow(grossSum, commissionSum, kdvSum),
        "hepsiburada_compare": computeHepsiburadaCompareRow(grossSum, commissionSum, kdvSum),
    })
}
```

The seller panel renders the comparison table from this endpoint's response. The numbers are deterministic and verifiable by the seller against their order detail page.

---

## 9. Continuous Reconciliation (Three Layers, Multi-Currency Aware)

### 9.1 Transaction-level (every commit)

The trigger above. Always on. DO NOT disable.

### 9.2 Hourly per-currency reconcile

`/opt/mopro/scripts/ledger-reconcile.sh`, cron `5 * * * *`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Per-currency reconcile: every currency MUST balance independently.
DIFFS=$(docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -tAc \
  "SELECT a.currency || '|' ||
          COALESCE(SUM(CASE WHEN le.direction='D' THEN le.amount_minor ELSE -le.amount_minor END), 0)
   FROM wallet_schema.ledger_entries le
   JOIN wallet_schema.accounts a ON a.id = le.account_id
   GROUP BY a.currency
   HAVING COALESCE(SUM(CASE WHEN le.direction='D' THEN le.amount_minor ELSE -le.amount_minor END), 0) != 0")

if [ -n "$DIFFS" ]; then
    while IFS='|' read -r CUR DELTA; do
        docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
          "INSERT INTO wallet_schema.ledger_alerts(severity, message, detected_at)
           VALUES ('CRITICAL', 'Currency '||quote_literal('$CUR')||' delta='||'$DELTA', now())"

        curl -X POST "$PAGERDUTY_API" -H "Content-Type: application/json" \
          -d "{\"event_action\":\"trigger\",\"payload\":{\"summary\":\"LEDGER VIOLATION currency=$CUR delta=$DELTA\",\"severity\":\"critical\"}}"
    done <<< "$DIFFS"

    docker exec fin-svc /app/app set-read-only --reason "ledger-invariant"
fi

curl -sf "https://hc-ping.com/$HEALTHCHECK_LEDGER_RECONCILE_UUID"
```

When the hourly reconcile sees a delta ≠ 0 for ANY currency, fin-svc is forced into read-only and on-call is paged.

### 9.3 Daily audit

A daily job exports per-account balances + treasury bank movements + cashback plan summaries + seller payout summaries to `/opt/mopro/audit/<date>.csv`. The accountant compares against bank statements.

### 9.4 Weekly cashback sanity check

A weekly cron verifies:
```sql
-- Sum of all 'paid' cashback payments == sum of all D obligation / C user_wallet entries
SELECT
  (SELECT SUM(amount_minor) FROM cashback_schema.payments WHERE status='paid') AS payments_total,
  (SELECT SUM(le.amount_minor)
   FROM wallet_schema.ledger_entries le
   JOIN wallet_schema.transactions t ON t.id = le.transaction_id
   WHERE t.type = 'cashback_payment' AND le.direction = 'D'
  ) AS ledger_total;
-- These two values MUST be equal.

-- Seller payout sanity:
SELECT
  (SELECT SUM(amount_minor) FROM commission_schema.seller_payouts WHERE status='paid') AS payouts_total,
  (SELECT SUM(le.amount_minor)
   FROM wallet_schema.ledger_entries le
   JOIN wallet_schema.transactions t ON t.id = le.transaction_id
   WHERE t.type = 'seller_payout' AND le.direction = 'D'
  ) AS ledger_total;
-- These two values MUST be equal.
```

If not equal: SEV1 alert.

---

## 10. Property-Based Tests Are Mandatory

Every change to `wallet`, `commission`, `treasury`, `cashback`, or `sellerpayout` MUST include or extend property-based tests using `github.com/leanovate/gopter`.

The single property to never break:

> **For any random sequence of valid operations, after applying them all, `Sum(D) - Sum(C) = 0` per currency.**

The cashback-specific property (v6 PERPETUAL):

> **For any plan with `monthly_amount_minor=M`, after N monthly cron runs (N arbitrary), the user wallet has been credited exactly N × M units of coin. There is no off-by-one because each period inserts exactly one payment row (UNIQUE on `(plan_id, period_yyyymm)`).**

> **For any plan with `commission_minor=C` and `reference_interest_rate_bps=R`, the computed `monthly_amount_minor = (C × R / 10000) / 12` matches the formula deterministically (verified by re-running CreatePlanForOrder with the same inputs).**

The seller payout property:

> **For any order with delivered_at=D, the corresponding seller_payout.unlock_at = AddBusinessDays(D, 3, calendar). If D falls on a Friday with no holidays, unlock_at = the next Wednesday.**

The freezing property:

> **For any plan or seller_payout, attempting to UPDATE its core fields raises an exception (`plans_immutable_trg` / `payout_immutable_trg`).**

See `PROMPTS.md` § "Property tests" for skeletons.

---

## 11. Common Failure Modes

| Symptom | Likely cause | Action |
|---|---|---|
| `Double-entry violation` exception | Forgot a C for a D, or amounts mismatch | Fix the code; add a property test reproducing the case |
| `Mixed currencies in transaction` exception | Tried to D in one currency, C in another | Split into two FX transactions with `fx_pair_id` |
| Hourly reconcile delta ≠ 0 for a currency | Outbox replay applied wrong, schema bypass via raw SQL | Page on-call; fin-svc to read-only; investigate |
| Outbox unpublished count growing | Worker crashed or Redis Streams down | `mopro outbox replay --since "1 hour ago"` |
| `ErrDuplicateIdempotency` | Same operation retried | Treat as success; do nothing |
| Cashback payment failed (status='failed') | Wallet account didn't exist OR ledger trigger threw | Investigate via `mopro cashback inspect <plan_id>`; manual replay if safe |
| Seller payout failed | PSP timeout or transient API error | Cron retries × 3; on persistent failure, DLQ + on-call SEV2 |
| Cashback plan immutability violation | Code tried to UPDATE plans table | Use reversal/new plan pattern instead |
| Seller payout immutability violation | Code tried to UPDATE seller_payouts core fields | Use reversal pattern instead |
| `unlock_at` is wrong (e.g., +3 calendar days vs 3 BD) | Used `time.AddDate(0,0,3)` instead of `timex.AddBusinessDays` | Replace with the helper; backfill affected rows via reversal+reissue |

---

## 12. Wallet Read API Rules

- Reading a wallet balance MUST query the materialized view `wallet_schema.balances` OR compute from `ledger_entries` on the fly.
- **Withdraw flow**: query balance with `SELECT ... FOR UPDATE` on the seller wallet account row inside the SAME transaction that creates the withdraw `transactions` record. This serializes concurrent withdraws.
- Cache balances in Redis with TTL ≤ 10 seconds for read endpoints. NEVER cache for the withdrawal critical path.
- **Cashback read (v6 PERPETUAL)**: list user's plans via `cashback_schema.plans`; for each plan show `monthly_amount_minor`, `start_date`, `next_payment_date`, lifetime `total_paid_minor` (sum from `payments` where status='paid'). NO total or end date — the plan is perpetual.
- **Seller payout read**: list seller's pending and paid payouts via `commission_schema.seller_payouts`; show `unlock_at` and PSP transfer reference.

---

## 13. mopro CLI Commands

```bash
# Outbox
mopro outbox list [--aggregate <name>] [--unpublished]
mopro outbox replay <event_id>
mopro outbox replay --since "2 hours ago" --dry-run

# Saga
mopro saga inspect <order_id>
mopro saga timeline <order_id>

# Ledger
mopro ledger reconcile [--currency TRY|TRY_COIN|...] --dry-run
mopro ledger reconcile [--currency TRY|TRY_COIN|...] --confirm
mopro ledger lock-account <id> --reason "<text>"
mopro ledger unlock-account <id>

# Cashback
mopro cashback inspect <plan_id>          # show plan + paid + scheduled
mopro cashback list-due --month YYYY-MM    # what would the cron do this month
mopro cashback replay-payment <payment_id> # idempotent re-pay
mopro cashback cancel-plan <plan_id> --reason "<text>"

# Seller Payouts (NEW v5)
mopro payout inspect <payout_id>          # show payout + ledger + PSP transfer
mopro payout list-due --date YYYY-MM-DD    # what would today's cron do
mopro payout replay <payout_id>           # idempotent retry
mopro payout cancel <payout_id> --reason "<text>"

# Business Calendar (TR holidays for AddBusinessDays)
mopro calendar show TR --year 2026
mopro calendar add TR --date 2026-12-31 --reason "Yarım gün"
```

The CLI is the ONLY supported way for operator interventions. Direct SQL on production ledger is prohibited.

---

**End of LEDGER_GUIDE.md.** See `PROMPTS.md` for code templates and verification flows.
