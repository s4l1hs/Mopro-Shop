import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/help/data/help_dto.dart';
import 'package:mopro/features/help/data/help_repository.dart';
import 'package:mopro/features/order/application/orders_provider.dart';

/// Shared fake HelpRepository for help widget/screen tests.
class FakeHelpRepo implements HelpRepository {
  FakeHelpRepo({
    this.cats = const [],
    this.arts = const [],
    this.one,
    this.results = const [],
    this.createThrows = false,
  });

  final List<HelpCategoryDto> cats;
  final List<HelpArticleDto> arts;
  final HelpArticleDto? one;
  final List<HelpSearchResultDto> results;
  final bool createThrows;
  CreateTicketRequest? created;

  @override
  Future<List<HelpCategoryDto>> categories() async => cats;
  @override
  Future<List<HelpArticleDto>> articles(String categorySlug) async => arts;
  @override
  Future<HelpArticleDto> article(String slug) async =>
      one ?? HelpArticleDto(slug: slug, title: 'T', body: '## H\n\nBody');
  @override
  Future<List<HelpSearchResultDto>> search(String query) async => results;
  @override
  Future<TicketDto> createTicket(CreateTicketRequest req) async {
    created = req;
    if (createThrows) throw Exception('boom');
    return const TicketDto(id: 555, status: 'open');
  }
}

/// Empty orders notifier so ContactFormContent's ordersProvider read is inert.
class EmptyOrders extends OrdersNotifier {
  @override
  OrdersState build() => const OrdersState(orders: AsyncData([]));
}

HelpCategoryDto cat(String slug, String title, int n) =>
    HelpCategoryDto(slug: slug, title: title, articleCount: n, iconName: 'person_outline');
