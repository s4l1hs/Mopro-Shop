import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';
import 'package:mopro/features/checkout/presentation/checkout_payment_screen.dart';

// PD-05: the payment step renders the taksit picker for the card method, the
// chips drive CheckoutState.installments, and the picker hides for non-card
// methods. i18n is keyed output in tests (bundle not loaded).

class _EmptyCartRepo implements CartRepository {
  @override
  Future<CartDto> getCart({String? coupon}) async => CartDto.empty();
  @override
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  }) async =>
      CartDto.empty();
  @override
  Future<CartDto> updateQty({required String lineId, required int qty}) async =>
      CartDto.empty();
  @override
  Future<void> removeLine({required String lineId}) async {}
  @override
  Future<void> clear() async {}
}

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [cartRepositoryProvider.overrideWithValue(_EmptyCartRepo())],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CheckoutPaymentScreen()),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('card method shows the installment picker with all options',
      (tester) async {
    await _pump(tester);

    expect(find.text('checkout.installments_title'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(kInstallmentOptions.length));
    // Default selection = single charge.
    final single = tester.widget<ChoiceChip>(find.byType(ChoiceChip).first);
    expect(single.selected, isTrue);
  });

  testWidgets('tapping a chip updates CheckoutState.installments',
      (tester) async {
    final container = await _pump(tester);

    // Chips render in kInstallmentOptions order: [1, 3, 6, 9, 12] → tap "6".
    await tester.tap(find.byType(ChoiceChip).at(2));
    await tester.pump();

    expect(container.read(checkoutControllerProvider).installments, 6);
    final chip6 = tester.widget<ChoiceChip>(find.byType(ChoiceChip).at(2));
    expect(chip6.selected, isTrue);
  });

  testWidgets('picker hides for non-card payment methods', (tester) async {
    final container = await _pump(tester);

    container
        .read(checkoutControllerProvider.notifier)
        .selectPaymentMethod('bank_transfer');
    await tester.pump();

    expect(find.text('checkout.installments_title'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
  });
}
