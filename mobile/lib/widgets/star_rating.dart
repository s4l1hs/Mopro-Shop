import 'package:flutter/material.dart';

class StarRating extends StatelessWidget {
  const StarRating({
    required this.rating,
    this.maxStars = 5,
    this.size = 16,
    this.color,
    super.key,
  });

  final double rating;
  final int maxStars;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final starColor =
        color ?? Theme.of(context).colorScheme.tertiary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxStars, (i) {
        final filled = rating >= i + 1;
        final half = !filled && rating >= i + 0.5;
        return Icon(
          filled
              ? Icons.star
              : half
                  ? Icons.star_half
                  : Icons.star_border,
          size: size,
          color: starColor,
        );
      }),
    );
  }
}
