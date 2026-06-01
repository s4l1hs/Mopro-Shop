import 'package:mopro/features/growth/meta_tags_service.dart';

/// Non-web platforms (mobile/desktop/tests): head meta tags are a no-op.
class _NoopMetaTagsService implements MetaTagsService {
  const _NoopMetaTagsService();
  @override
  void setMetaTags(MetaTagsInput input) {}
}

MetaTagsService createMetaTagsService() => const _NoopMetaTagsService();
