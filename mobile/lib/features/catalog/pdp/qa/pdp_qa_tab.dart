import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_provider.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_submission.dart';
import 'package:mopro/features/catalog/pdp/qa/question_row.dart';

/// The product detail page "Sorular" tab: an "Soru Sor" CTA, a sort dropdown,
/// the paginated question list (tap → question detail), and a "Daha fazla"
/// pagination button. [scrollable] mirrors the reviews tab: own ListView inside
/// the narrow TabBarView, a Column inside the wide layout's outer scroll.
class PdpQaTab extends ConsumerWidget {
  const PdpQaTab({required this.productId, this.scrollable = true, super.key});

  final int productId;
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final state = ref.watch(questionsProvider(productId));
    final notifier = ref.read(questionsProvider(productId).notifier);

    if (state.loading && state.items.isEmpty) {
      return _wrap(const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ]);
    }

    if (state.error != null && state.items.isEmpty) {
      return _wrap([
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'qa.load_error'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: notifier.refresh,
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      ]);
    }

    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              'qa.header'.tr(namedArgs: {'count': '${state.total}'}),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (state.items.isNotEmpty)
            _SortMenu(current: state.sort, onSelected: notifier.setSort),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => openAskQuestion(context, ref, productId: productId),
          icon: const Icon(Icons.add_comment_outlined, size: 18),
          label: Text('qa.ask_cta'.tr()),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.primary,
            side: BorderSide(color: cs.primary),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (state.items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'qa.empty'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        )
      else
        for (final (i, q) in state.items.indexed) ...[
          if (i > 0) const Divider(height: 1),
          QuestionRow(
            question: q,
            onTap: () =>
                context.go('/products/$productId/questions/${q.id}'),
          ),
        ],
      if (state.hasMore) ...[
        const SizedBox(height: 8),
        _LoadMoreButton(loading: state.loadingMore, onTap: notifier.loadMore),
      ],
    ];

    return _wrap(children);
  }

  Widget _wrap(List<Widget> children) {
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 16);
    if (scrollable) {
      return ListView(padding: padding, children: children);
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.current, required this.onSelected});

  final QuestionSort current;
  final ValueChanged<QuestionSort> onSelected;

  static String _key(QuestionSort s) => switch (s) {
        QuestionSort.newest => 'qa.sort_newest',
        QuestionSort.mostAnswered => 'qa.sort_most_answered',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<QuestionSort>(
      initialValue: current,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final s in QuestionSort.values)
          PopupMenuItem<QuestionSort>(value: s, child: Text(_key(s).tr())),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _key(current).tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Icon(Icons.arrow_drop_down, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: loading ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.primary),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: loading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              )
            : Text('qa.load_more'.tr()),
      ),
    );
  }
}
