import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_controls.dart';
import '../../design/glass/glass_menu.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/glass/glass_toast.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../design/widgets/media_tiles.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import '../more/feature_codec.dart';
import '../player/player_actions.dart';
import 'detail_screens.dart';
import 'section_views.dart';

export 'detail_screens.dart';
export 'section_views.dart';

/// Opens any media item: songs play (and continue with their radio),
/// collections push their page.
void openMediaItem(BuildContext context, WidgetRef ref, MediaItem item) {
  void push(Widget page) => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => page));
  switch (item) {
    case TrackItem(:final track):
      guarded(context, () => ref.read(engineProvider).playTracks([track]));
    case PlaylistItem(:final playlist):
      push(PlaylistScreen(id: playlist.id, title: playlist.name, artwork: playlist.thumbnailUrl));
    case AlbumItem(:final album):
      push(AlbumScreen(id: album.id, title: album.title, subtitle: album.artistLine, artwork: album.thumbnailUrl));
    case ArtistItem(:final artist):
      push(ArtistScreen(id: artist.id, name: artist.name, artwork: artist.thumbnailUrl));
    case BrowseItem(:final browseId, :final params, :final title):
      push(BrowseScreen(browseId: browseId, params: params, title: title));
  }
}

/// Long-press / ••• menu for a song. [playlistId] adds "Remove from playlist".
Future<void> showSongMenu(BuildContext context, WidgetRef ref, Track t, Rect anchor, {String? playlistId}) {
  final engine = ref.read(engineProvider);
  final artist = t.artists.where((a) => a.id != null).firstOrNull;
  return showGlassMenu(
    context,
    anchor: anchor,
    menu: GlassMenu(
      quickActions: [
        GlassMenuAction(
          icon: CupertinoIcons.text_insert,
          label: 'Play next',
          onSelected: () => guarded(context, () => engine.playNext([t])),
        ),
        GlassMenuAction(
          icon: CupertinoIcons.text_append,
          label: 'Add to queue',
          onSelected: () => guarded(context, () => engine.addToQueue([t])),
        ),
        GlassMenuAction(
          icon: t.liked ? CupertinoIcons.star_fill : CupertinoIcons.star,
          label: t.liked ? 'Favorited' : 'Favorite',
          onSelected: () => guarded(context, () => engine.setLiked(t, !t.liked)),
        ),
      ],
      sections: [
        [
          GlassMenuAction(
            icon: CupertinoIcons.text_badge_plus,
            label: 'Add to playlist',
            onSelected: () => showAddToPlaylist(context, ref, [t]),
          ),
          if (playlistId != null)
            GlassMenuAction(
              icon: CupertinoIcons.minus_circle,
              label: 'Remove from playlist',
              destructive: true,
              onSelected: () => guarded(context, () => engine.removeFromPlaylist(playlistId, t)),
            ),
          if (!t.isLocal)
            GlassMenuAction(
              icon: t.inLibrary ? CupertinoIcons.minus_circle : CupertinoIcons.plus_circle,
              label: t.inLibrary ? 'Remove from library' : 'Add to library',
              onSelected: () => guarded(context, () => engine.setInLibrary(t, !t.inLibrary)),
            ),
          if (!t.isLocal)
            GlassMenuAction(
              icon: t.isDownloaded ? CupertinoIcons.xmark_circle : CupertinoIcons.arrow_down_circle,
              label: t.isDownloaded ? 'Remove download' : 'Download',
              onSelected: () => guarded(context, () async {
                if (t.isDownloaded) {
                  await engine.removeDownload([t]);
                } else {
                  await engine.download([t]);
                  if (context.mounted) showGlassToast(context, 'Downloading', icon: CupertinoIcons.arrow_down_circle);
                }
              }),
            ),
        ],
        [
          if (!t.isLocal)
            GlassMenuAction(
              icon: CupertinoIcons.dot_radiowaves_left_right,
              label: 'Start radio',
              onSelected: () => guarded(context, () => engine.startRadio(t)),
            ),
          if (t.albumName != null && t.albumId != null)
            GlassMenuAction(
              icon: CupertinoIcons.square_stack,
              label: 'Go to Album',
              subtitle: t.albumName,
              onSelected: () => goToCollection(context, ref, 'album', t.albumId),
            ),
          if (artist != null)
            GlassMenuAction(
              icon: CupertinoIcons.mic,
              label: 'Go to Artist',
              subtitle: artist.name,
              onSelected: () => goToCollection(context, ref, 'artist', artist.id),
            ),
          if (!t.isLocal)
            GlassMenuAction(
              icon: CupertinoIcons.square_arrow_up,
              label: 'Share',
              onSelected: () => guarded(context, () async => engine.share(await engine.shareLink(TrackItem(t)))),
            ),
        ],
      ],
    ),
  );
}

/// Long-press menu for albums, playlists and artists.
Future<void> showItemMenu(BuildContext context, WidgetRef ref, MediaItem item, Rect anchor) async {
  if (item is TrackItem) return showSongMenu(context, ref, item.track, anchor);
  if (item is BrowseItem) return;
  final engine = ref.read(engineProvider);
  final id = switch (item) {
    AlbumItem(:final album) => album.id,
    ArtistItem(:final artist) => artist.id,
    PlaylistItem(:final playlist) => playlist.id,
    _ => '',
  };
  Future<List<Track>> tracks() async {
    final list = await engine.playlistTracks(id);
    if (list.isEmpty) throw StateError('Nothing to play');
    return list;
  }

  final localPlaylist = item is PlaylistItem && item.playlist.kind == PlaylistKind.local;
  return showGlassMenu(
    context,
    anchor: anchor,
    menu: GlassMenu(
      quickActions: [
        GlassMenuAction(
          icon: CupertinoIcons.play_fill,
          label: 'Play',
          onSelected: () => guarded(context, () async => engine.playTracks(await tracks())),
        ),
        GlassMenuAction(
          icon: CupertinoIcons.shuffle,
          label: 'Shuffle',
          onSelected: () => guarded(context, () async => engine.playTracks(await tracks(), shuffle: true)),
        ),
      ],
      sections: [
        [
          GlassMenuAction(
            icon: CupertinoIcons.text_insert,
            label: 'Play next',
            onSelected: () => guarded(context, () async => engine.playNext(await tracks())),
          ),
          GlassMenuAction(
            icon: CupertinoIcons.text_append,
            label: 'Add to queue',
            onSelected: () => guarded(context, () async => engine.addToQueue(await tracks())),
          ),
          GlassMenuAction(
            icon: CupertinoIcons.arrow_down_circle,
            label: 'Download',
            onSelected: () => guarded(context, () async {
              await engine.download(await tracks());
              if (context.mounted) showGlassToast(context, 'Downloading', icon: CupertinoIcons.arrow_down_circle);
            }),
          ),
        ],
        [
          if (localPlaylist)
            GlassMenuAction(
              icon: CupertinoIcons.trash,
              label: 'Delete playlist',
              destructive: true,
              onSelected: () async {
                final ok = await confirm(context, title: 'Delete “${item.title}”?', action: 'Delete', destructive: true);
                if (ok) await engine.deletePlaylist(id);
              },
            ),
          if (item is! PlaylistItem || item.playlist.kind == PlaylistKind.local || item.playlist.kind == PlaylistKind.online)
            GlassMenuAction(
              icon: CupertinoIcons.square_arrow_up,
              label: 'Share',
              onSelected: () => guarded(context, () async => engine.share(await engine.shareLink(item))),
            ),
        ],
      ],
    ),
  );
}

/// Playlists grid (reference screenshot): search, count + Create playlist,
/// two-column artwork grid.
class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  String _filter = '';

  Future<void> _create() async {
    final name = await promptText(context, title: 'New Playlist');
    if (name != null && name.isNotEmpty && mounted) {
      await guarded(context, () => ref.read(engineProvider).createPlaylist(name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(libraryPlaylistsProvider).value ?? const [];
    final shown = playlists.where((p) => p.name.toLowerCase().contains(_filter.toLowerCase())).toList();
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);

    return LargeTitleScaffold(
      title: 'Playlists',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter),
            child: HydeSearchField(placeholder: 'Search your playlists', onChanged: (v) => setState(() => _filter = v)),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 14, HydeMetrics.gutter + 4, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    shown.length == 1 ? '1 playlist' : '${shown.length} playlists',
                    style: HydeText.subhead.copyWith(color: secondary),
                  ),
                ),
                GlassPressable(
                  onTap: _create,
                  child: Row(
                    children: [
                      const Icon(CupertinoIcons.plus, color: HydeColors.accent, size: 18),
                      const SizedBox(width: 6),
                      Text('Create playlist', style: HydeText.headline.copyWith(fontSize: 16, color: HydeColors.accent)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ItemGridSliver(items: [for (final p in shown) PlaylistItem(p)]),
      ],
    );
  }
}

enum LibraryCollection { artists, albums, songs, downloads }

const _songSorts = [
  ('CREATE_DATE', 'Date added'),
  ('NAME', 'Title'),
  ('ARTIST', 'Artist'),
  ('PLAY_TIME', 'Most played'),
];

/// Artists / Albums / Songs / Downloads.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key, required this.collection});
  final LibraryCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(engineProvider);
    final title = switch (collection) {
      LibraryCollection.artists => 'Artists',
      LibraryCollection.albums => 'Albums',
      LibraryCollection.songs => 'Songs',
      LibraryCollection.downloads => 'Downloads',
    };
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);

    if (collection == LibraryCollection.artists || collection == LibraryCollection.albums) {
      final AsyncValue<List<MediaItem>> items = collection == LibraryCollection.artists
          ? ref.watch(libraryArtistsProvider).whenData((l) => [for (final a in l) ArtistItem(a)])
          : ref.watch(libraryAlbumsProvider).whenData((l) => [for (final a in l) AlbumItem(a)]);
      final list = items.value ?? const <MediaItem>[];
      return LargeTitleScaffold(
        title: title,
        slivers: [
          if (items.isLoading && list.isEmpty)
            const SliverToBoxAdapter(child: PageStatus.loading())
          else if (list.isEmpty)
            SliverToBoxAdapter(
              child: PageStatus.empty(
                message: collection == LibraryCollection.artists
                    ? 'Artists of the songs you save, and artists you follow, appear here.'
                    : 'Albums you add to your library appear here.',
              ),
            )
          else if (collection == LibraryCollection.artists)
            SliverList.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => MediaRow(
                item: list[i],
                onTap: () => openMediaItem(context, ref, list[i]),
                trailing: Icon(CupertinoIcons.chevron_forward, size: 16, color: HydeColors.tertiaryLabel.resolveFrom(context)),
              ),
            )
          else
            ItemGridSliver(items: list),
        ],
      );
    }

    final downloadsOnly = collection == LibraryCollection.downloads;
    final all = ref.watch(librarySongsProvider);
    final tracks = [
      for (final t in all.value ?? const <Track>[])
        if (!downloadsOnly || t.isDownloaded) t,
    ];
    final playing = ref.watch(nowPlayingProvider.select((s) => s.track?.id));
    final settings = ref.watch(settingsProvider).value ?? const {};
    final sort = settings['songSortType'] as String? ?? 'CREATE_DATE';
    final descending = settings['songSortDescending'] as bool? ?? true;

    return LargeTitleScaffold(
      title: title,
      actions: [
        Builder(
          builder: (buttonContext) => GlassIconButton(
            icon: CupertinoIcons.arrow_up_arrow_down,
            size: 40,
            iconSize: 18,
            color: HydeColors.accent,
            semanticLabel: 'Sort',
            onPressed: () => showGlassMenu(
              context,
              anchor: globalRectOf(buttonContext),
              menu: GlassMenu(
                sections: [
                  [
                    for (final (value, label) in _songSorts)
                      GlassMenuAction(
                        icon: value == sort ? CupertinoIcons.checkmark : CupertinoIcons.circle,
                        label: label,
                        onSelected: () => ref.read(settingsProvider.notifier).set('songSortType', value),
                      ),
                  ],
                  [
                    GlassMenuAction(
                      icon: descending ? CupertinoIcons.arrow_down : CupertinoIcons.arrow_up,
                      label: descending ? 'Descending' : 'Ascending',
                      onSelected: () => ref.read(settingsProvider.notifier).set('songSortDescending', !descending),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
      slivers: [
        if (downloadsOnly) const SliverToBoxAdapter(child: _DownloadStatus()),
        if (all.isLoading && tracks.isEmpty)
          const SliverToBoxAdapter(child: PageStatus.loading())
        else if (tracks.isEmpty)
          SliverToBoxAdapter(
            child: PageStatus.empty(
              message: downloadsOnly
                  ? 'Downloaded songs play without internet. Use Download in any song’s menu.'
                  : 'Songs you favorite or add to your library appear here.',
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: PlayShuffleRow(
              onPlay: () => guarded(context, () => engine.playTracks(tracks)),
              onShuffle: () => guarded(context, () => engine.playTracks(tracks, shuffle: true)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 4, HydeMetrics.gutter + 4, 4),
              child: Text(
                tracks.length == 1 ? '1 song' : '${tracks.length} songs',
                style: HydeText.footnote.copyWith(color: secondary),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (context, i) => SongSwipe(
              track: tracks[i],
              child: Builder(
                builder: (rowContext) => MediaRow(
                  item: TrackItem(tracks[i]),
                  dense: true,
                  playing: tracks[i].id == playing,
                  onTap: () => guarded(context, () => engine.playTracks(tracks, startIndex: i)),
                  onLongPress: () => showSongMenu(context, ref, tracks[i], globalRectOf(rowContext)),
                  trailing: GlassPressable(
                    onTap: () => showSongMenu(context, ref, tracks[i], globalRectOf(rowContext)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                      child: Icon(CupertinoIcons.ellipsis, size: 20, color: secondary),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Active downloads, failures, and the one-tap re-download of songs the
/// previous (native) version had downloaded.
class _DownloadStatus extends ConsumerWidget {
  const _DownloadStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(featureStateProvider('downloads')).value ?? const {};
    final active = (state['active'] as int? ?? 0) + (state['queued'] as int? ?? 0);
    final failed = ((state['failed'] as Map?) ?? const {}).length;
    final progress = ((state['progress'] as Map?) ?? const {}).values.cast<num>().toList();
    final pending = ref.watch(_pendingDownloadsProvider).value ?? const <Track>[];
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final engine = ref.read(engineProvider);

    Widget card({required Widget child}) => Container(
      margin: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 0, HydeMetrics.gutter, 12),
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        color: HydeColors.groupedFill.resolveFrom(context),
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: child,
    );

    return Column(
      children: [
        if (active > 0)
          card(
            child: Row(
              children: [
                const CupertinoActivityIndicator(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Downloading ${active == 1 ? '1 song' : '$active songs'}'
                    '${progress.isEmpty ? '' : ' · ${(progress.first * 100).round()}%'}',
                    style: HydeText.subhead.copyWith(color: HydeColors.label.resolveFrom(context)),
                  ),
                ),
              ],
            ),
          ),
        if (failed > 0 && active == 0)
          card(
            child: Text(
              '${failed == 1 ? '1 download' : '$failed downloads'} failed. Check your connection and try again.',
              style: HydeText.subhead.copyWith(color: secondary),
            ),
          ),
        if (pending.isNotEmpty && active == 0)
          card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${pending.length == 1 ? '1 song' : '${pending.length} songs'} from the previous version need to be downloaded again.',
                  style: HydeText.subhead.copyWith(color: HydeColors.label.resolveFrom(context)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => guarded(context, () async {
                        await engine.feature('downloads.redownload');
                        ref.invalidate(_pendingDownloadsProvider);
                      }),
                      child: const Text('Download All'),
                    ),
                    const SizedBox(width: 20),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => guarded(context, () async {
                        await engine.feature('downloads.dismissPending');
                        ref.invalidate(_pendingDownloadsProvider);
                      }),
                      child: Text('Not Now', style: TextStyle(color: secondary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

final _pendingDownloadsProvider = FutureProvider.autoDispose<List<Track>>((ref) async {
  ref.watch(libraryRevisionProvider);
  final raw = (await ref.watch(engineProvider).feature('downloads.pending') as List?) ?? const [];
  return [for (final m in raw.cast<Map>()) trackFromMap(m)];
});

/// Instant search across the local library (songs, albums, artists, playlists).
class LibrarySearchScreen extends ConsumerStatefulWidget {
  const LibrarySearchScreen({super.key});

  @override
  ConsumerState<LibrarySearchScreen> createState() => _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends ConsumerState<LibrarySearchScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    bool hit(String s) => s.toLowerCase().contains(q);
    final songs = ref.watch(librarySongsProvider).value ?? const <Track>[];
    final albums = ref.watch(libraryAlbumsProvider).value ?? const <Album>[];
    final artists = ref.watch(libraryArtistsProvider).value ?? const <Artist>[];
    final playlists = ref.watch(libraryPlaylistsProvider).value ?? const <Playlist>[];
    final results = q.isEmpty
        ? const <MediaItem>[]
        : <MediaItem>[
            for (final p in playlists)
              if (hit(p.name)) PlaylistItem(p),
            for (final a in artists)
              if (hit(a.name)) ArtistItem(a),
            for (final a in albums)
              if (hit(a.title) || hit(a.artistLine)) AlbumItem(a),
            for (final t in songs)
              if (hit(t.title) || hit(t.artistLine) || hit(t.albumName ?? '')) TrackItem(t),
          ];
    final tracks = [
      for (final r in results)
        if (r is TrackItem) r.track,
    ];

    return LargeTitleScaffold(
      title: 'Search Library',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 0, HydeMetrics.gutter, 12),
            child: HydeSearchField(
              placeholder: 'Songs, albums, artists, playlists',
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
        ),
        if (q.isNotEmpty && results.isEmpty)
          SliverToBoxAdapter(child: PageStatus.empty(message: 'Nothing in your library matches “${_q.trim()}”.')),
        SliverList.builder(
          itemCount: results.length,
          itemBuilder: (context, i) => Builder(
            builder: (rowContext) => MediaRow(
              item: results[i],
              showType: true,
              onTap: () => results[i] is TrackItem
                  ? guarded(
                      context,
                      () => ref
                          .read(engineProvider)
                          .playTracks(tracks, startIndex: tracks.indexOf((results[i] as TrackItem).track)),
                    )
                  : openMediaItem(context, ref, results[i]),
              onLongPress: () => showItemMenu(context, ref, results[i], globalRectOf(rowContext)),
            ),
          ),
        ),
      ],
    );
  }
}

/// iOS-style swipe actions on a song row: swipe right → Play Next,
/// swipe left → Add to Queue. The row springs back; nothing is removed.
class SongSwipe extends ConsumerWidget {
  const SongSwipe({super.key, required this.track, required this.child});
  final Track track;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget bg(Color color, IconData icon, String label, Alignment align) => Container(
      color: color,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFFFFFFF)),
          const SizedBox(height: 2),
          Text(label, style: HydeText.caption.copyWith(color: const Color(0xFFFFFFFF))),
        ],
      ),
    );
    return Dismissible(
      key: ValueKey('swipe-${track.id}'),
      dismissThresholds: const {DismissDirection.startToEnd: 0.28, DismissDirection.endToStart: 0.28},
      background: bg(HydeColors.indigo, CupertinoIcons.text_insert, 'Play Next', Alignment.centerLeft),
      secondaryBackground: bg(HydeColors.orange, CupertinoIcons.text_append, 'Add to Queue', Alignment.centerRight),
      confirmDismiss: (direction) async {
        final engine = ref.read(engineProvider);
        final next = direction == DismissDirection.startToEnd;
        await guarded(context, () => next ? engine.playNext([track]) : engine.addToQueue([track]));
        if (context.mounted) {
          showGlassToast(context, next ? 'Playing next' : 'Added to queue', icon: CupertinoIcons.checkmark_circle);
        }
        return false;
      },
      child: child,
    );
  }
}
