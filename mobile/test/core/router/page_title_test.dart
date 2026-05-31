import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/router/app_router.dart';

void main() {
  group('moproPageTitle', () {
    test('static routes resolve to their documented titles', () {
      const cases = {
        '/': 'Mopro',
        '/splash': 'Mopro',
        '/categories': 'Mopro · Kategoriler',
        '/cart': 'Mopro · Sepetim',
        '/favorites': 'Mopro · Favorilerim',
        '/checkout': 'Mopro · Ödeme',
        '/checkout/result': 'Mopro · Sipariş Sonucu',
        '/orders': 'Mopro · Siparişlerim',
        '/orders/123/return': 'Mopro · İade Talebi',
        '/returns': 'Mopro · İadelerim',
        '/wallet': 'Mopro · Cüzdan',
        '/wallet/plans/9': 'Mopro · Kampanya Detayı',
        '/profile/addresses': 'Mopro · Adreslerim',
        '/profile/addresses/new': 'Mopro · Yeni Adres',
        '/profile/addresses/5/edit': 'Mopro · Adresi Düzenle',
        '/account': 'Mopro · Hesabım',
        '/account/profile': 'Mopro · Profilim',
        '/account/security': 'Mopro · Güvenlik',
        '/account/cards': 'Mopro · Kartlarım',
        '/account/notifications': 'Mopro · Bildirimler',
        '/auth/login': 'Mopro · Giriş',
        '/auth/register': 'Mopro · Üye Ol',
        '/auth/verify-email': 'Mopro · E-posta Doğrulama',
        '/auth/forgot-password': 'Mopro · Şifre Sıfırlama',
        '/auth/mfa': 'Mopro · İki Faktör',
        '/auth/profile': 'Mopro · Profil Tamamlama',
      };
      for (final entry in cases.entries) {
        expect(moproPageTitle(entry.key), entry.value, reason: entry.key);
      }
    });

    test('dynamic routes use the name or fall back to loading', () {
      expect(moproPageTitle('/products/42'), 'Mopro · Yükleniyor…');
      expect(
        moproPageTitle('/products/42', name: 'Spor Ayakkabı'),
        'Mopro · Spor Ayakkabı',
      );
      expect(moproPageTitle('/categories/7'), 'Mopro · Yükleniyor…');
      expect(
        moproPageTitle('/categories/7', name: 'Elektronik'),
        'Mopro · Elektronik',
      );
      expect(moproPageTitle('/orders/123', name: '123'), 'Mopro · Sipariş #123');
      expect(moproPageTitle('/returns/7', name: '7'), 'Mopro · İade #7');
      expect(moproPageTitle('/returns/7'), 'Mopro · İadelerim');
      expect(moproPageTitle('/search'), 'Mopro · Arama');
      expect(
        moproPageTitle('/search', name: 'ayakkabı'),
        'Mopro · "ayakkabı" araması',
      );
    });

    test('unknown route resolves to not-found', () {
      expect(moproPageTitle('/totally/unknown'), 'Mopro · Sayfa Bulunamadı');
    });
  });
}
