import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for CatalogApi
void main() {
  final instance = MoproApi().getCatalogApi();

  group(CatalogApi, () {
    // Create a new product listing (admin / seller onboarding)
    //
    //Future<Product> createProduct(String xIdempotencyKey, CreateProductRequest createProductRequest, { String xTraceId }) async
    test('test createProduct', () async {
      // TODO
    });

    // Get live commission and KDV rates for a category + market pair
    //
    //Future<CategoryCommission> getCategoryCommission(int id, { String xTraceId, String market }) async
    test('test getCategoryCommission', () async {
      // TODO
    });

    // Get full product detail including variants and cashback preview
    //
    // Server resolves `title` and `description` from `Accept-Language` header. `cashback_preview.monthly_coin_minor` is computed handler-layer: `round(variant.price_minor × commission_pct_bps/10000 × 5000/10000 / 12)`. Uses the lowest-priced active variant for the preview amount. `seller_name` is joined from the seller module (in-process, core-svc only). `image_urls` are CDN-resolved (not raw storage keys). 
    //
    //Future<Product> getProduct(int id, { String xTraceId }) async
    test('test getProduct', () async {
      // TODO
    });

    // List all 42 product categories (locale-resolved names)
    //
    //Future<ListCategories200Response> listCategories({ String xTraceId }) async
    test('test listCategories', () async {
      // TODO
    });

    // List products with optional category filter, pagination, and sort
    //
    //Future<ListProducts200Response> listProducts({ String xTraceId, int categoryId, int page, int perPage, String sort }) async
    test('test listProducts', () async {
      // TODO
    });

  });
}
