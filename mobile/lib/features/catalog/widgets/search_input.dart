import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class SearchInput extends StatefulWidget {
  const SearchInput({
    required this.onChanged,
    this.controller,
    this.autofocus = false,
    super.key,
  });

  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final bool autofocus;

  @override
  State<SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<SearchInput> {
  late final TextEditingController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SearchBar(
      controller: _controller,
      hintText: 'search.hint'.tr(),
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
