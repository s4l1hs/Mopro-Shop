import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Outcome of a share attempt, surfaced so the UI can react (e.g. show a
/// "copied" snackbar on the web clipboard fallback).
enum ShareOutcome { shared, copiedToClipboard, failed }

/// Abstracts the platform share intent so widgets stay platform-agnostic and
/// tests can stub it.
///
/// - Mobile (iOS/Android): native share sheet via `share_plus`.
/// - Web: the Web Share API via `share_plus` when available; on browsers
///   without it (`share_plus` throws / returns unavailable) the URL is copied
///   to the clipboard and [ShareOutcome.copiedToClipboard] is returned so the
///   caller can show a confirmation snackbar.
class ShareService {
  ShareService({
    Future<void> Function(String text, String? subject)? shareFn,
    Future<void> Function(String text)? copyFn,
  })  : _share = shareFn ?? _defaultShare,
        _copy = copyFn ?? _defaultCopy;

  final Future<void> Function(String text, String? subject) _share;
  final Future<void> Function(String text) _copy;

  Future<ShareOutcome> share({required String text, String? subject}) async {
    try {
      await _share(text, subject);
      return ShareOutcome.shared;
    } catch (_) {
      // Web without the Web Share API (share_plus throws / unavailable) →
      // clipboard fallback. Never let a share failure surface to the user.
      try {
        await _copy(text);
        return ShareOutcome.copiedToClipboard;
      } catch (e) {
        if (kDebugMode) debugPrint('ShareService: clipboard fallback failed: $e');
        return ShareOutcome.failed;
      }
    }
  }

  static Future<void> _defaultShare(String text, String? subject) async {
    final result = await Share.share(text, subject: subject);
    // On web without Web Share, share_plus may report unavailable instead of
    // throwing — treat that as "fall back to clipboard".
    if (result.status == ShareResultStatus.unavailable) {
      throw StateError('share unavailable on this platform');
    }
  }

  static Future<void> _defaultCopy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

final shareServiceProvider = Provider<ShareService>((_) => ShareService());
