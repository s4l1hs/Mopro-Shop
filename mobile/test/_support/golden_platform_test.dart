import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'golden_platform.dart';

// Minimal valid 1x1 transparent PNG so LocalFileComparator can decode it.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4'
  '2mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);

void main() {
  group('sidecar reader', () {
    test('parses the platform line', () {
      expect(parseGoldenSidecarPlatform('platform: linux\n'), 'linux');
      expect(
        parseGoldenSidecarPlatform('# note\nplatform:  macos  \n'),
        'macos',
      );
    });

    test('throws FormatException when no platform line', () {
      expect(
        () => parseGoldenSidecarPlatform('nothing here\n'),
        throwsFormatException,
      );
    });

    test('readGoldenSidecarPlatform throws cleanly on missing file', () {
      final missing = File(
        '${Directory.systemTemp.path}/does_not_exist_${DateTime.now().microsecondsSinceEpoch}.meta',
      );
      expect(
        () => readGoldenSidecarPlatform(missing),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('PlatformGuardedGoldenComparator', () {
    late Directory dir;
    late LocalFileComparator inner;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('golden_guard_test');
      inner = LocalFileComparator(Uri.file('${dir.path}/x_test.dart'));
      File('${dir.path}/g.png').writeAsBytesSync(_png);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('passes through to the inner comparator on platform match', () async {
      File('${dir.path}/g.png.meta').writeAsStringSync('platform: testos\n');
      final cmp = PlatformGuardedGoldenComparator(inner, platform: 'testos');
      // Identical bytes → inner pixel comparison succeeds; no platform throw.
      expect(
        await cmp.compare(Uint8List.fromList(_png), Uri.parse('g.png')),
        isTrue,
      );
    });

    test('fails with a remediation message on platform mismatch', () async {
      File('${dir.path}/g.png.meta').writeAsStringSync('platform: linux\n');
      final cmp = PlatformGuardedGoldenComparator(inner, platform: 'macos');
      await expectLater(
        cmp.compare(Uint8List.fromList(_png), Uri.parse('g.png')),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            contains('make update-goldens'),
          ),
        ),
      );
    });

    test('update writes a sidecar stamped with the platform', () async {
      final cmp = PlatformGuardedGoldenComparator(inner, platform: 'linux');
      await cmp.update(Uri.parse('g.png'), Uint8List.fromList(_png));
      expect(
        readGoldenSidecarPlatform(File('${dir.path}/g.png.meta')),
        'linux',
      );
    });
  });
}
