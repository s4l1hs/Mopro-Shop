import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro_api/mopro_api.dart';

// Pass interceptors: [] so MoproApi does NOT add its generated OAuth
// interceptors on top of the Dio instance we already configured.
final apiClientProvider = Provider<MoproApi>((ref) {
  final dio = ref.watch(dioProvider);
  return MoproApi(dio: dio, interceptors: []);
});

final authApiProvider = Provider<AuthApi>((ref) {
  return ref.watch(apiClientProvider).getAuthApi();
});

final catalogApiProvider = Provider<CatalogApi>((ref) {
  return ref.watch(apiClientProvider).getCatalogApi();
});

final cartApiProvider = Provider<CartApi>((ref) {
  return ref.watch(apiClientProvider).getCartApi();
});

final walletApiProvider = Provider<WalletApi>((ref) {
  return ref.watch(apiClientProvider).getWalletApi();
});

final cashbackApiProvider = Provider<CashbackApi>((ref) {
  return ref.watch(apiClientProvider).getCashbackApi();
});

final ordersApiProvider = Provider<OrdersApi>((ref) {
  return ref.watch(apiClientProvider).getOrdersApi();
});

final searchApiProvider = Provider<SearchApi>((ref) {
  return ref.watch(apiClientProvider).getSearchApi();
});

final sellerApiProvider = Provider<SellerApi>((ref) {
  return ref.watch(apiClientProvider).getSellerApi();
});

final meApiProvider = Provider<MeApi>((ref) {
  return ref.watch(apiClientProvider).getMeApi();
});

final addressApiProvider = Provider<AddressApi>((ref) {
  return ref.watch(apiClientProvider).getAddressApi();
});
