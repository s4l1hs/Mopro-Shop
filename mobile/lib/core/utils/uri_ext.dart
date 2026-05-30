/// URL-state helpers.
extension UriEmptyClear on Uri {
  /// Returns a new [Uri] with all query parameters cleared.
  ///
  /// Use this instead of `replace(queryParameters: null)`, which is a **no-op**
  /// in Dart (a null `queryParameters` means "leave unchanged", so the existing
  /// query is kept). See `CONTRIBUTING.md` → "URL state".
  Uri clearQueryParameters() {
    if (queryParameters.isEmpty) return this;
    return replace(queryParameters: const <String, String>{});
  }
}
