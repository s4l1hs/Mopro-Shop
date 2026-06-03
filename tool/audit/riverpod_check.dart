// tool/audit/riverpod_check.dart
//
// PURPOSE
//   Riverpod inference analyzer (TOOLING_AUDIT T3-5). GATES inferred-type
//   providers (a provider declared without an explicit <Type> — inference can
//   drift) as a ratchet against the baseline; INVENTORIES Notifier build() shapes
//   as informational only (the synchronous-reachability rule is too subtle for
//   textual heuristics to enforce — see docs/internal/riverpod-analyzer.md).
//
//   Standalone Dart: dart:io + dart:convert only (no package: deps, no AST, no
//   custom_lint) — matching tool/audit/list_providers.dart / check_i18n_usage.dart.
//
// USAGE
//   dart run tool/audit/riverpod_check.dart            # human summary
//   dart run tool/audit/riverpod_check.dart --manifest # JSON
//   dart run tool/audit/riverpod_check.dart --check     # CI ratchet (exit 1 on drift)
//   dart run tool/audit/riverpod_check.dart --self-test # inline fixtures
import 'dart:convert';
import 'dart:io';

const libRoot = 'mobile/lib';
const inferredBaselinePath = 'tool/audit/riverpod_inferred_baseline.txt';

// final <name> = <Kind>Provider[.modifier]* followed by '<' (explicit) or '(' (inferred).
final _provider =
    RegExp(r'final\s+(\w+)\s*=\s*(\w*Provider(?:\.\w+)*)\s*([<(])');
// class <N> extends (Async)?Notifier<...>
final _notifier = RegExp(r'class\s+(\w+)\s+extends\s+(?:Async)?Notifier<');

class Provider {
  final String name;
  final String kind;
  final bool inferred;
  Provider(this.name, this.kind, this.inferred);
}

class Notifier {
  final String name;
  final String shape;
  Notifier(this.name, this.shape);
}

/// Extract the `build(...)` method body (expression or balanced-brace block)
/// from a Notifier class. Returns null if not found. Scoping to build() avoids
/// mislabelling event-handler `state =` writes as build-time ones.
String? buildBody(String classBody) {
  final sig = RegExp(r'build\s*\([^)]*\)\s*(?:async\s*)?').firstMatch(classBody);
  if (sig == null) return null;
  var i = sig.end;
  // Expression body: `=> ... ;`
  if (i < classBody.length && classBody.startsWith('=>', i)) {
    final end = classBody.indexOf(';', i);
    return classBody.substring(i, end < 0 ? classBody.length : end);
  }
  // Block body: balance braces from the first '{'.
  final open = classBody.indexOf('{', i);
  if (open < 0) return null;
  var depth = 0;
  for (var j = open; j < classBody.length; j++) {
    if (classBody[j] == '{') depth++;
    if (classBody[j] == '}') {
      depth--;
      if (depth == 0) return classBody.substring(open + 1, j);
    }
  }
  return classBody.substring(open + 1);
}

/// INFORMATIONAL shape hint, scoped to build() — only RELIABLE signals are
/// labelled; everything else is 'unclassified' (never gated). The full
/// synchronous-reachability rule needs flow analysis a textual tool can't do.
String shapeOf(String classBody) {
  final body = buildBody(classBody);
  if (body == null) return 'no-build';
  if (body.contains('Future.microtask')) return 'microtask'; // shape #2
  final firstAwait = body.indexOf('await');
  final preAwait = firstAwait >= 0 ? body.substring(0, firstAwait) : body;
  if (!RegExp(r'\bstate\s*=').hasMatch(preAwait)) {
    // No state write before the first await in build → matches #1 or #3.
    return firstAwait >= 0 ? 'post-await' : 'const-return';
  }
  return 'unclassified'; // a pre-await state write — worth a human look
}

class Findings {
  final List<Provider> providers;
  final List<Notifier> notifiers;
  Findings(this.providers, this.notifiers);
}

Findings extractFromSource(String text) {
  final providers = <Provider>[];
  for (final m in _provider.allMatches(text)) {
    providers.add(Provider(m.group(1)!, m.group(2)!, m.group(3) == '('));
  }
  final notifiers = <Notifier>[];
  for (final m in _notifier.allMatches(text)) {
    // Body window: from the class decl to a heuristic end (next "\nclass " or EOF).
    final start = m.start;
    final next = text.indexOf('\nclass ', m.end);
    final body = text.substring(start, next < 0 ? text.length : next);
    notifiers.add(Notifier(m.group(1)!, shapeOf(body)));
  }
  return Findings(providers, notifiers);
}

List<String> _dartFiles(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .toList()
    ..sort();
}

Set<String> _readKeyFile(String path) {
  final f = File(path);
  if (!f.existsSync()) return {};
  return f
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toSet();
}

Findings _runOnRepo() {
  final providers = <Provider>[];
  final notifiers = <Notifier>[];
  for (final p in _dartFiles(libRoot)) {
    final f = extractFromSource(File(p).readAsStringSync());
    providers.addAll(f.providers);
    notifiers.addAll(f.notifiers);
  }
  return Findings(providers, notifiers);
}

void main(List<String> args) {
  if (args.contains('--self-test')) exit(_selfTest() ? 0 : 1);

  final f = _runOnRepo();
  final inferred = (f.providers.where((p) => p.inferred).map((p) => p.name).toSet()
        .toList()
        ..sort());

  if (args.contains('--manifest')) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'providers_total': f.providers.length,
      'inferred': inferred,
      'notifiers': (f.notifiers.toList()..sort((a, b) => a.name.compareTo(b.name)))
          .map((n) => {'name': n.name, 'shape': n.shape})
          .toList(),
    }));
    return;
  }

  if (args.contains('--check')) {
    final baseline = _readKeyFile(inferredBaselinePath);
    final cur = inferred.toSet();
    final added = cur.difference(baseline).toList()..sort();
    final gone = baseline.difference(cur).toList()..sort();
    var ok = true;
    if (added.isNotEmpty) {
      ok = false;
      stderr.writeln('NEW inferred-type providers (add an explicit <Type> or, if '
          'intentional, add to $inferredBaselinePath):');
      for (final k in added) {
        stderr.writeln('  - $k');
      }
    }
    if (gone.isNotEmpty) {
      ok = false;
      stderr.writeln('STALE baseline: ${gone.length} provider(s) listed are no '
          'longer inferred — remove them from $inferredBaselinePath:');
      for (final k in gone) {
        stderr.writeln('  - $k');
      }
    }
    if (ok) {
      stdout.writeln('riverpod-check: OK — ${f.providers.length} providers, '
          '${inferred.length} inferred (== baseline), ${f.notifiers.length} notifiers.');
    }
    exit(ok ? 0 : 1);
  }

  // Default human summary.
  final byShape = <String, int>{};
  for (final n in f.notifiers) {
    byShape[n.shape] = (byShape[n.shape] ?? 0) + 1;
  }
  stdout.writeln('riverpod usage — ${libRoot}');
  stdout.writeln('  providers        : ${f.providers.length}');
  stdout.writeln('  inferred-type    : ${inferred.length} (gated vs baseline)');
  stdout.writeln('  notifiers        : ${f.notifiers.length}');
  stdout.writeln('  shapes (info)    : $byShape');
}

// ── self-test (inline fixtures; no package:test) ────────────────────────────
bool _selfTest() {
  var pass = true;
  void check(bool c, String label) {
    stdout.writeln('${c ? "PASS" : "FAIL"}  $label');
    if (!c) pass = false;
  }

  final src = '''
    final aProvider = Provider<int>((ref) => 1);              // explicit
    final bProvider = StateProvider<bool>((ref) => false);    // explicit
    final cProvider = NotifierProvider(CNotifier.new);        // inferred
    final dProvider = Provider.family<String, int>((ref, id) => '');  // explicit (modifier)
    final eProvider = FutureProvider((ref) async => 1);       // inferred

    class CNotifier extends Notifier<int> {
      int build() { Future.microtask(_load); return 0; }      // microtask
      void _load() {}
    }
    class FNotifier extends AsyncNotifier<int> {
      Future<int> build() async { final r = await x(); return r; }  // post-await
    }
  ''';
  final f = extractFromSource(src);
  final inferred = f.providers.where((p) => p.inferred).map((p) => p.name).toSet();
  check(!inferred.contains('aProvider'), 'explicit Provider<int> not inferred');
  check(!inferred.contains('bProvider'), 'explicit StateProvider<bool> not inferred');
  check(inferred.contains('cProvider'), 'NotifierProvider(...) is inferred');
  check(!inferred.contains('dProvider'), 'Provider.family<...> not inferred');
  check(inferred.contains('eProvider'), 'FutureProvider(...) is inferred');
  check(f.providers.length == 5, 'all 5 providers found (got ${f.providers.length})');
  final shapes = {for (final n in f.notifiers) n.name: n.shape};
  check(shapes['CNotifier'] == 'microtask', 'CNotifier → microtask (got ${shapes['CNotifier']})');
  check(f.notifiers.length == 2, 'both notifiers found');

  return pass;
}
