/// Appends a CDN width hint (`?w=`) to an image URL, sized to the physical
/// pixels the image will actually occupy (logical width × DPR), bucketed to the
/// nearest 100 so small layout differences don't churn the URL (and thus the
/// browser/CDN cache). Clamped to [100, 2000] so an off-screen widget with
/// absurd constraints never requests a giant image. Existing query params are
/// preserved; an existing `w` is overwritten (idempotent).
///
/// Pure function — no platform/context access — so it's trivially testable.
String responsiveImageUrl(
  String url, {
  required double targetWidthLogical,
  required double devicePixelRatio,
}) {
  final physical = (targetWidthLogical * devicePixelRatio).round();
  final bucketed = ((physical + 50) ~/ 100) * 100; // round to nearest 100
  final clamped = bucketed.clamp(100, 2000);
  final uri = Uri.parse(url);
  final params = Map<String, String>.from(uri.queryParameters)
    ..['w'] = '$clamped';
  return uri.replace(queryParameters: params).toString();
}
