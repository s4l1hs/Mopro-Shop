// tool/audit/list_routes.dart
//
// PURPOSE
//   Inventory every go_router route declared in the Flutter app. Reads the
//   router source as text (no Flutter import — runnable as standalone Dart on
//   macOS and Linux) and emits one Markdown row per `path:` declaration with
//   its source line and a best-effort screen-widget guess (the first
//   Capitalised constructor that follows the path in the same route block).
//
// OUTPUT
//   GitHub-flavoured Markdown to stdout. Deterministic: rows are emitted in
//   source order, which is stable across runs on an unchanged file.
//
// USAGE
//   dart run tool/audit/list_routes.dart            # markdown to stdout
//   dart run tool/audit/list_routes.dart --help
//
// EXTEND
//   If the router is split across files, add their paths to [_routerFiles].
import 'dart:io';

const _routerFiles = <String>['mobile/lib/core/router/app_router.dart'];

void main(List<String> args) {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln('Lists every go_router route (path, line, screen guess) as '
        'Markdown.\nUsage: dart run tool/audit/list_routes.dart');
    return;
  }

  final pathRe = RegExp(r"""\bpath:\s*'([^']*)'""");
  final widgetRe = RegExp(r'\b(const\s+)?([A-Z][A-Za-z0-9]+)\s*\(');
  final shellRe = RegExp(r'(StatefulShellRoute|ShellRoute)');

  final rows = <List<String>>[];
  var total = 0;
  for (final file in _routerFiles) {
    final f = File(file);
    if (!f.existsSync()) continue;
    final lines = f.readAsLinesSync();
    var currentShell = '—';
    for (var i = 0; i < lines.length; i++) {
      if (shellRe.hasMatch(lines[i])) {
        currentShell = shellRe.firstMatch(lines[i])!.group(1)!;
      }
      final m = pathRe.firstMatch(lines[i]);
      if (m == null) continue;
      final path = m.group(1)!;
      // Look ahead up to 6 lines for the first non-noise screen constructor.
      var screen = '(builder)';
      lookahead:
      for (var j = i; j < i + 7 && j < lines.length; j++) {
        for (final wm in widgetRe.allMatches(lines[j])) {
          final name = wm.group(2)!;
          if (_isNoise(name)) continue;
          screen = name;
          break lookahead;
        }
      }
      total++;
      rows.add([path, '${file.split('/').last}:${i + 1}', screen, currentShell]);
    }
  }

  stdout.writeln('| Path | Source | Screen (guess) | Shell |');
  stdout.writeln('|---|---|---|---|');
  for (final r in rows) {
    stdout.writeln('| `${r[0]}` | `${r[1]}` | ${r[2]} | ${r[3]} |');
  }
  stdout.writeln('\n_Total: $total route declarations._');
}

bool _isNoise(String name) => const {
      'GoRoute',
      'GoRouterState',
      'StatefulShellRoute',
      'ShellRoute',
      'StatefulNavigationShell',
      'NavigatorState',
      'GlobalKey',
      'ValueKey',
      'Key',
      'MaterialPage',
      'NoTransitionPage',
      'Duration',
      'Offset',
    }.contains(name);
