import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/design/widgets/responsive_network_image.dart';
import 'package:mopro/features/catalog/providers/home_provider.dart';

/// Horizontally-scrolled strip of circular mood tiles for the home screen.
///
/// Layout: 72dp avatar (with brand-orange ring) over an 11sp label.
/// Tapping a tile follows its deep_link via go_router. On any provider error
/// (or empty payload), the strip is collapsed entirely — never shown empty.
class MoodStoriesStrip extends ConsumerWidget {
  const MoodStoriesStrip({super.key});

  static const double _avatarSize = 64;
  static const double _stripHeight = 110;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncStories = ref.watch(homeMoodStoriesProvider);
    return asyncStories.when(
      loading: () => const SizedBox(height: _stripHeight),
      error: (_, __) => const SizedBox.shrink(),
      data: (stories) {
        if (stories.isEmpty) return const SizedBox.shrink();
        // Mobile keeps the horizontal scroller; tablet/desktop lay the tiles out
        // as a fixed-column grid: 8 per row (tablet) / 12 per row (desktop) (§6.2).
        if (!context.isMobile) {
          final perRow = context.isDesktop ? 12 : 8;
          final tiles = stories.take(perRow).toList();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: perRow,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
              ),
              itemCount: tiles.length,
              itemBuilder: (context, i) => _MoodTile(story: tiles[i]),
            ),
          );
        }
        return SizedBox(
          height: _stripHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: stories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _MoodTile(story: stories[i]),
          ),
        );
      },
    );
  }
}

class _MoodTile extends StatelessWidget {
  const _MoodTile({required this.story});
  final HomeMoodStory story;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(story.deepLink),
      borderRadius: BorderRadius.circular(40),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: MoodStoriesStrip._avatarSize + 6,
              height: MoodStoriesStrip._avatarSize + 6,
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [MoproTokens.primaryLight, Color(0xFFE36925)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: ClipOval(
                child: ResponsiveNetworkImage(
                  imageUrl: story.imageUrl,
                  placeholder: (_, __) => const ColoredBox(
                    color: Color(0xFFEEEEEE),
                  ),
                  errorWidget: (_, __, ___) => const Icon(
                    Icons.image_not_supported_outlined,
                    size: 28,
                    color: Colors.black26,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              story.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
