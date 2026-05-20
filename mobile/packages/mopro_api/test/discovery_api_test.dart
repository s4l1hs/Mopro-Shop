import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for DiscoveryApi
void main() {
  final instance = MoproApi().getDiscoveryApi();

  group(DiscoveryApi, () {
    // Promotional banners for a given placement
    //
    //Future<ListBanners200Response> listBanners({ String xTraceId, String placement }) async
    test('test listBanners', () async {
      // TODO
    });

    // Personalised product recommendations for the authenticated user
    //
    //Future<ListRecommendations200Response> listRecommendations({ String xTraceId }) async
    test('test listRecommendations', () async {
      // TODO
    });

  });
}
