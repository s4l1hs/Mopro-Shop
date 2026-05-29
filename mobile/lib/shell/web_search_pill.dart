import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/providers/home_provider.dart';
import 'package:mopro/features/catalog/providers/recent_searches_provider.dart';
import 'package:mopro/shell/search_suggestions_dropdown.dart';

/// Real-text-input search pill used by `WebHeader` at `>=600` widths.
///
/// Replaces the tap-to-overlay `HeaderSearchBar` behavior with an inline
/// `TextField` + a `SearchSuggestionsDropdown` overlay anchored to the bottom
/// edge of the pill via `CompositedTransformFollower`.
///
/// Open triggers: TextField gains focus.
/// Close triggers: outside click, Escape key, route change, or focus moves to
/// a non-dropdown element.
class WebSearchPill extends ConsumerStatefulWidget {
  const WebSearchPill({super.key});

  @override
  ConsumerState<WebSearchPill> createState() => _WebSearchPillState();
}

class _WebSearchPillState extends ConsumerState<WebSearchPill>
    with RouteAware {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _overlayController = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _overlayController.show();
    } else {
      // Delay close to allow a row tap (which steals focus mid-frame) to
      // complete before the overlay disappears.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_focusNode.hasFocus) _overlayController.hide();
      });
    }
  }

  void _submit(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).add(q);
    _overlayController.hide();
    _focusNode.unfocus();
    context.push('/search?q=${Uri.encodeQueryComponent(q)}');
  }

  void _selectRecent(String q) {
    _controller.text = q;
    _submit(q);
  }

  void _selectTrending(String q) {
    _controller.text = q;
    _submit(q);
  }

  void _selectCategory(int categoryId) {
    _overlayController.hide();
    _focusNode.unfocus();
    context.go('/categories/$categoryId');
  }

  void _removeRecent(String q) {
    ref.read(recentSearchesProvider.notifier).remove(q);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (overlayContext) {
          return _DropdownOverlay(
            layerLink: _layerLink,
            anchorContext: context,
            onDismiss: () {
              _overlayController.hide();
              _focusNode.unfocus();
            },
            child: Consumer(
              builder: (context, ref, _) {
                final recent = ref.watch(recentSearchesProvider);
                final trending = ref.watch(trendingSearchesProvider);
                final categoriesState = ref.watch(categoriesProvider);
                return SearchSuggestionsDropdown(
                  recentSearches: recent,
                  trendingSearches: _asSnapshot(trending),
                  categories:
                      categoriesState.categories.valueOrNull ?? const [],
                  onSelectRecent: _selectRecent,
                  onSelectTrending: _selectTrending,
                  onSelectCategory: _selectCategory,
                  onRemoveRecent: _removeRecent,
                );
              },
            ),
          );
        },
        child: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape): _DismissIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _DismissIntent: CallbackAction<_DismissIntent>(
                onInvoke: (_) {
                  _overlayController.hide();
                  _focusNode.unfocus();
                  return null;
                },
              ),
            },
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(MoproTokens.radiusFull),
                border: Border.all(color: cs.outlineVariant),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onSubmitted: _submit,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'search.hint'.tr(),
                        hintStyle: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  if (_controller.text.isNotEmpty)
                    InkWell(
                      onTap: () {
                        _controller.clear();
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
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

class _DismissIntent extends Intent {
  const _DismissIntent();
}

/// Outer overlay shell. A full-viewport `GestureDetector` catches outside
/// clicks; a `CompositedTransformFollower` positions the dropdown directly
/// beneath the search pill anchor, matching its width.
class _DropdownOverlay extends StatelessWidget {
  const _DropdownOverlay({
    required this.layerLink,
    required this.anchorContext,
    required this.onDismiss,
    required this.child,
  });

  final LayerLink layerLink;
  final BuildContext anchorContext;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final width = anchorBox?.size.width ?? 480;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        Positioned(
          width: width,
          child: CompositedTransformFollower(
            link: layerLink,
            showWhenUnlinked: false,
            // Drop the panel directly beneath the pill (40dp tall) with 6dp
            // breathing room.
            offset: const Offset(0, 46),
            child: child,
          ),
        ),
      ],
    );
  }
}
