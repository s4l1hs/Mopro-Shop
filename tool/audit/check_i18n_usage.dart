// tool/audit/check_i18n_usage.dart
//
// PURPOSE
//   Prefix-aware i18n DEAD-KEY analyzer (TOOLING_AUDIT T-001). Finds master
//   translation keys never referenced in Dart code (dead keys) and code refs to
//   keys missing from the master (missing keys). Complements check_i18n.sh,
//   which checks locale COMPLETENESS — this checks USAGE. See
//   docs/internal/i18n-analyzer.md for the full design + the platform rationale.
//
//   Standalone Dart: dart:io + dart:convert only (no package: deps, no AST), so
//   it runs from the repo root with no pubspec — matching tool/audit/list_*.dart.
//
// USAGE
//   dart run tool/audit/check_i18n_usage.dart            # human summary
//   dart run tool/audit/check_i18n_usage.dart --manifest # JSON manifest
//   dart run tool/audit/check_i18n_usage.dart --check     # CI gate (exit 1)
//   dart run tool/audit/check_i18n_usage.dart --self-test # unit fixtures
//
// MODEL (see the doc): declared = flattened tr-TR.json. A declared key is USED
// if its literal appears anywhere in mobile/lib, OR it starts with a prefix
// auto-derived from an interpolated `'pre${x}'.tr()` site, OR it is allowlisted.
// MISSING = a clean direct `'key'.tr()` whose key is not declared.
import 'dart:convert';
import 'dart:io';

const masterPath = 'mobile/assets/translations/tr-TR.json';
const libRoot = 'mobile/lib';
const baselinePath = 'tool/audit/i18n_usage_baseline.txt';
const missingBaselinePath = 'tool/audit/i18n_missing_baseline.txt';
const allowlistPath = 'tool/audit/i18n_dynamic_allowlist.txt';

// A quoted, key-shaped literal: starts with a letter, then word chars / dots.
final _literalKey = RegExp('''(['"])([A-Za-z][\\w.]*)\\1''');
// Direct `.tr(` on a clean string literal (handles multi-line via \\s*).
final _directTr = RegExp('''(['"])([A-Za-z][\\w.]*)\\1\\s*\\.\\s*tr\\s*\\(''');
// Interpolated literal (contains \$) followed by `.tr(`. Prefix = before first \$.
final _interpTr = RegExp('''(['"])([^'"]*\\\$[^'"]*)\\1\\s*\\.\\s*tr\\s*\\(''');
// Any `.tr(`/`.plural(` call — used to flag unresolved (non-literal) receivers.
final _anyTr = RegExp('\\.\\s*(?:tr|plural)\\s*\\(');

/// Findings extracted from one source file's text (pure — unit-testable).
class FileFindings {
  final Set<String> literals = {}; // every key-shaped quoted literal
  final Map<String, int> directRefs = {}; // clean `'k'.tr()` key -> first line
  final Set<String> dynamicPrefixes = {}; // static prefix of `'pre${x}'.tr()`
  final List<int> unresolvedLines = []; // `.tr(` with a non-literal receiver
}

int _lineAt(String text, int index) =>
    '\n'.allMatches(text.substring(0, index)).length + 1;

/// Core extraction over raw source text. No I/O — the self-test drives this.
FileFindings extractFromSource(String text) {
  final f = FileFindings();

  for (final m in _literalKey.allMatches(text)) {
    f.literals.add(m.group(2)!);
  }
  for (final m in _directTr.allMatches(text)) {
    final key = m.group(2)!;
    f.directRefs.putIfAbsent(key, () => _lineAt(text, m.start));
  }
  for (final m in _interpTr.allMatches(text)) {
    final lit = m.group(2)!;
    final prefix = lit.substring(0, lit.indexOf('\$'));
    if (prefix.isNotEmpty) f.dynamicPrefixes.add(prefix);
  }
  // Unresolved: a `.tr(`/`.plural(` whose receiver is not a string literal.
  for (final m in _anyTr.allMatches(text)) {
    var i = m.start - 1;
    while (i >= 0 && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n')) {
      i--;
    }
    if (i < 0 || (text[i] != "'" && text[i] != '"')) {
      f.unresolvedLines.add(_lineAt(text, m.start));
    }
  }
  return f;
}

/// Flatten nested JSON to dotted leaf keys.
Set<String> flattenKeys(dynamic node, [String prefix = '']) {
  final out = <String>{};
  if (node is Map) {
    node.forEach((k, v) {
      final key = prefix.isEmpty ? '$k' : '$prefix.$k';
      if (v is Map) {
        out.addAll(flattenKeys(v, key));
      } else {
        out.add(key);
      }
    });
  }
  return out;
}

class Analysis {
  final Set<String> declared;
  final List<String> unused;
  final List<String> missing;
  final int unresolvedCount;
  final List<String> unresolvedSites;
  Analysis(this.declared, this.unused, this.missing, this.unresolvedCount,
      this.unresolvedSites);
}

Analysis analyze(Set<String> declared, List<FileFindings> findings,
    Set<String> allowlist) {
  final literals = <String>{};
  final directRefs = <String>{};
  final prefixes = <String>{};
  final unresolved = <String>[];
  var unresolvedCount = 0;
  for (final f in findings) {
    literals.addAll(f.literals);
    directRefs.addAll(f.directRefs.keys);
    prefixes.addAll(f.dynamicPrefixes);
    unresolvedCount += f.unresolvedLines.length;
  }

  bool isUsed(String k) {
    if (literals.contains(k)) return true;
    if (allowlist.contains(k)) return true;
    for (final p in prefixes) {
      if (k.startsWith(p)) return true;
    }
    for (final a in allowlist) {
      if (a.endsWith('*') && k.startsWith(a.substring(0, a.length - 1))) {
        return true;
      }
    }
    return false;
  }

  final unused = declared.where((k) => !isUsed(k)).toList()..sort();
  final missing = directRefs.where((k) => !declared.contains(k)).toList()..sort();
  return Analysis(declared, unused, missing, unresolvedCount, unresolved);
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

/// Read a flat key-list file (baseline / allowlist); blanks + `#` lines ignored.
Set<String> _readKeyFile(String path) {
  final f = File(path);
  if (!f.existsSync()) return {};
  return f
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toSet();
}

/// Ratchet one current set against its baseline file. Returns true when they
/// match; prints additions (new drift) and removals (stale baseline) otherwise.
bool _gate(Set<String> current, String path, String label) {
  final baseline = _readKeyFile(path);
  final added = current.difference(baseline).toList()..sort();
  final gone = baseline.difference(current).toList()..sort();
  if (added.isEmpty && gone.isEmpty) return true;
  if (added.isNotEmpty) {
    stderr.writeln('NEW $label keys (not in $path) — add a real reference/'
        'declaration or run the follow-up sweep/fix PR:');
    for (final k in added) {
      stderr.writeln('  - $k');
    }
  }
  if (gone.isNotEmpty) {
    stderr.writeln('STALE baseline $path: ${gone.length} listed key(s) are no '
        'longer $label — remove them from the baseline (sweep/fix PR):');
    for (final k in gone) {
      stderr.writeln('  - $k');
    }
  }
  return false;
}

Analysis _runOnRepo() {
  final masterFile = File(masterPath);
  if (!masterFile.existsSync()) {
    stderr.writeln('check_i18n_usage: master not found: $masterPath');
    exit(2);
  }
  final declared = flattenKeys(jsonDecode(masterFile.readAsStringSync()));
  final findings = _dartFiles(libRoot)
      .map((p) => extractFromSource(File(p).readAsStringSync()))
      .toList();
  return analyze(declared, findings, _readKeyFile(allowlistPath));
}

void main(List<String> args) {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(File(Platform.script.toFilePath())
        .readAsLinesSync()
        .takeWhile((l) => l.startsWith('//'))
        .map((l) => l.replaceFirst(RegExp('^// ?'), ''))
        .join('\n'));
    return;
  }
  if (args.contains('--self-test')) {
    exit(_selfTest() ? 0 : 1);
  }

  final a = _runOnRepo();

  if (args.contains('--manifest')) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'declared': a.declared.length,
      'unused': a.unused,
      'missing': a.missing,
      'unresolved_sites': a.unresolvedCount,
    }));
    return;
  }

  if (args.contains('--check')) {
    // Ratchet: both the dead (unused) and missing sets are frozen at a baseline.
    // The gate fails on any DRIFT — a new dead/missing key, or a baseline that
    // lists a key no longer dead/missing. The legal way to change a baseline is
    // the follow-up sweep PR (dead keys) / translation-fix PR (missing keys).
    final unusedOk = _gate(a.unused.toSet(), baselinePath, 'dead (unused)');
    final missingOk = _gate(a.missing.toSet(), missingBaselinePath, 'missing');
    final ok = unusedOk && missingOk;
    if (ok) {
      stdout.writeln('i18n-usage: OK — ${a.declared.length} declared; '
          '${a.unused.length} dead, ${a.missing.length} missing (both == baseline).');
    }
    exit(ok ? 0 : 1);
  }

  // Default: human summary.
  stdout.writeln('i18n usage — master $masterPath (${a.declared.length} keys)');
  stdout.writeln('  unused (dead) keys : ${a.unused.length}');
  stdout.writeln('  missing keys       : ${a.missing.length}');
  stdout.writeln('  unresolved .tr()   : ${a.unresolvedCount} (informational)');
  if (a.missing.isNotEmpty) {
    stdout.writeln('\nMISSING:');
    for (final k in a.missing) {
      stdout.writeln('  - $k');
    }
  }
}

// ── self-test (inline fixtures; no package:test) ────────────────────────────
bool _selfTest() {
  var pass = true;
  void check(bool cond, String label) {
    stdout.writeln('${cond ? "PASS" : "FAIL"}  $label');
    if (!cond) pass = false;
  }

  // flatten
  final decl = flattenKeys(jsonDecode(
      '{"app_name":"M","common":{"ok":"o","cancel":"c"},'
      '"catalog":{"sort_price":"p","sort_name":"n"},"orphan":{"dead":"x"}}'));
  check(decl.containsAll({'app_name', 'common.ok', 'catalog.sort_price'}),
      'flatten nested + top-level keys');

  // direct literal + multi-line + double quote not used here
  final src = '''
    Text('common.ok'.tr());
    Widget x() => Text('common.cancel'
        .tr(namedArgs: {'a': b}));         // multi-line literal
    Text('catalog.sort_\${s.token}'.tr()); // interpolated -> prefix catalog.sort_
    Text(messageKey.tr());                  // unresolved (variable)
    const k = 'app_name';                   // literal-anywhere (param/var value)
    Text('new.undeclared'.tr());            // missing
  ''';
  final f = extractFromSource(src);
  check(f.directRefs.containsKey('common.ok'), 'direct literal ref');
  check(f.directRefs.containsKey('common.cancel'), 'multi-line .tr() ref');
  check(f.dynamicPrefixes.contains('catalog.sort_'), 'interpolation prefix');
  check(f.literals.contains('app_name'), 'bare literal captured (param value)');
  check(f.unresolvedLines.isNotEmpty, 'unresolved variable receiver flagged');

  final a = analyze(decl, [f], {});
  check(!a.unused.contains('common.ok'), 'direct-ref key not dead');
  check(!a.unused.contains('app_name'), 'literal-anywhere key not dead');
  check(!a.unused.contains('catalog.sort_price'), 'prefix-covered key not dead');
  check(a.unused.contains('orphan.dead'), 'truly-unused key is dead');
  check(a.missing.contains('new.undeclared'), 'undeclared direct ref is missing');

  // allowlist exact + glob
  final a2 = analyze(decl, [extractFromSource('//')], {'orphan.dead'});
  check(!a2.unused.contains('orphan.dead'), 'allowlist exact suppresses dead');
  final a3 = analyze(decl, [extractFromSource('//')], {'orphan.*'});
  check(!a3.unused.contains('orphan.dead'), 'allowlist glob suppresses dead');

  return pass;
}
