import 'package:easy_localization/easy_localization.dart';

class HelpCategoryDto {
  const HelpCategoryDto({
    required this.slug,
    required this.title,
    required this.articleCount,
    this.iconName,
  });

  factory HelpCategoryDto.fromJson(Map<String, dynamic> json) => HelpCategoryDto(
        slug: json['slug'] as String,
        title: (json['title'] as String?) ?? '',
        articleCount: (json['article_count'] as num?)?.toInt() ?? 0,
        iconName: json['icon_name'] as String?,
      );

  final String slug;
  final String title;
  final int articleCount;
  final String? iconName;
}

class HelpArticleDto {
  const HelpArticleDto({
    required this.slug,
    required this.title,
    this.body = '',
    this.categorySlug,
  });

  factory HelpArticleDto.fromJson(Map<String, dynamic> json) => HelpArticleDto(
        slug: json['slug'] as String,
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        categorySlug: json['category_slug'] as String?,
      );

  final String slug;
  final String title;
  final String body;
  final String? categorySlug;
}

class HelpSearchResultDto {
  const HelpSearchResultDto({
    required this.slug,
    required this.title,
    required this.snippet,
    required this.categorySlug,
  });

  factory HelpSearchResultDto.fromJson(Map<String, dynamic> json) =>
      HelpSearchResultDto(
        slug: json['slug'] as String,
        title: (json['title'] as String?) ?? '',
        snippet: (json['snippet'] as String?) ?? '',
        categorySlug: (json['category_slug'] as String?) ?? '',
      );

  final String slug;
  final String title;
  final String snippet;
  final String categorySlug;
}

/// Contact-form ticket categories (mirror the backend enum).
class TicketCategory {
  static const orderIssue = 'order_issue';
  static const payment = 'payment';
  static const returns = 'returns';
  static const account = 'account';
  static const other = 'other';

  static const all = [orderIssue, payment, returns, account, other];

  static String label(String code) => 'help.ticket_cat_$code'.tr();
}

class CreateTicketRequest {
  const CreateTicketRequest({
    required this.email,
    required this.subject,
    required this.body,
    required this.category,
    this.relatedOrderId,
    this.relatedArticleSlug,
  });

  final String email;
  final String subject;
  final String body;
  final String category;
  final int? relatedOrderId;
  final String? relatedArticleSlug;

  Map<String, dynamic> toJson() => {
        'email': email,
        'subject': subject,
        'body': body,
        'category': category,
        if (relatedOrderId != null) 'related_order_id': relatedOrderId,
        if (relatedArticleSlug != null && relatedArticleSlug!.isNotEmpty)
          'related_article_slug': relatedArticleSlug,
      };
}

class TicketDto {
  const TicketDto({required this.id, required this.status});

  factory TicketDto.fromJson(Map<String, dynamic> json) => TicketDto(
        id: (json['id'] as num).toInt(),
        status: (json['status'] as String?) ?? 'open',
      );

  final int id;
  final String status;
}
