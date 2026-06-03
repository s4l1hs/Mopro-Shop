import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// `moproPageTitle` localises via the global `.tr()` (P-014). Unit tests do not
// load the translation bundle, so `.tr()` returns the *key* — we assert the
// route → branded-key mapping (the function's own logic: prefix, branch
// selection, dynamic-name passthrough, namedArgs key choice). The key → Turkish
// mapping is asserted directly from tr-TR.json below, and enforced live by the
// i18n usage/extras gates. Together they cover route → rendered title.
void main() {
  group('moproPageTitle route → branded key', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => Directory.systemTemp.path,
      );
      await EasyLocalization.ensureInitialized();
    });

    test('splash is brandless; known routes get the brand prefix', () {
      expect(moproPageTitle('/'), 'Mopro');
      expect(moproPageTitle('/splash'), 'Mopro');
      expect(moproPageTitle('/account'), 'Mopro · router_title.account');
      expect(moproPageTitle('/cart'), 'Mopro · router_title.cart');
      expect(moproPageTitle('/favorites'), 'Mopro · router_title.favorites');
      expect(moproPageTitle('/checkout'), 'Mopro · router_title.checkout');
      expect(moproPageTitle('/wallet'), 'Mopro · router_title.wallet');
      expect(moproPageTitle('/auth/login'), 'Mopro · router_title.login');
      expect(moproPageTitle('/account/security'), 'Mopro · router_title.security');
    });

    test('dynamic routes: name passthrough vs loading fallback vs namedArgs key',
        () {
      // No name → loading key; with name → the name is shown verbatim (no key).
      expect(moproPageTitle('/products/42'), 'Mopro · router_title.loading');
      expect(
        moproPageTitle('/products/42', name: 'Spor Ayakkabı'),
        'Mopro · Spor Ayakkabı',
      );
      expect(moproPageTitle('/categories/7'), 'Mopro · router_title.loading');
      expect(
        moproPageTitle('/categories/7', name: 'Elektronik'),
        'Mopro · Elektronik',
      );
      // Interpolated titles select a namedArgs key (substitution happens at
      // runtime once translations are loaded).
      expect(
        moproPageTitle('/orders/123', name: '123'),
        'Mopro · router_title.order_numbered',
      );
      expect(
        moproPageTitle('/returns/7', name: '7'),
        'Mopro · router_title.return_numbered',
      );
      expect(moproPageTitle('/returns/7'), 'Mopro · router_title.my_returns');
      expect(
        moproPageTitle('/search', name: 'ayakkabı'),
        'Mopro · router_title.search_query',
      );
    });

    test('unknown route → not-found key', () {
      expect(
        moproPageTitle('/totally/unknown'),
        'Mopro · router_title.not_found',
      );
    });
  });

  test('router_title keys resolve to the documented Turkish titles (verbatim)',
      () {
    final root = json.decode(
      File('assets/translations/tr-TR.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final rt = root['router_title'] as Map<String, dynamic>;
    // Spot-check the documented titles + the namedArgs placeholders.
    expect(rt['account'], 'Hesabım');
    expect(rt['cart'], 'Sepetim');
    expect(rt['favorites'], 'Favorilerim');
    expect(rt['checkout'], 'Ödeme');
    expect(rt['wallet'], 'Cüzdan');
    expect(rt['login'], 'Giriş');
    expect(rt['security'], 'Güvenlik');
    expect(rt['loading'], 'Yükleniyor…');
    expect(rt['my_returns'], 'İadelerim');
    expect(rt['order_numbered'], 'Sipariş #{n}');
    expect(rt['return_numbered'], 'İade #{n}');
    expect(rt['search_query'], '"{q}" araması');
    expect(rt['not_found'], 'Sayfa Bulunamadı');
  });
}
