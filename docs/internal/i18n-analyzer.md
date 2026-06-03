# i18n dead-key analyzer — discovery + design (TOOLING_AUDIT T-001)

Discovery doc for the prefix-aware i18n usage analyzer. The build (the analyzer,
baseline, CI wire) follows in later commits. **The dead-key *sweep* — removing
the unused keys — is a separate follow-up PR; this PR only builds the gate.**

## What's on the ground (verified on this branch)

- **easy_localization `^3.0.7`**, `intl ^0.20.2`. **No code-gen** — there is no
  `LocaleKeys`/`codegen_loader` file (`find mobile/lib -iname 'locale_keys*'` →
  nothing). Keys are **raw string literals**, not generated constants.
- Translations: `mobile/assets/translations/{tr-TR,en-US,de-DE,ar-AE}.json`,
  **nested JSON**, master `tr-TR.json` (740 leaf keys). `tr-TR` is the source of
  truth; other locales are partial by design (see T-010 / CLAUDE.md market model).
- **278 `.dart` files, 692 `.tr()` call sites; 0 `.plural()`, 0 double-quoted
  keys, 0 function-form `tr('…')`.** Of the 692, 649 are the clean single-quote
  extension form `'a.b.c'.tr(`; the remaining ~43 are non-literal (below).

## The call-site patterns the analyzer must handle

1. **Direct literal (the 649):** `'common.ok'.tr()`, sometimes multi-line —
   `'cart.discount'\n  .tr(namedArgs: {...})` (the literal is on the *previous*
   line). → must scan whole-file text with `'<key>'\s*\.\s*tr\s*\(`, not line-by-line.
2. **Interpolated / dynamic-suffix (prefix concatenation — the audit's headline
   case):** `'catalog.sort_${s.token}'.tr()`, `'help.ticket_cat_$code'.tr()`,
   `'notifications.cat_$category'`, `'returns.reason_$code'`, `'seller.status_$status'`,
   etc. The suffix is runtime; the **static prefix is known** (`catalog.sort_`,
   `help.ticket_cat_`, …). Declared keys under those prefixes are dynamically used.
3. **Variable / param / helper-held:** `messageKey.tr()`, `titleKey.tr()`,
   `label.tr()`, `_key(s).tr()` (a `switch` returning `'qa.sort_newest'` etc.).
   The actual key *value* is a literal **elsewhere** — at the widget construction
   site (`EmptyState(messageKey: 'cart.empty')`) or in the `switch` body. Pure
   static dataflow can't follow the variable; the literal-appears-anywhere rule
   (below) catches the value at its definition.

## Platform decision — text-based standalone Dart (named deviation from the prompt)

The T3-2 prompt assumed an **`analyzer`-package AST tool**. Discovery says
otherwise, and the choice is deliberate:

- The repo's existing Dart tooling (`tool/audit/list_providers.dart`,
  `list_routes.dart`) is **standalone, `dart:`-only, zero-`package:`-deps** so it
  runs via `dart run tool/audit/X.dart` with **no root `pubspec.yaml`** (there
  isn't one). Matching that convention keeps the analyzer dependency-free and
  cross-platform.
- An AST tool buys **nothing** here: 99% of keys are plain string literals a
  regex resolves perfectly, and the genuinely dynamic cases (`_key(enum)`,
  `'$prefix${x}'`) are **not statically evaluable even with the `analyzer`
  package** — AST gives you the syntax tree, not the runtime value of `s.token`.
- `custom_lint` is **not** a dep (`very_good_analysis ^6.0.0` is present, but
  it's a lint *ruleset*, not a `custom_lint` host). Per the prompt anti-goal we
  do **not** introduce it.

So: `tool/audit/check_i18n_usage.dart`, `dart:io` + `dart:convert` only. Unit
coverage via a built-in `--self-test` (inline fixtures) — `package:test` would
need a pubspec; the self-test keeps the tool zero-dep and CI-runnable.

## Algorithm

Declared set = flattened `tr-TR.json` leaf keys (master = source of truth).

- **Used (for dead-key detection)** — a declared key `K` is *used* if ANY holds:
  1. the literal `'K'` (or `"K"`) appears **anywhere** in `mobile/lib/**.dart`
     (catches direct `.tr()`, param-passing, and `switch`-body literals);
  2. `K` starts with a **dynamic prefix** auto-derived from an interpolated site
     `'<prefix>${…}'.tr(` / `'<prefix>$ident…'.tr(`;
  3. `K` matches an entry in the explicit allowlist (`i18n_dynamic_allowlist.txt`)
     — escape hatch for anything categories 1–2 miss.
  This is intentionally **biased toward "used"**: a dead-key gate feeds a removal
  PR, so the safe failure mode is keeping a maybe-used key, never deleting a live one.
- **Missing** — for each clean direct `'<key>'.tr(` (no `$`), if `<key>` ∉
  declared → missing. High-confidence (direct refs only). `tr-TR` master must
  declare every key referenced in code.
- **Unresolved (informational)** — `.tr(` whose receiver isn't a clean literal
  (variable/expr). Reported with `file:line`; does NOT fail CI.

## Output + exit codes

- `--manifest` → JSON: `{declared, unused[], missing[], unresolved_sites}`.
- `--check` (CI): **ratchet** — exit 1 on any drift from EITHER baseline:
  `i18n_usage_baseline.txt` (dead/unused keys) or `i18n_missing_baseline.txt`
  (missing keys). A "new dead key" or "new missing key" fails; a baseline that
  lists a key no longer dead/missing also fails (stale). The legal way to change
  a baseline is the follow-up sweep PR (dead keys) / translation-fix PR (missing).
- `--self-test` → runs the resolver fixtures; exit 1 on any failure.
- default (no flag) → human-readable summary.

### Discovery result on the full repo (this PR's baselines)

Running the analyzer on `mobile/lib` against the 740-key master:
- **163 dead (unused)** keys → frozen in `i18n_usage_baseline.txt`. The follow-up
  **sweep PR** removes them + clears the baseline.
- **10 missing** keys → frozen in `i18n_missing_baseline.txt`. These are a **real
  bug** (code calls e.g. `'checkout.payment_3ds'.tr()` / `'common.yes'.tr()` but
  the master — the launched TR locale — lacks them, so users see raw key strings).
  Fixing them is translation content, out of scope for this gate PR (§8) — filed
  as **TOOLING_AUDIT T-015** for a focused translation-fix PR. Baselining them
  makes the gate green + ratchets against NEW missing keys.
- 24 `.tr()` sites have non-literal receivers (variables / `_key(enum)`) — all
  resolved as used via the literal-anywhere rule; reported as informational.

Originally the doc planned `missing != 0 → hard fail`; discovery on the full repo
turned up 10 pre-existing missing keys, so missing is **baselined** like unused
(same ratchet) rather than blocking adoption on a pre-existing bug.

## Limitations (documented, not bugs)

- API-driven keys (`'$serverField'.tr()`) are unresolvable — none exist today;
  if added, allowlist them.
- The "literal appears anywhere" rule can count a key string in a comment as
  used. Accepted: conservative for a removal tool.

## Relationship to `check_i18n.sh` (T-010)

Orthogonal, both kept. `check_i18n.sh` = **completeness** (do locales match the
master key set). This analyzer = **usage** (are master keys referenced; are refs
declared). T-001 does NOT supersede T-010.
