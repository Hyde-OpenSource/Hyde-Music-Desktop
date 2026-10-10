import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_menu.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/widgets/media_tiles.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import 'collection_screens.dart';
import 'detail_screens.dart';

/// Slivers for a list of shelves — shared by Home, artist pages, browse
/// pages and the "more like this" rows of albums and playlists.
List<Widget> sectionSlivers(BuildContext context, WidgetRef ref, List<HomeSection> sections) => [
  for (final s in sections) ...[
    SliverToBoxAdapter(
      child: SectionHeader(
        title: s.title,
        label: s.label,
        thumbnailUrl: s.thumbnailUrl,
        onMore: _moreAction(context, s),
      ),
    ),
    SliverToBoxAdapter(child: SectionBody(section: s)),
  ],
];

VoidCallback? _moreAction(BuildContext context, HomeSection s) {
  final id = s.moreBrowseId;
  void push(Widget page) => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => page));
  if (id != null) {
    if (id.startsWith('VL')) return () => push(PlaylistScreen(id: id.substring(2), title: s.title));
    return () => push(BrowseScreen(browseId: id, params: s.moreParams, title: s.title));
  }
  // No server page: offer the full shelf as a grid when it's long.
  if (s.items.length > 8 && s.style != HomeSectionStyle.moods) {
    return () => push(ItemsScreen(title: s.title, items: s.items));
  }
  return null;
}

class SectionBody extends StatelessWidget {
  const SectionBody({super.key, required this.section});
  final HomeSection section;

  @override
  Widget build(BuildContext context) => switch (section.style) {
    HomeSectionStyle.quickPicks => SongColumns(items: section.items),
    HomeSectionStyle.moods => MoodGrid(items: [for (final i in section.items) if (i is BrowseItem) i]),
    _ => ItemCarousel(items: section.items),
  };
}

/// Songs in paged columns of four rows (Quick picks, Top songs).
class SongColumns extends ConsumerStatefulWidget {
  const SongColumns({super.key, required this.items});
  final List<MediaItem> items;

  @override
  ConsumerState<SongColumns> createState() => _SongColumnsState();
}

class _SongColumnsState extends ConsumerState<SongColumns> {
  final _pages = PageController(viewportFraction: 0.92);
  static const _rowHeight = 64.0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final playing = ref.watch(nowPlayingProvider.select((s) => s.track?.id));
    Widget row(int i) => SizedBox(
      height: _rowHeight,
      child: Builder(
        builder: (rowContext) => MediaRow(
          item: items[i],
          playing: items[i] is TrackItem && (items[i] as TrackItem).track.id == playing,
          onTap: () => openMediaItem(context, ref, items[i]),
          onLongPress: () => showItemMenu(context, ref, items[i], globalRectOf(rowContext)),
        ),
      ),
    );
    if (items.length <= 4) {
      return Column(children: [for (var i = 0; i < items.length; i++) row(i)]);
    }
    final rows = items.length < 4 ? items.length : 4;
    final columns = (items.length / rows).ceil();
    return SizedBox(
      height: rows * _rowHeight,
      child: PageView.builder(
        controller: _pages,
        padEnds: false,
        itemCount: columns,
        itemBuilder: (context, c) => Column(
          children: [for (var r = 0; r < rows && c * rows + r < items.length; r++) row(c * rows + r)],
        ),
      ),
    );
  }
}

/// Horizontal row of cards.
class ItemCarousel extends ConsumerWidget {
  const ItemCarousel({super.key, required this.items});
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const width = 148.0;
    return SizedBox(
      // artwork + gap + title + subtitle
      height: width + 7 + 20 + 18 + 4,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => Builder(
          builder: (cardContext) => MediaCard(
            item: items[i],
            width: width,
            onTap: () => openMediaItem(context, ref, items[i]),
            onLongPress: () => showItemMenu(context, ref, items[i], globalRectOf(cardContext)),
          ),
        ),
      ),
    );
  }
}

/// Mood & genre tiles: three rows scrolling sideways.
class MoodGrid extends ConsumerWidget {
  const MoodGrid({super.key, required this.items});
  final List<BrowseItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = items.length < 3 ? items.length.clamp(1, 3) : 3;
    return SizedBox(
      height: rows * 46.0 + (rows - 1) * 8,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: rows,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 168,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => MoodTile(item: items[i], onTap: () => openMediaItem(context, ref, items[i])),
      ),
    );
  }
}

/// Two-column grid of cards as slivers (library grids, "see all").
class ItemGridSliver extends ConsumerWidget {
  const ItemGridSliver({super.key, required this.items});
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 16,
          crossAxisSpacing: 14,
          // width → artwork (square) + 7 + two text lines
          childAspectRatio: 0.78,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => Builder(
          builder: (cardContext) => MediaCard(
            item: items[i],
            onTap: () => openMediaItem(context, ref, items[i]),
            onLongPress: () => showItemMenu(context, ref, items[i], globalRectOf(cardContext)),
          ),
        ),
      ),
    );
  }
}

/// Centered spinner / error-with-retry used by every async page.
class PageStatus extends StatelessWidget {
  const PageStatus.loading({super.key}) : message = null, onRetry = null;
  const PageStatus.error({super.key, required String this.message, this.onRetry});
  const PageStatus.empty({super.key, required String this.message}) : onRetry = null;

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
      child: message == null
          ? const Center(child: CupertinoActivityIndicator(radius: 13))
          : Column(
              children: [
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: HydeText.body.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 10),
                  CupertinoButton(onPressed: onRetry, child: const Text('Try Again')),
                ],
              ],
            ),
    );
  }
}

/// Play / Shuffle pair under a page header.
class PlayShuffleRow extends StatelessWidget {
  const PlayShuffleRow({super.key, required this.onPlay, required this.onShuffle, this.onSmartShuffle});
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  /// AI Shuffle: plays the list in a flowing, artist-balanced order.
  final VoidCallback? onSmartShuffle;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, VoidCallback? onTap) => Expanded(
      child: GlassPressable(
        onTap: onTap,
        pressedScale: 0.96,
        child: Container(
          height: 46,
          decoration: ShapeDecoration(
            shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(13)),
            color: HydeColors.groupedFill.resolveFrom(context),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: HydeColors.accent, size: 18),
              const SizedBox(width: 7),
              Text(label, style: HydeText.headline.copyWith(fontSize: 16, color: HydeColors.accent)),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 14, HydeMetrics.gutter + 4, 8),
      child: Row(
        children: [
          button(CupertinoIcons.play_fill, 'Play', onPlay),
          const SizedBox(width: 12),
          button(CupertinoIcons.shuffle, 'Shuffle', onShuffle),
          if (onSmartShuffle != null) ...[
            const SizedBox(width: 12),
            button(CupertinoIcons.sparkles, 'AI Shuffle', onSmartShuffle),
          ],
        ],
      ),
    );
  }
}
