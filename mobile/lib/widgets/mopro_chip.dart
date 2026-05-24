import 'package:flutter/material.dart';

class MoproChip extends StatelessWidget {
  const MoproChip({
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap != null ? (_) => onTap!() : null,
      avatar: leading,
      showCheckmark: false,
    );
  }
}

class MoproChoiceGroup extends StatelessWidget {
  const MoproChoiceGroup({
    required this.items,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<String> items;
  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => MoproChip(
              label: item,
              selected: item == selected,
              onTap: () => onChanged(item),
            ),
          )
          .toList(),
    );
  }
}
