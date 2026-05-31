import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/order/data/order_dto.dart';

void main() {
  group('OrderDto.fromJson', () {
    test('parses flat order object (list item shape)', () {
      final o = OrderDto.fromJson({
        'id': 5,
        'user_id': 1,
        'status': 'delivered',
        'total_minor': 9900,
        'currency': 'TRY',
        'created_at': '2026-05-01T00:00:00Z',
      });
      expect(o.id, 5);
      expect(o.status, OrderStatus.delivered);
      expect(o.actions, isNull);
      expect(o.refund, isNull);
    });

    test('parses wrapped detail envelope with actions + refund', () {
      final o = OrderDto.fromJson({
        'order': {
          'id': 7,
          'user_id': 1,
          'status': 'cancelled',
          'total_minor': 12500,
          'currency': 'TRY',
          'created_at': '2026-05-01T00:00:00Z',
        },
        'items': const <Map<String, dynamic>>[],
        'actions': {
          'canCancel': false,
          'canReturn': true,
          'returnableUntil': '2026-06-30T23:59:59Z',
          'returnableItems': [
            {'itemId': 567, 'maxQuantity': 2},
          ],
        },
        'refund': {
          'amountMinor': 12500,
          'currency': 'TRY',
          'method': 'original_payment',
          'status': 'pending',
          'estimatedAt': '2026-06-10T00:00:00Z',
        },
      });
      expect(o.id, 7);
      expect(o.actions, isNotNull);
      expect(o.actions!.canReturn, isTrue);
      expect(o.actions!.maxQuantityFor(567), 2);
      expect(o.actions!.maxQuantityFor(999), 0);
      expect(o.refund!.amountMinor, 12500);
      expect(o.refund!.status, RefundStatus.pending);
      expect(o.refund!.isWallet, isFalse);
    });

    test('copyWith preserves refund/actions unless overridden', () {
      final base = OrderDto(
        id: 1,
        userId: 1,
        status: OrderStatus.paid,
        totalMinor: 100,
        currency: 'TRY',
        createdAt: DateTime(2026),
        actions: const OrderActions(canCancel: true),
      );
      final flipped = base.copyWith(status: OrderStatus.cancelled);
      expect(flipped.status, OrderStatus.cancelled);
      expect(flipped.actions!.canCancel, isTrue);
    });
  });
}
