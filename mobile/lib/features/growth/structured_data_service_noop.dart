import 'package:mopro/features/growth/structured_data_service.dart';

/// Non-web platforms (mobile/desktop/tests): JSON-LD is a no-op.
class _NoopStructuredDataService implements StructuredDataService {
  const _NoopStructuredDataService();
  @override
  void setJsonLd(Map<String, dynamic> data) {}
}

StructuredDataService createStructuredDataService() =>
    const _NoopStructuredDataService();
