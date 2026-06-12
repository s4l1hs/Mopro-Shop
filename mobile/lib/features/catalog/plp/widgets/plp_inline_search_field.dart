import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/catalog/providers/filtered_products_provider.dart';

/// PLP-10: inline "search in this category" field. Submit writes the query to
/// `plpInlineQueryProvider(plpKey)`; the products notifier watches it and swaps
/// the source to the category-scoped `/search` (filters + pagination intact).
/// The clear button (shown while a query is active) restores the plain listing.
class PlpInlineSearchField extends ConsumerStatefulWidget {
  const PlpInlineSearchField({required this.plpKey, super.key});

  final String plpKey;

  @override
  ConsumerState<PlpInlineSearchField> createState() =>
      _PlpInlineSearchFieldState();
}

class _PlpInlineSearchFieldState extends ConsumerState<PlpInlineSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      // Survive screen rebuilds/navigation: seed from the provider state.
      text: ref.read(plpInlineQueryProvider(widget.plpKey)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String q) =>
      ref.read(plpInlineQueryProvider(widget.plpKey).notifier).state = q.trim();

  void _clear() {
    _controller.clear();
    _submit('');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = ref.watch(plpInlineQueryProvider(widget.plpKey)).isNotEmpty;
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'plp.search_in_category'.tr(),
          prefixIcon: Icon(Icons.search, size: 20, color: cs.onSurfaceVariant),
          suffixIcon: active
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _clear,
                )
              : null,
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
