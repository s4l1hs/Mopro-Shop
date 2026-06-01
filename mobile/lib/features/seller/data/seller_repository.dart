import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';

/// A return in the seller inbox (GET /seller/returns). Header-only — 5a ships
/// no seller-scoped per-item detail endpoint, so the detail screen renders from
/// these fields + the approve/reject actions.
class SellerReturn {
  const SellerReturn({
    required this.id,
    required this.orderId,
    required this.status,
    required this.reason,
    required this.description,
    required this.refundAmountMinor,
    required this.refundCurrency,
    required this.createdAt,
  });

  factory SellerReturn.fromJson(Map<String, dynamic> j) => SellerReturn(
        id: (j['id'] as num).toInt(),
        orderId: (j['order_id'] as num?)?.toInt() ?? 0,
        status: (j['status'] as String?) ?? 'submitted',
        reason: (j['reason'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        refundAmountMinor: (j['refund_amount_minor'] as num?)?.toInt() ?? 0,
        refundCurrency: (j['refund_currency'] as String?) ?? 'TRY',
        createdAt: DateTime.tryParse((j['created_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int id;
  final int orderId;
  final String status; // submitted | approved | rejected | refunded
  final String reason;
  final String description;
  final int refundAmountMinor;
  final String refundCurrency;
  final DateTime createdAt;

  SellerReturn copyWith({String? status}) => SellerReturn(
        id: id,
        orderId: orderId,
        status: status ?? this.status,
        reason: reason,
        description: description,
        refundAmountMinor: refundAmountMinor,
        refundCurrency: refundCurrency,
        createdAt: createdAt,
      );
}

/// A question in the seller inbox (GET /seller/questions).
class SellerQuestion {
  const SellerQuestion({
    required this.id,
    required this.productId,
    required this.userId,
    required this.body,
    required this.answerCount,
    required this.createdAt,
  });

  factory SellerQuestion.fromJson(Map<String, dynamic> j) => SellerQuestion(
        id: (j['id'] as num).toInt(),
        productId: (j['product_id'] as num?)?.toInt() ?? 0,
        userId: (j['user_id'] as num?)?.toInt() ?? 0,
        body: (j['body'] as String?) ?? '',
        answerCount: (j['answer_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse((j['created_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int id;
  final int productId;
  final int userId;
  final String body;
  final int answerCount;
  final DateTime createdAt;

  bool get isAnswered => answerCount > 0;
}

/// Thin wrapper over the role-gated /seller/* endpoints (5a backend).
class SellerRepository {
  SellerRepository(this._dio);
  final Dio _dio;

  Future<(List<SellerReturn>, bool)> listReturns({
    required String status,
    int limit = 20,
    int offset = 0,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/seller/returns',
      queryParameters: <String, dynamic>{
        if (status.isNotEmpty) 'status': status,
        'limit': limit,
        'offset': offset,
      },
    );
    final data = resp.data ?? const {};
    final items = ((data['data'] as List<dynamic>?) ?? const [])
        .map((e) => SellerReturn.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items, (data['hasMore'] as bool?) ?? false);
  }

  Future<void> approveReturn(int id) =>
      _dio.post<Map<String, dynamic>>('/seller/returns/$id/approve');

  Future<void> rejectReturn(int id, String reasonCode, String? note) =>
      _dio.post<Map<String, dynamic>>(
        '/seller/returns/$id/reject',
        data: <String, dynamic>{
          'reason_code': reasonCode,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );

  Future<(List<SellerQuestion>, int, bool)> listQuestions({
    required bool unanswered,
    int page = 1,
    int pageSize = 20,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/seller/questions',
      queryParameters: <String, dynamic>{
        if (unanswered) 'unanswered': 'true',
        'page': page,
        'pageSize': pageSize,
      },
    );
    final data = resp.data ?? const {};
    final items = ((data['data'] as List<dynamic>?) ?? const [])
        .map((e) => SellerQuestion.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (data['total'] as num?)?.toInt() ?? items.length;
    return (items, total, (data['hasMore'] as bool?) ?? false);
  }
}

final sellerRepositoryProvider =
    Provider<SellerRepository>((ref) => SellerRepository(ref.watch(dioProvider)));
