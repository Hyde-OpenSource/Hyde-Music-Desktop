import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_controls.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../design/widgets/media_tiles.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import '../more/history_screen.dart';
import '../more/local_media_screen.dart';
import '../more/social_screens.dart';
import '../more/stats_screen.dart';
import 'collection_screens.dart';

/// Library (reference screenshot): a short list of accent-icon rows, then
/// Recently Added as a grid.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentlyAddedProvider).value ?? const <MediaItem>[];
    void push(Widget w) => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => w));

    final rows = <(IconData, String, VoidCallback)>[
      (CupertinoIcons.music_note_list, 'Playlists', () => push(const PlaylistsScreen())),
      (CupertinoIcons.mic, 'Artists', () => push(const CollectionScreen(collection: LibraryCollection.artists))),
      (CupertinoIcons.square_stack, 'Albums', () => push(const CollectionScreen(collection: LibraryCollection.albums))),
      (CupertinoIcons.music_note, 'Songs', () => push(const CollectionScreen(collection: LibraryCollection.songs))),
      (
        CupertinoIcons.arrow_down_circle,
        'Downloaded',
        () => push(const CollectionScreen(collection: LibraryCollection.downloads)),
      ),
      (CupertinoIcons.device_phone_portrait, 'On This Device', () => push(const LocalMediaScreen())),
    ];
    final more = <(IconData, String, VoidCallback)>[
      (CupertinoIcons.clock, 'History', () => push(const HistoryScreen())),
      (CupertinoIcons.chart_bar, 'Stats', () => push(const StatsScreen())),
      (CupertinoIcons.sparkles, 'Your Year', () => push(const WrappedScreen())),
    ];
    final together = <(IconData, String, VoidCallback)>[
      (CupertinoIcons.person_2, 'Listen Together', () => push(const ListenTogetherScreen())),
      (CupertinoIcons.dot_radiowaves_left_right, 'Nearby Sync', () => push(const NearbySyncScreen())),
    ];

    return LargeTitleScaffold(
      title: 'Library',
      actions: [
        GlassIconButton(
          icon: CupertinoIcons.search,
          size: 40,
          iconSize: 20,
          color: HydeColors.accent,
          semanticLabel: 'Search library',
          onPressed: () => push(const LibrarySearchScreen()),
        ),
      ],
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: () async {
            ref.invalidate(recentlyAddedProvider);
            await ref.read(recentlyAddedProvider.future);
          },
        ),
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) =>
              _LibraryRow(icon: rows[i].$1, title: rows[i].$2, onTap: rows[i].$3, divider: i < rows.length - 1),
        ),
        // Secondary destinations as compact tiles so the list above stays short.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 16, HydeMetrics.gutter + 4, 0),
            child: Row(
              children: [
                for (var i = 0; i < more.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _Shortcut(icon: more[i].$1, label: more[i].$2, onTap: more[i].$3)),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 8, HydeMetrics.gutter + 4, 0),
            child: Row(
              children: [
                for (var i = 0; i < together.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _Shortcut(icon: together[i].$1, label: together[i].$2, onTap: together[i].$3)),
                ],
              ],
            ),
          ),
        ),
        if (recent.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader(title: 'Recently Added')),
          ItemGridSliver(items: recent),
        ] else
          const SliverToBoxAdapter(
            child: PageStatus.empty(message: 'Songs, albums and playlists you save will show up here.'),
          ),
      ],
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.icon, required this.title, required this.onTap, required this.divider});
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: HydeMetrics.gutter + 4),
        child: Row(
          children: [
            SizedBox(width: 28, child: Icon(icon, color: HydeColors.accent, size: 23)),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                height: 50,
                padding: const EdgeInsets.only(right: HydeMetrics.gutter + 4),
                decoration: BoxDecoration(
                  border: divider
                      ? Border(bottom: BorderSide(color: HydeColors.separator.resolveFrom(context), width: 0.5))
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: HydeText.body.copyWith(fontSize: 19, color: HydeColors.label.resolveFrom(context)),
                      ),
                    ),
                    Icon(CupertinoIcons.chevron_forward, size: 16, color: HydeColors.tertiaryLabel.resolveFrom(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: ShapeDecoration(
          color: HydeColors.groupedFill.resolveFrom(context),
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: HydeColors.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HydeText.subhead.copyWith(fontWeight: FontWeight.w600, color: HydeColors.label.resolveFrom(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
