import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/glass/glass_switch.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/glass/glass_style.dart';
import '../../design/glass/glass_toast.dart';
import '../../design/glass/liquid_glass.dart';
import '../../design/widgets/artwork.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../design/widgets/media_tiles.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import '../library/collection_screens.dart';
import 'feature_codec.dart';

typedef StatsData = ({
  int totalMs,
  int totalPlays,
  List<(Track, int plays)> songs,
  List<(MediaItem, int plays)> artists,
  List<(MediaItem, int plays)> albums,
});

final statsProvider = FutureProvider.autoDispose.family<StatsData, String>((ref, period) async {
  final m = (await ref.watch(engineProvider).feature('stats', {'period': period}) as Map?) ?? const {};
  return (
    totalMs: (m['totalMs'] as num?)?.toInt() ?? 0,
    totalPlays: (m['totalPlays'] as num?)?.toInt() ?? 0,
    songs: [
      for (final s in ((m['songs'] as List?) ?? const []).cast<Map>())
        (trackFromMap(s), (s['plays'] as num?)?.toInt() ?? 0),
    ],
    artists: [
      for (final a in ((m['artists'] as List?) ?? const []).cast<Map>())
        (
          ArtistItem(
            Artist(id: a['id'] as String, name: a['name'] as String? ?? '', thumbnailUrl: a['thumbnailUrl'] as String?),
          ) as MediaItem,
          (a['plays'] as num?)?.toInt() ?? 0,
        ),
    ],
    albums: [
      for (final a in ((m['albums'] as List?) ?? const []).cast<Map>())
        (
          AlbumItem(
            Album(
              id: a['id'] as String,
              title: a['title'] as String? ?? '',
              thumbnailUrl: a['thumbnailUrl'] as String?,
              artists: [
                for (final r in ((a['artists'] as List?) ?? const []).cast<Map>())
                  ArtistRef(id: r['id'] as String?, name: r['name'] as String? ?? ''),
              ],
            ),
          ) as MediaItem,
          (a['plays'] as num?)?.toInt() ?? 0,
        ),
    ],
  );
});

const _periods = [('day', 'Day'), ('week', 'Week'), ('month', 'Month'), ('year', 'Year'), ('all', 'All time')];

/// Listening stats (day → all time): totals, top songs, artists and albums,
/// plus a "Your Year" card that opens the Wrapped story.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider(_period));
    final s = stats.value;
    final label = HydeColors.label.resolveFrom(context);
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);

    return LargeTitleScaffold(
      title: 'Stats',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter),
            child: LayoutBuilder(
              builder: (context, c) => GlassSegmentedControl(
                segments: [for (final p in _periods) p.$2],
                selectedIndex: _periods.indexWhere((p) => p.$1 == _period),
                onChanged: (i) => setState(() => _period = _periods[i].$1),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 18, HydeMetrics.gutter, 0),
            child: GlassPressable(
              onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const WrappedScreen())),
              pressedScale: 0.98,
              stretch: 0,
              child: Container(
                height: 120,
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(26)),
                  gradient: const LinearGradient(colors: [Color(0xFFFA2D48), Color(0xFF7D3CFF), Color(0xFF1E90FF)]),
                ),
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Your ${DateTime.now().year}',
                            style: HydeText.title1.copyWith(color: const Color(0xFFFFFFFF)),
                          ),
                          Text('Your year in music', style: HydeText.subhead.copyWith(color: const Color(0xDDFFFFFF))),
                        ],
                      ),
                    ),
                    const Icon(CupertinoIcons.sparkles, color: Color(0xFFFFFFFF), size: 36),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (s == null)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.only(top: 60), child: CupertinoActivityIndicator()),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 18, HydeMetrics.gutter, 0),
              child: Row(
                children: [
                  _Tile(value: formatListening(s.totalMs), label: 'Listening time', color: label, secondary: secondary),
                  const SizedBox(width: 12),
                  _Tile(value: '${s.totalPlays}', label: 'Plays', color: label, secondary: secondary),
                ],
              ),
            ),
          ),
          if (s.songs.isNotEmpty) const SliverToBoxAdapter(child: SectionHeader(title: 'Top songs')),
          SliverList.builder(
            itemCount: s.songs.length.clamp(0, 10),
            itemBuilder: (context, i) => MediaRow(
              item: TrackItem(s.songs[i].$1),
              trailing: Text('${s.songs[i].$2} plays', style: HydeText.footnote.copyWith(color: secondary)),
              onTap: () => guarded(
                context,
                () => ref.read(engineProvider).playTracks([for (final x in s.songs) x.$1], startIndex: i),
              ),
            ),
          ),
          if (s.artists.isNotEmpty) const SliverToBoxAdapter(child: SectionHeader(title: 'Top artists')),
          if (s.artists.isNotEmpty) SliverToBoxAdapter(child: _Carousel(items: s.artists)),
          if (s.albums.isNotEmpty) const SliverToBoxAdapter(child: SectionHeader(title: 'Top albums')),
          if (s.albums.isNotEmpty) SliverToBoxAdapter(child: _Carousel(items: s.albums)),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, required this.color, required this.secondary});
  final String value;
  final String label;
  final Color color;
  final Color secondary;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: HydeColors.groupedFill.resolveFrom(context),
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: HydeText.title2.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(label, style: HydeText.footnote.copyWith(color: secondary)),
        ],
      ),
    ),
  );
}

class _Carousel extends ConsumerWidget {
  const _Carousel({required this.items});
  final List<(MediaItem, int)> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    height: 230,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (context, i) =>
          MediaCard(item: items[i].$1, width: 150, onTap: () => openMediaItem(context, ref, items[i].$1)),
    ),
  );
}

/// "Your Year" story: swipe through minutes, top song, top artist, top five.
class WrappedScreen extends ConsumerStatefulWidget {
  const WrappedScreen({super.key});

  @override
  ConsumerState<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends ConsumerState<WrappedScreen> {
  final _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(statsProvider('year')).value;
    final year = DateTime.now().year;
    const white = Color(0xFFFFFFFF);

    Widget page(List<Color> colors, List<Widget> children) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );

    final topSong = s == null || s.songs.isEmpty ? null : s.songs.first;
    final topArtist = s == null || s.artists.isEmpty ? null : s.artists.first;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFF000000),
      child: Stack(
        children: [
          if (s == null)
            const Center(child: CupertinoActivityIndicator())
          else
            PageView(
              controller: _pages,
              children: [
                page(
                  const [Color(0xFFFA2D48), Color(0xFF7D3CFF)],
                  [
                    Text('HYDE $year', style: HydeText.caption.copyWith(color: white, letterSpacing: 3)),
                    const SizedBox(height: 12),
                    Text(
                      '${s.totalMs ~/ 60000}',
                      style: HydeText.largeTitle.copyWith(fontSize: 88, color: white, height: 1),
                    ),
                    Text('minutes of music', style: HydeText.title2.copyWith(color: white)),
                    const SizedBox(height: 12),
                    Text(
                      '${s.totalPlays} plays this year',
                      style: HydeText.body.copyWith(color: const Color(0xDDFFFFFF)),
                    ),
                  ],
                ),
                page(
                  const [Color(0xFF0F2027), Color(0xFF2C5364)],
                  [
                    Text('YOUR #1 SONG', style: HydeText.caption.copyWith(color: white, letterSpacing: 3)),
                    const SizedBox(height: 20),
                    if (topSong != null) ...[
                      Artwork(url: topSong.$1.thumbnailUrl, size: 220, radius: 18, shadow: true),
                      const SizedBox(height: 20),
                      Text(topSong.$1.title, style: HydeText.title1.copyWith(color: white)),
                      Text(topSong.$1.artistLine, style: HydeText.title3.copyWith(color: const Color(0xCCFFFFFF))),
                      Text('${topSong.$2} plays', style: HydeText.body.copyWith(color: const Color(0x99FFFFFF))),
                    ] else
                      Text('Keep listening to find your anthem.', style: HydeText.title2.copyWith(color: white)),
                  ],
                ),
                page(
                  const [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                  [
                    Text('YOUR TOP ARTIST', style: HydeText.caption.copyWith(color: white, letterSpacing: 3)),
                    const SizedBox(height: 20),
                    if (topArtist != null) ...[
                      Artwork(url: topArtist.$1.thumbnailUrl, size: 200, circle: true, shadow: true),
                      const SizedBox(height: 20),
                      Text(topArtist.$1.title, style: HydeText.title1.copyWith(color: white)),
                      Text('${topArtist.$2} plays', style: HydeText.body.copyWith(color: const Color(0x99FFFFFF))),
                    ] else
                      Text('Your favorite is out there.', style: HydeText.title2.copyWith(color: white)),
                  ],
                ),
                page(
                  const [Color(0xFF232526), Color(0xFF414345)],
                  [
                    Text('TOP 5', style: HydeText.caption.copyWith(color: white, letterSpacing: 3)),
                    const SizedBox(height: 16),
                    for (var i = 0; i < s.songs.length && i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text('${i + 1}', style: HydeText.title2.copyWith(color: white)),
                            const SizedBox(width: 14),
                            Artwork(url: s.songs[i].$1.thumbnailUrl, size: 52, radius: 8),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                s.songs[i].$1.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HydeText.headline.copyWith(color: white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    GlassPressable(
                      onTap: () => ref
                          .read(engineProvider)
                          .share(
                            'My $year on Hyde Music: ${s.totalMs ~/ 60000} minutes'
                            '${topSong == null ? '' : ', #1 song “${topSong.$1.title}”'}'
                            '${topArtist == null ? '' : ', top artist ${topArtist.$1.title}'}.',
                          ),
                      child: LiquidGlass.capsule(
                        style: GlassStyle.clear,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          child: Text('Share', style: HydeText.headline.copyWith(color: white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            right: 12,
            child: GlassPressable(
              onTap: () => Navigator.of(context).pop(),
              child: const LiquidGlass.capsule(
                style: GlassStyle.clear,
                child: SizedBox.square(
                  dimension: 40,
                  child: Icon(CupertinoIcons.xmark, color: Color(0xFFFFFFFF), size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
