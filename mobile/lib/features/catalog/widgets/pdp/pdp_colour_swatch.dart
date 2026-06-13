import 'package:flutter/material.dart';

/// PD-02: maps a variant's real `color` name (TR/EN) to a swatch colour so the
/// PDP variant chips can show a colour dot. This is a *presentation* of the
/// already-served `Variant.color` field — NOT fabricated data. Unknown names
/// return null → the chip stays text-only (no fake swatch). A full per-variant
/// colour-attribute model (hex from the catalog) remains PLP-13 Phase 2.
Color? colourForName(String? name) {
  if (name == null) return null;
  final n = name.toLowerCase().trim();
  if (n.isEmpty) return null;
  if (_swatches.containsKey(n)) return _swatches[n];
  // Multi-word names ("açık mavi", "koyu yeşil"): match a known colour token.
  for (final entry in _swatches.entries) {
    if (n.contains(entry.key)) return entry.value;
  }
  return null;
}

const Map<String, Color> _swatches = {
  // TR
  'siyah': Color(0xFF000000),
  'beyaz': Color(0xFFFFFFFF),
  'kırmızı': Color(0xFFE53935),
  'mavi': Color(0xFF1E88E5),
  'lacivert': Color(0xFF1A237E),
  'yeşil': Color(0xFF43A047),
  'sarı': Color(0xFFFDD835),
  'turuncu': Color(0xFFFB8C00),
  'mor': Color(0xFF8E24AA),
  'pembe': Color(0xFFEC407A),
  'gri': Color(0xFF9E9E9E),
  'kahverengi': Color(0xFF6D4C41),
  'bej': Color(0xFFD7CCC8),
  'bordo': Color(0xFF800020),
  'ekru': Color(0xFFF5F5DC),
  'krem': Color(0xFFFFFDD0),
  'haki': Color(0xFF8F9779),
  'turkuaz': Color(0xFF1DE9B6),
  'altın': Color(0xFFFFD700),
  'gümüş': Color(0xFFC0C0C0),
  // EN
  'black': Color(0xFF000000),
  'white': Color(0xFFFFFFFF),
  'red': Color(0xFFE53935),
  'blue': Color(0xFF1E88E5),
  'navy': Color(0xFF1A237E),
  'green': Color(0xFF43A047),
  'yellow': Color(0xFFFDD835),
  'orange': Color(0xFFFB8C00),
  'purple': Color(0xFF8E24AA),
  'pink': Color(0xFFEC407A),
  'grey': Color(0xFF9E9E9E),
  'gray': Color(0xFF9E9E9E),
  'brown': Color(0xFF6D4C41),
  'beige': Color(0xFFD7CCC8),
  'gold': Color(0xFFFFD700),
  'silver': Color(0xFFC0C0C0),
};

/// A small circular colour swatch for a variant chip avatar. Light colours get a
/// hairline border so white/cream stays visible on a light surface.
class ColourSwatch extends StatelessWidget {
  const ColourSwatch({required this.colour, this.size = 14, super.key});

  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant),
      ),
    );
  }
}
