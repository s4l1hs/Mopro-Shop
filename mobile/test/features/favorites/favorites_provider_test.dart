import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FAV-07: the price-at-favorite snapshot the favorites surface compares the
/// live price against for the "fiyatı düştü" cue.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  test('favoriting with a price records the snapshot', () async {
    final prefs = await freshPrefs();
    final n = FavoritesNotifier(prefs);

    n.toggle(7, priceMinor: 25000);

    expect(n.isFavorite(7), isTrue);
    expect(n.priceAtFavorite(7), 25000);
  });

  test('un-favoriting clears the snapshot (fresh baseline on re-add)', () async {
    final prefs = await freshPrefs();
    final n = FavoritesNotifier(prefs);

    n.toggle(7, priceMinor: 25000);
    n.toggle(7); // remove
    expect(n.priceAtFavorite(7), isNull);

    n.toggle(7, priceMinor: 18000); // re-add at a new price
    expect(n.priceAtFavorite(7), 18000);
  });

  test('favoriting without a price stores no snapshot (no fabricated baseline)',
      () async {
    final prefs = await freshPrefs();
    final n = FavoritesNotifier(prefs);

    n.toggle(7); // e.g. legacy call site with no price in hand

    expect(n.isFavorite(7), isTrue);
    expect(n.priceAtFavorite(7), isNull);
  });

  test('snapshots survive a reload from SharedPreferences', () async {
    final prefs = await freshPrefs();
    FavoritesNotifier(prefs)
      ..toggle(1, priceMinor: 5000)
      ..toggle(2, priceMinor: 9000);

    // A second notifier over the same prefs hydrates the persisted map.
    final reloaded = FavoritesNotifier(prefs);
    expect(reloaded.priceAtFavorite(1), 5000);
    expect(reloaded.priceAtFavorite(2), 9000);
    expect(reloaded.isFavorite(1), isTrue);
  });

  test('mergeServer (FAV-02 down-sync) does not invent snapshots', () async {
    final prefs = await freshPrefs();
    final n = FavoritesNotifier(prefs)..mergeServer([3, 4]);

    expect(n.isFavorite(3), isTrue);
    expect(n.priceAtFavorite(3), isNull); // server carries only IDs
  });
}
