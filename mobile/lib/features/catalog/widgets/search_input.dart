import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class SearchInput extends StatefulWidget {
  const SearchInput({
    required this.onChanged,
    this.autofocus = false,
    super.key,
  });

  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<SearchInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SearchBar(
      controller: _controller,
      hintText: 'catalog.search_hint'.tr(),
      leading: const Icon(Icons.search),
      trailing: [
        if (_controller.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _controller.clear();
              widget.onChanged('');
            },
          ),
      ],
      onChanged: widget.onChanged,
      autoFocus: widget.autofocus,
    );
  }
}
