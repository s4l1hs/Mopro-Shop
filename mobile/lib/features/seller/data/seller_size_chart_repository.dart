import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';

/// Seller-entered size charts (docs/internal/seller-size-charts.md). Hand-written
/// raw-Dio over the role-gated /seller/size-charts* endpoints — the seller console
/// convention (the writes are not in the OpenAPI spec).

/// One (size, measurement) range, in millimetres (mirrors the backend row shape).
class SizeChartRow {
  const SizeChartRow({
    required this.sizeLabel,
    required this.sortRank,
    required this.measurement,
    required this.minMm,
    required this.maxMm,
  });

  factory SizeChartRow.fromJson(Map<String, dynamic> j) => SizeChartRow(
        sizeLabel: (j['size_label'] as String?) ?? '',
        sortRank: (j['sort_rank'] as num?)?.toInt() ?? 0,
        measurement: (j['measurement'] as String?) ?? '',
        minMm: (j['min_mm'] as num?)?.toInt() ?? 0,
        maxMm: (j['max_mm'] as num?)?.toInt() ?? 0,
      );

  final String sizeLabel;
  final int sortRank;
  final String measurement; // chest | waist | hip
  final int minMm;
  final int maxMm;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'size_label': sizeLabel,
        'sort_rank': sortRank,
        'measurement': measurement,
        'min_mm': minMm,
        'max_mm': maxMm,
      };
}

/// A seller-authored chart (header + rows).
class SellerSizeChart {
  const SellerSizeChart({
    required this.id,
    required this.name,
    required this.garmentType,
    required this.gender,
    required this.sizeSystem,
    required this.source,
    required this.rows,
  });

  factory SellerSizeChart.fromJson(Map<String, dynamic> j) => SellerSizeChart(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] as String?) ?? '',
        garmentType: (j['garment_type'] as String?) ?? 'top',
        gender: (j['gender'] as String?) ?? 'female',
        sizeSystem: (j['size_system'] as String?) ?? 'alpha',
        source: (j['source'] as String?) ?? 'seller',
        rows: ((j['rows'] as List<dynamic>?) ?? const [])
            .map((e) => SizeChartRow.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final int id;
  final String name;
  final String garmentType; // top|bottom|dress|skirt|outerwear
  final String gender; // female|male
  final String sizeSystem; // alpha|eu
  final String source; // seller|standard
  final List<SizeChartRow> rows;

  /// Body for create/update (the server sets id/seller_id/source).
  Map<String, dynamic> toCreateJson() => <String, dynamic>{
        'name': name,
        'garment_type': garmentType,
        'gender': gender,
        'size_system': sizeSystem,
        'rows': rows.map((r) => r.toJson()).toList(),
      };
}

/// Thrown on a 422 from a chart write — carries the server's inline reason
/// (which size/dimension failed monotonicity/bounds/etc.) for the form to show.
class SizeChartValidationException implements Exception {
  const SizeChartValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SellerSizeChartRepository {
  SellerSizeChartRepository(this._dio);
  final Dio _dio;

  Future<List<SellerSizeChart>> listCharts() async {
    final resp = await _dio.get<Map<String, dynamic>>('/seller/size-charts');
    final data = resp.data ?? const {};
    return ((data['charts'] as List<dynamic>?) ?? const [])
        .map((e) => SellerSizeChart.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// EN baseline rows for the copy-from-standard prefill. Null when the baseline
  /// has no such combination (404).
  Future<SellerSizeChart?> fetchStandard({
    required String garmentType,
    required String gender,
    String sizeSystem = 'alpha',
  }) async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/seller/size-charts/standard',
        queryParameters: <String, dynamic>{
          'garment_type': garmentType,
          'gender': gender,
          'size_system': sizeSystem,
        },
      );
      final chart = resp.data?['chart'] as Map<String, dynamic>?;
      return chart == null ? null : SellerSizeChart.fromJson(chart);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<int> createChart(SellerSizeChart chart) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/seller/size-charts',
        data: chart.toCreateJson(),
      );
      return (resp.data?['id'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      _throwIfValidation(e);
      rethrow;
    }
  }

  Future<void> updateChart(int id, SellerSizeChart chart) async {
    try {
      await _dio.put<Map<String, dynamic>>(
        '/seller/size-charts/$id',
        data: chart.toCreateJson(),
      );
    } on DioException catch (e) {
      _throwIfValidation(e);
      rethrow;
    }
  }

  Future<void> attachToProduct(int productId, int chartId) =>
      _dio.post<Map<String, dynamic>>(
        '/seller/products/$productId/size-chart',
        data: <String, dynamic>{'chart_id': chartId},
      );

  /// A 422 carries the server's inline validation reason → surface it typed.
  void _throwIfValidation(DioException e) {
    if (e.response?.statusCode == 422) {
      final msg = (e.response?.data is Map)
          ? (e.response?.data as Map)['error']?.toString()
          : null;
      throw SizeChartValidationException(msg ?? 'invalid size chart');
    }
  }
}

final sellerSizeChartRepositoryProvider = Provider<SellerSizeChartRepository>(
  (ref) => SellerSizeChartRepository(ref.watch(dioProvider)),
);

/// The seller's charts (autoDispose → refetch on next visit).
final AutoDisposeFutureProvider<List<SellerSizeChart>> sellerSizeChartsProvider =
    FutureProvider.autoDispose<List<SellerSizeChart>>((ref) {
  return ref.watch(sellerSizeChartRepositoryProvider).listCharts();
});
