import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/features/help/data/help_dto.dart';

abstract class HelpRepository {
  Future<List<HelpCategoryDto>> categories();
  Future<List<HelpArticleDto>> articles(String categorySlug);
  Future<HelpArticleDto> article(String slug);
  Future<List<HelpSearchResultDto>> search(String query);
  Future<TicketDto> createTicket(CreateTicketRequest req);
}

class HelpRepositoryImpl implements HelpRepository {
  const HelpRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<List<HelpCategoryDto>> categories() async {
    final resp = await _dio.get<Map<String, dynamic>>('/help/categories');
    return (resp.data!['categories'] as List<dynamic>)
        .map((e) => HelpCategoryDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<HelpArticleDto>> articles(String categorySlug) async {
    final resp = await _dio
        .get<Map<String, dynamic>>('/help/categories/$categorySlug/articles');
    return (resp.data!['articles'] as List<dynamic>)
        .map((e) => HelpArticleDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<HelpArticleDto> article(String slug) async {
    final resp = await _dio.get<Map<String, dynamic>>('/help/articles/$slug');
    return HelpArticleDto.fromJson(resp.data!['article'] as Map<String, dynamic>);
  }

  @override
  Future<List<HelpSearchResultDto>> search(String query) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/help/search',
      queryParameters: {'q': query},
    );
    return (resp.data!['results'] as List<dynamic>)
        .map((e) => HelpSearchResultDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<TicketDto> createTicket(CreateTicketRequest req) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/support/tickets',
      data: req.toJson(),
    );
    return TicketDto.fromJson(resp.data!['ticket'] as Map<String, dynamic>);
  }
}

final helpRepositoryProvider = Provider<HelpRepository>((ref) {
  return HelpRepositoryImpl(ref.watch(dioProvider));
});
