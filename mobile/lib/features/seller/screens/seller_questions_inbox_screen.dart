import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/utils/relative_time.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';
import 'package:mopro/features/seller/providers/seller_questions_provider.dart';

/// `/seller/questions` — seller Q&A inbox with an unanswered/all filter.
class SellerQuestionsInboxScreen extends ConsumerStatefulWidget {
  const SellerQuestionsInboxScreen({this.initialUnanswered = true, super.key});

  final bool initialUnanswered;

  @override
  ConsumerState<SellerQuestionsInboxScreen> createState() =>
      _SellerQuestionsInboxScreenState();
}

class _SellerQuestionsInboxScreenState
    extends ConsumerState<SellerQuestionsInboxScreen> {
  late bool _unanswered = widget.initialUnanswered;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sellerQuestionsInboxProvider(_unanswered));
    final notifier = ref.read(sellerQuestionsInboxProvider(_unanswered).notifier);

    final body = state.loading
        ? const Center(child: CircularProgressIndicator())
        : (state.error != null && state.items.isEmpty)
            ? Center(child: Text('seller.error_generic'.tr()))
            : state.items.isEmpty
                ? Center(
                    child: Text(
                      _unanswered
                          ? 'seller.questions_empty_unanswered'.tr()
                          : 'seller.questions_empty_all'.tr(),
                    ),
                  )
                : _list(state, notifier);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text('seller.filter_unanswered'.tr()),
                selected: _unanswered,
                onSelected: (_) => setState(() => _unanswered = true),
              ),
              ChoiceChip(
                label: Text('seller.filter_all'.tr()),
                selected: !_unanswered,
                onSelected: (_) => setState(() => _unanswered = false),
              ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text('seller.questions_title'.tr())),
      body: context.isMobile ? content : CenteredContentColumn(child: content),
    );
  }

  Widget _list(SellerQuestionsState state, SellerQuestionsNotifier notifier) {
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: state.items.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 16),
        itemBuilder: (context, i) {
          if (i == state.items.length) {
            if (!state.hasMore) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: state.loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: notifier.loadMore,
                        child: Text('seller.load_more'.tr()),
                      ),
              ),
            );
          }
          return _QuestionRow(item: state.items[i]);
        },
      ),
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.item});
  final SellerQuestion item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        item.body,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            _StatusChip(answered: item.isAnswered),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${'seller.customer_label'.tr(namedArgs: {'id': '${item.userId}'})} · ${relativeTime(item.createdAt)}',
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/seller/questions/${item.id}', extra: item),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.answered});
  final bool answered;
  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        answered ? 'seller.q_answered'.tr() : 'seller.q_awaiting'.tr(),
      ),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
