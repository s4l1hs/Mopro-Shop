import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/account/current_user_provider.dart';
import 'package:mopro/features/seller/user_is_seller_provider.dart';
import 'package:mopro_api/mopro_api.dart';

SellerBinding _binding() => SellerBinding(
      sellerId: 1,
      sellerSlug: 'acme-store',
      sellerName: 'Acme Store',
      role: SellerBindingRoleEnum.owner,
    );

CurrentUser _user({SellerBinding? binding}) =>
    CurrentUser(id: 7, displayName: 'Test', sellerBinding: binding);

Future<ProviderContainer> _container(CurrentUser? user) async {
  final c = ProviderContainer(
    overrides: [currentUserProvider.overrideWith((ref) async => user)],
  );
  await c.read(currentUserProvider.future);
  return c;
}

void main() {
  test('guest (null user) → not a seller', () async {
    final c = await _container(null);
    addTearDown(c.dispose);
    expect(c.read(userIsSellerProvider), isFalse);
    expect(c.read(currentSellerBindingProvider), isNull);
  });

  test('authed non-seller (null binding) → not a seller', () async {
    final c = await _container(_user());
    addTearDown(c.dispose);
    expect(c.read(userIsSellerProvider), isFalse);
    expect(c.read(currentSellerBindingProvider), isNull);
  });

  test('seller-bound user → is a seller + binding exposed', () async {
    final c = await _container(_user(binding: _binding()));
    addTearDown(c.dispose);
    expect(c.read(userIsSellerProvider), isTrue);
    final b = c.read(currentSellerBindingProvider);
    expect(b?.sellerSlug, 'acme-store');
    expect(b?.role, SellerBindingRoleEnum.owner);
  });

  test('rebuilds when the upstream user changes', () async {
    // Drive currentUserProvider from a controllable StateProvider so flipping
    // it triggers proper invalidation of the derived provider.
    final userState = StateProvider<CurrentUser?>((_) => _user());
    final c = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith((ref) async => ref.watch(userState)),
      ],
    );
    addTearDown(c.dispose);
    final emitted = <bool>[];
    c.listen(
      userIsSellerProvider,
      (_, next) => emitted.add(next),
      fireImmediately: true,
    );

    await c.read(currentUserProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(emitted.last, isFalse);

    // Flip the upstream to a seller-bound user.
    c.read(userState.notifier).state = _user(binding: _binding());
    await c.read(currentUserProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect(emitted.last, isTrue);
  });
}
