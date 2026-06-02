import 'package:flutter/material.dart';

/// A padded, centered [CircularProgressIndicator] for full-section loading states.
///
/// Consolidated from two byte-identical private `_LoadingSpinner` copies in the
/// wallet screens (see chore/project-cleanup-confirmed).
class LoadingSpinner extends StatelessWidget {
  const LoadingSpinner({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
}
