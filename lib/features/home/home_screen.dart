import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_controls.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/glass/glass_toast.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import '../library/collection_screens.dart';

/// Home feed: mood chips, quick picks, keep listening, your playlists,
/// "similar to" rows and YouTube Music's shelves, loading more as you scroll.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _reloading = false;

  /// Reloads every shelf; the header button spins meanwhile.
  Future<void> _reload() async {
    if (_reloading) return;
    setState(() => _reloading = true);
    try {
      await ref.read(homeProvider.notifier).refresh();
    } catch (e) {
      if (mounted) showGlassToast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeProvider);
    final state = home.value;
    final notifier = ref.read(homeProvider.notifier);
    return LargeTitleScaffold(
      title: 'Home',
      onEndReached: notifier.loadMore,
      actions: [
        // History and Settings live in the sidebar on desktop.
        if (_reloading)
          const SizedBox.square(dimension: 40, child: CupertinoActivityIndicator())
        else
          GlassIconButton(
            icon: CupertinoIcons.arrow_clockwise,
            size: 40,
            iconSize: 19,
            semanticLabel: 'Reload Home (F5)',
            onPressed: _reload,
          ),
      ],
      slivers: [
        if (state != null && state.feed.chips.isNotEmpty)
          SliverToBoxAdapter(
            child: _Chips(chips: state.feed.chips, selected: state.chip, onSelected: notifier.selectChip),
          ),
        const SliverToBoxAdapter(child: _ExploreRow()),
        if (state == null)
          SliverToBoxAdapter(
            child: home.hasError
                ? PageStatus.error(message: friendlyError(home.error!), onRetry: () => ref.invalidate(homeProvider))
                : const PageStatus.loading(),
          )
        else ...[
          ...sectionSlivers(context, ref, state.feed.sections),
          if (state.loadingMore || state.feed.continuation != null)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.symmetric(vertical: 28), child: CupertinoActivityIndicator()),
            )
          else if (state.feed.sections.isEmpty)
            SliverToBoxAdapter(
              child: PageStatus.error(message: 'Nothing to show right now.', onRetry: () => ref.invalidate(homeProvider)),
            ),
        ],
      ],
    );
  }
}

/// Mood filter chips ("Relax", "Workout"…). Tapping the selected one clears it.
class _Chips extends StatelessWidget {
  const _Chips({required this.chips, required this.selected, required this.onSelected});
  final List<HomeChip> chips;
  final HomeChip? selected;
  final ValueChanged<HomeChip?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final on = chips[i].title == selected?.title;
          return GlassPressable(
            onTap: () => onSelected(chips[i]),
            pressedScale: 0.94,
            stretch: 0,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                color: on ? HydeColors.accent : HydeColors.groupedFill.resolveFrom(context),
              ),
              child: Text(
                chips[i].title,
                style: HydeText.subhead.copyWith(
                  fontWeight: FontWeight.w600,
                  color: on ? const Color(0xFFFFFFFF) : HydeColors.label.resolveFrom(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shortcuts into YouTube Music's browse pages.
class _ExploreRow extends StatelessWidget {
  const _ExploreRow();

  @override
  Widget build(BuildContext context) {
    void push(Widget page) => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => page));
    Widget tile(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
      child: GlassPressable(
        onTap: onTap,
        pressedScale: 0.95,
        stretch: 0,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: ShapeDecoration(
            color: HydeColors.groupedFill.resolveFrom(context),
            shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 7),
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
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 14, HydeMetrics.gutter + 4, 0),
      child: Row(
        children: [
          tile(
            CupertinoIcons.sparkles,
            'New',
            HydeColors.pink,
            () => push(const BrowseScreen(browseId: 'FEmusic_new_releases_albums', title: 'New Releases')),
          ),
          const SizedBox(width: 8),
          tile(
            CupertinoIcons.chart_bar_alt_fill,
            'Charts',
            HydeColors.blue,
            () => push(const BrowseScreen(browseId: 'FEmusic_charts', title: 'Charts')),
          ),
          const SizedBox(width: 8),
          tile(
            CupertinoIcons.smiley,
            'Moods',
            HydeColors.orange,
            () => push(const BrowseScreen(browseId: 'FEmusic_moods_and_genres', title: 'Moods & Genres')),
          ),
        ],
      ),
    );
  }
}
