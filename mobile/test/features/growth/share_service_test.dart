import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/growth/share_service.dart';

void main() {
  group('ShareService', () {
    test('share succeeds → shared (clipboard not touched)', () async {
      var copied = false;
      final svc = ShareService(
        shareFn: (_, __) async {},
        copyFn: (_) async => copied = true,
      );
      expect(
        await svc.share(text: 'x — https://mopro.shop/products/1'),
        ShareOutcome.shared,
      );
      expect(copied, isFalse);
    });

    test('share throws (web w/o Web Share) → clipboard fallback', () async {
      String? copiedText;
      final svc = ShareService(
        shareFn: (_, __) async => throw StateError('unavailable'),
        copyFn: (t) async => copiedText = t,
      );
      final outcome = await svc.share(text: 'hello — https://mopro.shop/x');
      expect(outcome, ShareOutcome.copiedToClipboard);
      expect(copiedText, 'hello — https://mopro.shop/x');
    });

    test('share + clipboard both fail → failed (never throws)', () async {
      final svc = ShareService(
        shareFn: (_, __) async => throw StateError('no share'),
        copyFn: (_) async => throw StateError('no clipboard'),
      );
      expect(await svc.share(text: 'x'), ShareOutcome.failed);
    });

    test('subject is forwarded to the share function', () async {
      String? gotSubject;
      final svc = ShareService(
        shareFn: (_, s) async => gotSubject = s,
        copyFn: (_) async {},
      );
      await svc.share(text: 'x', subject: 'Bak bu ürüne');
      expect(gotSubject, 'Bak bu ürüne');
    });
  });
}
