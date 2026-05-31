// tool/audit/list_providers.dart
//
// PURPOSE
//   Inventory every Riverpod provider declared in the Flutter app: top-level
//   `final xProvider = ...` declarations and the Notifier/AsyncNotifier
//   subclasses that back `NotifierProvider`s. Reads sources as text (no Flutter
//   import — standalone Dart, macOS + Linux).
//
// OUTPUT
//   GitHub-flavoured Markdown to stdout: one table of provider declarations
//   (name, file:line, provider kind) and one of Notifier subclasses. Rows are
//   sorted by name for deterministic output.
//
// USAGE
//   dart run tool/audit/list_providers.dart            # markdown to stdout
//   dart run tool/audit/list_providers.dart --help
//
// EXTEND
//   Scans mobile/lib recursively for *.dart. Adjust [_root] to rescope.
import 'dart:io';

const _root = 'mobile/lib';

void main(List<String> args) {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln('Lists Riverpod providers + Notifier subclasses as Markdown.'
        '\nUsage: dart run tool/audit/list_providers.dart');
    return;
  }

  // final fooProvider = SomethingProvider...(...)  /  = SomethingProvider.family
  final declRe = RegExp(
    r'^\s*final\s+([a-zA-Z0-9_]+)\s*=\s*([A-Za-z0-9_.]*Provider[A-Za-z0-9_.]*)',
  );
  // class FooNotifier extends (Async)Notifier<...> / FamilyNotifier / etc.
  final notifierRe = RegExp(
    r'^\s*class\s+([A-Za-z0-9_]+)\s+extends\s+(\$?[A-Za-z0-9_]*Notifier[A-Za-z0-9_<>, ]*)',
  );

  final decls = <List<String>>[];
  final notifiers = <List<String>>[];

  for (final ent in Directory(_root).listSync(recursive: true)) {
    if (ent is! File || !ent.path.endsWith('.dart')) continue;
    if (ent.path.endsWith('.g.dart') || ent.path.endsWith('.freezed.dart')) {
      continue;
    }
    final rel = ent.path;
    final lines = ent.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final d = declRe.firstMatch(lines[i]);
      if (d != null) {
        decls.add([d.group(1)!, _kind(d.group(2)!), '$rel:${i + 1}']);
      }
      final n = notifierRe.firstMatch(lines[i]);
      if (n != null) {
        notifiers.add([n.group(1)!, _trim(n.group(2)!), '$rel:${i + 1}']);
      }
    }
  }

  decls.sort((a, b) => a[0].compareTo(b[0]));
  notifiers.sort((a, b) => a[0].compareTo(b[0]));

  stdout.writeln('### Provider declarations\n');
  stdout.writeln('| Provider | Kind | Source |');
  stdout.writeln('|---|---|---|');
  for (final r in decls) {
    stdout.writeln('| `${r[0]}` | ${r[1]} | `${r[2]}` |');
  }

  stdout.writeln('\n### Notifier subclasses\n');
  stdout.writeln('| Class | Base | Source |');
  stdout.writeln('|---|---|---|');
  for (final r in notifiers) {
    stdout.writeln('| `${r[0]}` | `${r[1]}` | `${r[2]}` |');
  }

  stdout.writeln('\n_Totals: ${decls.length} provider declarations; '
      '${notifiers.length} Notifier subclasses._');
}

String _kind(String raw) {
  final base = raw.split('(').first.split('.').first;
  return '`$base`';
}

String _trim(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();
