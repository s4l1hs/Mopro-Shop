import 'package:mopro/features/order/data/order_repository.dart';
import 'package:mopro/features/order/data/return_dto.dart';

/// Default no-op implementations of the returns surface of [OrderRepository],
/// so existing fake repos only override what their test exercises.
mixin OrderReturnsStub implements OrderRepository {
  @override
  Future<ReturnDetailDto> createReturn(CreateReturnRequest req) async =>
      ReturnDetailDto(
        id: 1,
        orderId: req.orderId,
        status: ReturnLifecycle.pending,
        reason: req.reason,
        description: req.description,
        createdAt: DateTime(2026),
        items: req.items,
      );

  @override
  Future<List<ReturnListItemDto>> listReturns({int limit = 20, int offset = 0}) async => const [];

  @override
  Future<ReturnDetailDto> getReturn(int id) async => ReturnDetailDto(
        id: id,
        orderId: 1,
        status: ReturnLifecycle.pending,
        reason: ReturnReason.damaged,
        createdAt: DateTime(2026),
      );
}
