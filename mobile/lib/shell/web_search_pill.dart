import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/anchored_overlay_panel.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/providers/home_provider.dart';
import 'package:mopro/features/catalog/providers/recent_searches_provider.dart';
import 'package:mopro/features/catalog/providers/search_suggestions_provider.dart';
import 'package:mopro/shell/search_suggestions_dropdown.dart';

/// Real-text-input search pill used by `WebHeader` at `>=600` widths.
///
/// The pill is a `TextField`; the `SearchSuggestionsDropdown` is rendered
/// inside an `AnchoredOverlayPanel` anchored to the pill's bottom edge with
/// `matchTriggerWidth: true` so the dropdown width tracks the pill.
///
/// Session 4b migration: previously this widget owned its own `OverlayPortal`,
/// `CompositedTransformFollower`, `Shortcuts`/`Actions` for Escape, and the
/// outside-click dismisser. All of that is now provided by
/// `AnchoredOverlayPanel`; this widget only configures it (openOnFocus, not
/// openOnTap — taps go through to the TextField so the cursor lands there
/// naturally) and renders the inner content.
class WebSearchPill extends ConsumerStatefulWidget {
  const WebSearchPill({super.key});

  @override
  ConsumerState<WebSearchPill> createState() => _WebSearchPillState();
}

class _WebSearchPillState extends ConsumerState<WebSearchPill> {
  final _controller = TextEditingController();
  final _textFocusNode = FocusNode();
  Timer? _debounce;

  // Matches the rest of the app's 300 ms search debounce (SearchNotifier).
  static const _debounceMs = 300;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  /// Debounce the typed text into `searchSuggestQueryProvider` so the dropdown
  /// fetches brand/product suggestions only after the user pauses (SE-06). An
  /// empty field resets immediately so the recent/trending sections return.
  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      ref.read(searchSuggestQueryProvider.notifier).state = '';
      return;
    }
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (!mounted) return;
      ref.read(searchSuggestQueryProvider.notifier).state = q;
    });
  }

  void _submit(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).add(q);
    _textFocusNode.unfocus();
    context.push('/search?q=${Uri.encodeQueryComponent(q)}');
  }

  void _selectRecent(String q, VoidCallback close) {
    _controller.text = q;
    close();
    _submit(q);
  }

  void _selectTrending(String q, VoidCallback close) {
    _controller.text = q;
    close();
    _submit(q);
  }

  void _selectCategory(int categoryId, VoidCallback close) {
    close();
    _textFocusNode.unfocus();
    context.go('/categories/$categoryId');
  }

  // SE-06: a brand suggestion lands on the brand-filtered listing (a search for
  // the brand name); a product suggestion goes straight to its PDP.
  void _selectBrand(String name, VoidCallback close) {
    _controller.text = name;
    close();
    _submit(name);
  }

  void _selectProduct(int productId, VoidCallback close) {
    close();
    _textFocusNode.unfocus();
    context.push('/products/$productId');
  }

  void _removeRecent(String q) {
    ref.read(recentSearchesProvider.notifier).remove(q);
  }

  void _clear() {
    setState(_controller.clear);
    _debounce?.cancel();
    ref.read(searchSuggestQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnchoredOverlayPanel(
      // The TextField inside the trigger handles its own taps; we just need
      // the panel to open when the TextField gains focus.
      openOnHover: false,
      openOnTap: false,
      matchTriggerWidth: true,
      trigger: _PillBody(
        controller: _controller,
        focusNode: _textFocusNode,
        onSubmitted: _submit,
        onChanged: _onChanged,
        onClear: _clear,
        colorScheme: cs,
      ),
      panelBuilder: (panelContext, close) {
        return Consumer(
          builder: (context, ref, _) {
            final recent = ref.watch(recentSearchesProvider);
            final trending = ref.watch(trendingSearchesProvider);
            final categoriesState = ref.watch(categoriesProvider);

            // SE-06: structured suggestions for the active (debounced) query.
            final query = ref.watch(searchSuggestQueryProvider);
            final suggestions = query.isEmpty
                ? null
                : ref.watch(searchSuggestionsProvider(query));
            return SearchSuggestionsDropdown(
              recentSearches: recent,
              trendingSearches: _asSnapshot(trending),
              categories:
                  categoriesState.categories.valueOrNull ?? const [],
              brandSuggestions:
                  suggestions?.valueOrNull?.brands ?? const [],
              productSuggestions:
                  suggestions?.valueOrNull?.products ?? const [],
              suggestionsLoading: suggestions?.isLoading ?? false,
              onSelectRecent: (q) => _selectRecent(q, close),
              onSelectTrending: (q) => _selectTrending(q, close),
              onSelectCategory: (id) => _selectCategory(id, close),
              onSelectBrand: (name) => _selectBrand(name, close),
              onSelectProduct: (id) => _selectProduct(id, close),
              onRemoveRecent: _removeRecent,
            );
          },
        );
      },
    );
  }
}

class _PillBody extends StatelessWidget {
  const _PillBody({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onChanged,
    required this.onClear,
    required this.colorScheme,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(MoproTokens.radiusFull),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'search.hint'.tr(),
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wrap an `AsyncValue<List<String>>` in an `AsyncSnapshot` shape so the
/// dropdown widget can render skeleton/data branches without knowing about
/// Riverpod.
AsyncSnapshot<List<String>> _asSnapshot(AsyncValue<List<String>> v) {
  return v.when(
    loading: () => const AsyncSnapshot<List<String>>.waiting(),
    error: (_, __) => const AsyncSnapshot<List<String>>.withData(
      ConnectionState.done,
      <String>[],
    ),
    data: (d) => AsyncSnapshot<List<String>>.withData(
      ConnectionState.done,
      d,
    ),
  );
}
