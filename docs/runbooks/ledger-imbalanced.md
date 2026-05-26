# Runbook: LedgerImbalanced

## Severity
critical (panic routing — also fires to #mopro-panic Slack channel)

## What this means
The weekly ledger reconciliation job (`ledger-reconcile-weekly`) reported a failure: `mopro_job_last_run_status{job="ledger-reconcile"} == 0`. This means either the reconcile cron itself failed to run, or it ran and detected an accounting imbalance in `postgres-ledger`. This is the highest-severity financial alert — it signals potential data integrity loss in the double-entry ledger.

## Common causes
- A code bug introduced a ledger write that bypassed the double-entry trigger (sum of debits ≠ sum of credits)
- A manually applied DB migration created orphaned rows without proper debit/credit pairs
- The reconcile job itself failed due to a DB connection error, timeout, or paniced before completing
- A mixed-currency transaction was partially written before the currency constraint fired, leaving a partial entry
- Clock skew between services caused an event to be processed out of order, writing entries against a transaction that had not yet committed

## Investigation steps
1. **Check job logs immediately**:
   ```bash
   docker compose -f deploy/docker-compose.prod.yml logs --tail=500 fin-svc | grep -E "reconcile|imbalance|IMBALANCED"
   ```
2. **Run reconcile manually in verbose mode**:
   ```bash
   docker exec fin-svc /fin-svc --run-once --cron=ledger-reconcile-weekly 2>&1
   ```
   (On the VDS; requires exec access to the running container)
3. **Query ledger directly for imbalanced transactions**:
   ```sql
   SELECT transaction_id,
          SUM(CASE WHEN direction='D' THEN amount_minor ELSE 0 END) AS total_debit,
          SUM(CASE WHEN direction='C' THEN amount_minor ELSE 0 END) AS total_credit,
          SUM(CASE WHEN direction='D' THEN amount_minor ELSE -amount_minor END) AS net
   FROM ledger_schema.ledger_entries
   GROUP BY transaction_id
   HAVING SUM(CASE WHEN direction='D' THEN amount_minor ELSE -amount_minor END) != 0
   ORDER BY transaction_id DESC
   LIMIT 50;
   ```
4. **Identify the transaction**: For each imbalanced `transaction_id`, check `ledger_schema.transactions` for context (`idempotency_key`, `description`, `created_at`)
5. **Correlate with deploy timeline**: `git log --oneline -10` — did a deploy happen in the hours before the imbalance was written?
6. **Check if reconcile job failed (vs detected imbalance)**: Distinguish between `level=ERROR cron=ledger-reconcile error="..."` (job failed) vs `level=ERROR cron=ledger-reconcile message="imbalance detected"` (data integrity issue)

## Mitigation
**STOP. Do not attempt automatic fixes. This is a financial data integrity issue.**

- **If the reconcile job failed to run** (connection error, panic): fix the underlying issue (DB connectivity, service restart) and re-run: `fin-svc --run-once --cron=ledger-reconcile-weekly`
- **If imbalance detected**:
  1. Do NOT attempt to "fix" ledger rows. The `no_update_ledger` rule prevents updates anyway.
  2. Identify the imbalanced transaction IDs from step 3 above.
  3. Determine if the imbalance represents real money movement or a phantom entry.
  4. Insert a **reversal transaction** (via the appropriate service module — cashback, payout, or commission) to correct the accounting. See `LEDGER_GUIDE.md §Reversal Pattern`.
  5. Re-run reconcile to confirm balance is restored.
- **Halt new financial operations** if the imbalance is growing: temporarily set `FIN_SVC_HALT=true` in `.env` and restart fin-svc (this feature must exist; if not, coordinate manual hold with Finance)

## Escalation
- Slack: #mopro-panic (this is a panic-routing alert)
- PagerDuty escalation policy: Platform → On-Call Engineer
- **Mandatory**: ping Finance team lead immediately — financial data integrity is their responsibility
- **Mandatory**: if imbalance involves user wallet balances, also ping legal/compliance

## Post-incident
- Record exact imbalanced transaction IDs, amounts, and root cause in incident doc
- Review the code path that wrote the imbalance; add a missing `CHECK` constraint or trigger if applicable
- Add a property-based test covering the scenario that caused the imbalance
- Run `go test -tags=integration -run Property ./internal/wallet/... ./internal/cashback/... ./internal/sellerpayout/...` to confirm invariants hold after fix
- Consider changing reconcile frequency from weekly to daily if this is a recurring risk
