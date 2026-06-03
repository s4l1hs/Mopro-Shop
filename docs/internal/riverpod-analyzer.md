# Riverpod inference analyzer — discovery + design (TOOLING_AUDIT T3-5)

The second deferred Step-1 analyzer. `tool/audit/riverpod_check.dart` — standalone
Dart (`dart:io` only, no `package:`, no `custom_lint`), matching the
`list_providers.dart` / `check_i18n_usage.dart` convention.

## What's on the ground (verified)
- **No `@riverpod` code-gen** (`riverpod_generator`/`riverpod_annotation` absent
  from pubspec) — providers are declared manually. `very_good_analysis` is the
  ruleset; `custom_lint` is NOT a dep (so a standalone tool, not a lint plugin).
- 92 provider declarations, 25 `Notifier`/`AsyncNotifier` subclasses.
- Provider types are **mostly explicit** (`Provider<int>`, `StateProvider<bool>`);
  a handful are inferred (notably `NotifierProvider(X.new)` forms).

## The two signals — and why only one is gated

### Gated: inferred-type providers (clean, ratcheted)
A provider declared without an explicit `<Type>` lets Dart infer it; inference
can silently drift when the builder's return type changes. Detection is textual
and unambiguous: `final x = Provider(...)` (inferred) vs `final x = Provider<T>(...)`
(explicit). The analyzer baselines the current inferred set and **fails on a NEW
inferred-type provider** — a ratchet, exactly like T-001. Existing ones are frozen
(a follow-up may annotate them; that's not this PR).

### Informational only: Notifier `build()` shape (NOT gated)
CONTRIBUTING documents three safe `build()` shapes (#1 const-then-event,
#2 `Future.microtask` defer, #3 post-`await` mutation) under a
**synchronous-reachability** rule (no `state =` reachable synchronously from
`build()` before the first `await`, including via `unawaited`/`Future.wait`).
Classifying that **correctly** needs inter-procedural, await-position-aware flow
analysis — well beyond textual heuristics, and a wrong label is worse than none
(the §4.3.4 anti-trap). So the analyzer emits a **best-effort hint** per Notifier
(`microtask` / `const-return` / `post-await` / `unclassified`) as an inventory,
and **never fails** on it. A real shape-enforcer would be a `custom_lint` rule —
a separate, larger effort if the project later adopts `custom_lint`.

## Algorithm
- Scan `mobile/lib/**/*.dart` (text).
- **Providers:** match `final <name> = <Kind>Provider[.family|.autoDispose]*(<TypeArgs>)?(`.
  Record name, file:line, kind, `explicit` (has `<…>`) or `inferred`.
- **Notifiers:** match `class <N> extends (Async)?Notifier<…>`; within its `build(`
  body, hint the shape: `Future.microtask` → microtask; a `state =`/`state.` before
  any `await` → likely-eager (flagged `unclassified` for human review); leading
  `return ` with no pre-state-write → const-return; else post-await/unclassified.

## Output + exit codes
- `--manifest` → JSON `{providers_total, inferred[], notifiers[]{name,shape}}`.
- `--check` (CI ratchet): exit 1 if the inferred-provider set drifts from
  `tool/audit/riverpod_inferred_baseline.txt`. Notifier shapes never fail.
- `--self-test` → inline fixtures. default → human summary.

## Out of scope (this PR builds the gate, not the cleanup)
- Annotating the baselined inferred providers with explicit types — follow-up.
- Enforcing Notifier shapes — needs `custom_lint`; not adopted.
