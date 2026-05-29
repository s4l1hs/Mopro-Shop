import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Platform-mismatch guard for golden files (Session 4e §5.5).
///
/// Flutter goldens render differently per platform (fonts/subpixel), so this
/// repo baselines them on Linux/CI. Each golden gets a sidecar `<name>.png.meta`
/// recording the platform it was generated on (`platform: <os>`). The guard:
///
/// - on `compare`: if a sidecar exists and its platform != the current OS, it
///   fails the test with a clear message pointing at `make update-goldens`
///   (instead of a cryptic pixel diff);
/// - on `update` (`flutter test --update-goldens`): writes the golden AND the
///   sidecar stamped with the current platform.
///
/// Installed globally in `test/flutter_test_config.dart`. Inert until sidecars
/// exist, so it is non-breaking until the goldens are regenerated on Linux.

/// The platform string stamped into / read from a sidecar.
String currentGoldenPlatform() => Platform.operatingSystem;

/// Parses the `platform:` line from a sidecar's contents. Throws [FormatException]
/// if absent so callers can surface a clear error.
String parseGoldenSidecarPlatform(String contents) {
  for (final line in contents.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('platform:')) {
      return trimmed.substring('platform:'.length).trim();
    }
  }
  throw const FormatException('sidecar has no "platform:" line');
}

/// Reads the recorded platform from a sidecar file. Throws [FileSystemException]
/// if the file is missing.
String readGoldenSidecarPlatform(File sidecar) {
  if (!sidecar.existsSync()) {
    throw FileSystemException('golden sidecar not found', sidecar.path);
  }
  return parseGoldenSidecarPlatform(sidecar.readAsStringSync());
}

class PlatformGuardedGoldenComparator implements GoldenFileComparator {
  PlatformGuardedGoldenComparator(this._inner, {String? platform})
      : _platform = platform ?? currentGoldenPlatform();

  final LocalFileComparator _inner;
  final String _platform;

  File sidecarFor(Uri golden) =>
      File('${File.fromUri(_inner.basedir.resolveUri(golden)).path}.meta');

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final sidecar = sidecarFor(golden);
    if (sidecar.existsSync()) {
      final recorded = parseGoldenSidecarPlatform(sidecar.readAsStringSync());
      if (recorded != _platform) {
        throw TestFailure(
          'Golden "$golden" was baselined on "$recorded" but this run is on '
          '"$_platform". Goldens in this repo are baselined on Linux/CI — '
          'regenerate them with `make update-goldens` (see CONTRIBUTING.md); '
          'do not compare or re-baseline on a non-CI platform.',
        );
      }
    }
    return _inner.compare(imageBytes, golden);
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    await _inner.update(golden, imageBytes);
    sidecarFor(golden).writeAsStringSync('platform: $_platform\n');
  }

  @override
  Uri getTestUri(Uri key, int? version) => _inner.getTestUri(key, version);
}

/// Wraps the active [LocalFileComparator] with the platform guard. Call from
/// `flutter_test_config.dart`'s `testExecutable`.
void installPlatformGuardedGoldenComparator() {
  final inner = goldenFileComparator;
  if (inner is LocalFileComparator) {
    goldenFileComparator = PlatformGuardedGoldenComparator(inner);
  }
}
