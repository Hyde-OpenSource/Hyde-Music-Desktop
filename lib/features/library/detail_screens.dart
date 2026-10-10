import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show SystemMouseCursors;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_controls.dart';
import '../../design/glass/glass_menu.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/glass/glass_sheets.dart';
import '../../design/glass/glass_toast.dart';
import '../../design/widgets/artwork.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../design/widgets/media_tiles.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import '../player/player_actions.dart' show showAddToPlaylist;
import 'collection_screens.dart';
import 'section_views.dart';

/// Album page: artwork, artist, Play / Shuffle, numbered tracks, other versions.
class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.id, this.title, this.subtitle, this.artwork});
  final String id;
  final String? title;
  final String? subtitle;
  final String? artwork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(albumPageProvider(id));
    return _CollectionView(
      page: page,
      isAlbum: true,
      placeholderTitle: title ?? 'Album',
      placeholderSubtitle: subtitle,
      placeholderArtwork: artwork,
      onRetry: () => ref.invalidate(albumPageProvider(id)),
    );
  }
}

/// Playlist page (local, automatic or online).
class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.id, this.title, this.subtitle, this.artwork});
  final String id;
  final String? title;
  final String? subtitle;
  final String? artwork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(playlistPageProvider(id));
    return _CollectionView(
      page: page,
      isAlbum: false,
      placeholderTitle: title ?? 'Playlist',
      placeholderSubtitle: subtitle,
      placeholderArtwork: artwork,
      onRetry: () => ref.invalidate(playlistPageProvider(id)),
    );
  }
}

class _CollectionView extends ConsumerWidget {
  const _CollectionView({
    required this.page,
    required this.isAlbum,
    required this.placeholderTitle,
    required this.onRetry,
    this.placeholderSubtitle,
    this.placeholderArtwork,
  });

  final AsyncValue<CollectionPage> page;
  final bool isAlbum;
  final String placeholderTitle;
  final String? placeholderSubtitle;
  final String? placeholderArtwork;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = page.value;
    final engine = ref.read(engineProvider);
    final tracks = data?.tracks ?? const <Track>[];
    final playing = ref.watch(nowPlayingProvider.select((s) => s.track?.id));
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final title = data?.title ?? placeholderTitle;
    final subtitle = data?.subtitle ?? placeholderSubtitle;
    final artwork = data?.thumbnailUrl ?? placeholderArtwork;
    final playlist = data?.playlist;
    final editable = playlist != null && playlist.kind == PlaylistKind.local && playlist.isEditable;
    final artistRef = isAlbum ? data?.album?.artists.where((a) => a.id != null).firstOrNull : null;

    return LargeTitleScaffold(
      title: title,
      showLargeTitle: false,
      titleRevealOffset: 250,
      actions: [
        if (data != null)
          Builder(
            builder: (buttonContext) => GlassIconButton(
              icon: CupertinoIcons.ellipsis,
              size: 40,
              iconSize: 20,
              color: HydeColors.accent,
              semanticLabel: 'More',
              onPressed: () => _showMenu(context, ref, data, globalRectOf(buttonContext)),
            ),
          ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, c) {
              final text = _HeaderText(
                title: title,
                subtitle: subtitle,
                isAlbum: isAlbum,
                data: data,
                artistRef: artistRef,
                center: c.maxWidth < 720,
              );
              // Wide window: cover beside the title, like a desktop music app.
              if (c.maxWidth >= 720) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 12, 12, HydeMetrics.gutter + 12, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Artwork(url: artwork, size: 232, radius: 14, shadow: true),
                      const SizedBox(width: 28),
                      Expanded(child: text),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(72, 4, 72, 16),
                    child: Artwork(url: artwork, radius: 12, shadow: true),
                  ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: text),
                ],
              );
            },
          ),
        ),
        if (data == null)
          SliverToBoxAdapter(
            child: page.hasError
                ? PageStatus.error(message: friendlyError(page.error!), onRetry: onRetry)
                : const PageStatus.loading(),
          )
        else ...[
          SliverToBoxAdapter(
            child: PlayShuffleRow(
              onPlay: tracks.isEmpty ? null : () => guarded(context, () => engine.playTracks(tracks)),
              onShuffle: tracks.isEmpty ? null : () => guarded(context, () => engine.playTracks(tracks, shuffle: true)),
              onSmartShuffle: tracks.length < 3
                  ? null
                  : () async {
                      await guarded(context, () => engine.playTracks(tracks, smart: true));
                      ref.invalidate(settingsProvider);
                    },
            ),
          ),
          SliverToBoxAdapter(child: _ActionRow(page: data, isAlbum: isAlbum)),
          if (tracks.isEmpty)
            SliverToBoxAdapter(
              child: PageStatus.empty(message: editable ? 'No songs yet. Add some from any song’s menu.' : 'No songs here.'),
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
                  leading: isAlbum
                      ? SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}',
                            textAlign: TextAlign.center,
                            style: HydeText.body.copyWith(
                              fontSize: 16,
                              color: tracks[i].id == playing ? HydeColors.accent : secondary,
                            ),
                          ),
                        )
                      : null,
                  onTap: () => guarded(context, () => engine.playTracks(tracks, startIndex: i)),
                  onLongPress: () => showSongMenu(
                    context,
                    ref,
                    tracks[i],
                    globalRectOf(rowContext),
                    playlistId: editable || (playlist?.kind == PlaylistKind.liked) ? data.id : null,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tracks[i].duration > Duration.zero)
                        Text(formatDuration(tracks[i].duration), style: HydeText.footnote.copyWith(color: secondary)),
                      GlassPressable(
                        onTap: () => showSongMenu(
                          context,
                          ref,
                          tracks[i],
                          globalRectOf(rowContext),
                          playlistId: editable || (playlist?.kind == PlaylistKind.liked) ? data.id : null,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                          child: Icon(CupertinoIcons.ellipsis, size: 20, color: secondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!isAlbum && tracks.any((t) => !t.isLocal))
            SliverToBoxAdapter(
              child: _Suggestions(key: ValueKey('suggest-${data.id}'), page: data, editable: editable),
            ),
          if (data.description != null && data.description!.trim().isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 18, HydeMetrics.gutter + 4, 0),
                child: Text(
                  data.description!,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: HydeText.footnote.copyWith(color: secondary, height: 1.35),
                ),
              ),
            ),
          ...sectionSlivers(context, ref, data.related),
        ],
      ],
    );
  }

  void _showMenu(BuildContext context, WidgetRef ref, CollectionPage data, Rect anchor) {
    final engine = ref.read(engineProvider);
    final tracks = data.tracks;
    final playlist = data.playlist;
    final local = playlist != null && playlist.kind == PlaylistKind.local;
    final MediaItem item = isAlbum
        ? AlbumItem(data.album ?? Album(id: data.id, title: data.title, artists: const []))
        : PlaylistItem(playlist ?? Playlist(id: data.id, name: data.title, kind: PlaylistKind.online));
    showGlassMenu(
      context,
      anchor: anchor,
      menu: GlassMenu(
        sections: [
          [
            GlassMenuAction(
              icon: CupertinoIcons.text_insert,
              label: 'Play next',
              onSelected: () => guarded(context, () => engine.playNext(tracks)),
            ),
            GlassMenuAction(
              icon: CupertinoIcons.text_append,
              label: 'Add to queue',
              onSelected: () => guarded(context, () => engine.addToQueue(tracks)),
            ),
            GlassMenuAction(
              icon: CupertinoIcons.text_badge_plus,
              label: 'Add to playlist',
              onSelected: () => showAddToPlaylist(context, ref, tracks),
            ),
          ],
          [
            if (local) ...[
              GlassMenuAction(
                icon: CupertinoIcons.pencil,
                label: 'Rename',
                onSelected: () async {
                  final name = await promptText(context, title: 'Rename Playlist', initial: data.title);
                  if (name != null && name.isNotEmpty) await engine.renamePlaylist(data.id, name);
                },
              ),
              GlassMenuAction(
                icon: CupertinoIcons.trash,
                label: 'Delete playlist',
                destructive: true,
                onSelected: () async {
                  final ok = await confirm(context, title: 'Delete “${data.title}”?', action: 'Delete', destructive: true);
                  if (!ok) return;
                  await engine.deletePlaylist(data.id);
                  if (context.mounted) Navigator.of(context).maybePop();
                },
              ),
            ],
            if (playlist == null || playlist.kind == PlaylistKind.local || playlist.kind == PlaylistKind.online)
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
}

/// Save / download row under Play and Shuffle.
class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.page, required this.isAlbum});
  final CollectionPage page;
  final bool isAlbum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(engineProvider);
    final tracks = page.tracks;
    final kind = page.playlist?.kind;
    final online = !isAlbum && kind == PlaylistKind.online;
    final allDownloaded = tracks.isNotEmpty && tracks.every((t) => t.isDownloaded || t.isLocal);
    final downloads = ref.watch(featureStateProvider('downloads')).value;
    final busy = ((downloads?['progress'] as Map?) ?? const {}).keys.toSet();
    final downloading = tracks.any((t) => busy.contains(t.id));

    Widget action(IconData icon, String label, VoidCallback? onTap, {bool active = false}) => Expanded(
      child: GlassPressable(
        onTap: onTap,
        pressedScale: 0.94,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: active ? HydeColors.accent : HydeColors.label.resolveFrom(context)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HydeText.subhead.copyWith(
                    color: active ? HydeColors.accent : HydeColors.label.resolveFrom(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 2, HydeMetrics.gutter, 8),
      child: Row(
        children: [
          if (isAlbum)
            action(
              page.saved ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.plus_circle,
              page.saved ? 'In Library' : 'Add',
              () => guarded(context, () async {
                await engine.setAlbumSaved(page, !page.saved);
                if (context.mounted) {
                  showGlassToast(
                    context,
                    page.saved ? 'Removed from library' : 'Added to library',
                    icon: CupertinoIcons.checkmark_circle,
                  );
                }
              }),
              active: page.saved,
            ),
          if (online)
            action(
              CupertinoIcons.plus_circle,
              'Save',
              () => guarded(context, () async {
                await engine.importPlaylist(page);
                if (context.mounted) showGlassToast(context, 'Saved to your playlists', icon: CupertinoIcons.checkmark_circle);
              }),
            ),
          action(
            allDownloaded
                ? CupertinoIcons.checkmark_circle_fill
                : downloading
                ? CupertinoIcons.arrow_down_circle_fill
                : CupertinoIcons.arrow_down_circle,
            allDownloaded ? 'Downloaded' : (downloading ? 'Downloading…' : 'Download'),
            tracks.isEmpty
                ? null
                : () => guarded(context, () async {
                    if (allDownloaded) {
                      final ok = await confirm(context, title: 'Remove downloads?', action: 'Remove', destructive: true);
                      if (ok) await engine.removeDownload(tracks);
                    } else {
                      await engine.download(tracks);
                      if (context.mounted) showGlassToast(context, 'Downloading ${tracks.length} songs', icon: CupertinoIcons.arrow_down_circle);
                    }
                  }),
            active: allDownloaded || downloading,
          ),
          if (tracks.isNotEmpty && !tracks.first.isLocal)
            action(
              CupertinoIcons.dot_radiowaves_left_right,
              'Radio',
              () => guarded(context, () => engine.startRadio(tracks.first)),
            ),
        ],
      ),
    );
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return m >= 60 ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:$s' : '$m:$s';
}

Future<String?> promptText(BuildContext context, {required String title, String initial = '', String placeholder = 'Name'}) async {
  final controller = TextEditingController(text: initial);
  final result = await showGlassDialog<String>(
    context: context,
    builder: (context) => GlassAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          controller: controller,
          autofocus: true,
          placeholder: placeholder,
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
      ),
      actions: [
        GlassDialogAction(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        GlassDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return result;
}

Future<bool> confirm(BuildContext context, {required String title, String? message, required String action, bool destructive = false}) async {
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (context) => GlassAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        GlassDialogAction(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        GlassDialogAction(
          isDestructiveAction: destructive,
          isDefaultAction: !destructive,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Artist page: portrait header, Shuffle / Radio / Follow, then shelves.
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.id, this.name, this.artwork});
  final String id;
  final String? name;
  final String? artwork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(artistPageProvider(id));
    final data = page.value;
    final engine = ref.read(engineProvider);
    final title = data?.artist.name ?? name ?? 'Artist';
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final image = data?.artist.thumbnailUrl ?? artwork;

    Widget pill(IconData icon, String label, VoidCallback onTap, {bool filled = false}) => GlassPressable(
      onTap: onTap,
      pressedScale: 0.95,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: filled ? HydeColors.accent : HydeColors.groupedFill.resolveFrom(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: filled ? const Color(0xFFFFFFFF) : HydeColors.accent),
            const SizedBox(width: 7),
            Text(
              label,
              style: HydeText.headline.copyWith(fontSize: 15, color: filled ? const Color(0xFFFFFFFF) : HydeColors.accent),
            ),
          ],
        ),
      ),
    );

    final topSongs = [
      for (final s in data?.sections ?? const <HomeSection>[])
        if (s.style == HomeSectionStyle.quickPicks)
          for (final i in s.items)
            if (i is TrackItem) i.track,
    ];

    return LargeTitleScaffold(
      title: title,
      showLargeTitle: false,
      titleRevealOffset: 230,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              const SizedBox(height: 4),
              Artwork(url: image, size: 190, circle: true, shadow: true, placeholderIcon: CupertinoIcons.mic_fill),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HydeText.title1.copyWith(color: HydeColors.label.resolveFrom(context)),
                ),
              ),
              if (data?.subscriberText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    data!.subscriberText!.toLowerCase().contains('subscriber')
                        ? data.subscriberText!
                        : '${data.subscriberText} subscribers',
                    style: HydeText.footnote.copyWith(color: secondary)),
                ),
            ],
          ),
        ),
        if (data == null)
          SliverToBoxAdapter(
            child: page.hasError
                ? PageStatus.error(message: friendlyError(page.error!), onRetry: () => ref.invalidate(artistPageProvider(id)))
                : const PageStatus.loading(),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 2),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (data.shufflePlaylistId != null || topSongs.isNotEmpty)
                    pill(
                      CupertinoIcons.shuffle,
                      'Shuffle',
                      () => guarded(
                        context,
                        () => data.shufflePlaylistId != null
                            ? engine.playOnline(playlistId: data.shufflePlaylistId, shuffle: true)
                            : engine.playTracks(topSongs, shuffle: true),
                      ),
                      filled: true,
                    ),
                  if (data.radioPlaylistId != null)
                    pill(
                      CupertinoIcons.dot_radiowaves_left_right,
                      'Radio',
                      () => guarded(context, () => engine.playOnline(playlistId: data.radioPlaylistId)),
                    ),
                  pill(
                    data.artist.subscribed ? CupertinoIcons.checkmark : CupertinoIcons.plus,
                    data.artist.subscribed ? 'Following' : 'Follow',
                    () => guarded(context, () async {
                      await engine.setArtistFollowed(data.artist, !data.artist.subscribed);
                      ref.invalidate(artistPageProvider(id));
                    }),
                  ),
                ],
              ),
            ),
          ),
          if (data.sections.isEmpty) const SliverToBoxAdapter(child: PageStatus.empty(message: 'Nothing here yet.')),
          ...sectionSlivers(context, ref, data.sections),
          if (data.description != null && data.description!.trim().isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader(title: 'About')),
            SliverToBoxAdapter(child: _Expandable(text: data.description!)),
          ],
        ],
      ],
    );
  }
}

class _Expandable extends StatefulWidget {
  const _Expandable({required this.text});
  final String text;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4),
        child: Text(
          widget.text,
          maxLines: _open ? null : 4,
          overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis,
          style: HydeText.subhead.copyWith(height: 1.4, color: HydeColors.secondaryLabel.resolveFrom(context)),
        ),
      ),
    );
  }
}

/// A YouTube Music shelf page: explore, charts, a mood, "see all".
class BrowseScreen extends ConsumerWidget {
  const BrowseScreen({super.key, required this.browseId, this.params, this.title});
  final String browseId;
  final String? params;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (browseId, params);
    final page = ref.watch(browsePageProvider(key));
    final data = page.value;
    final sections = data?.sections ?? const <HomeSection>[];
    // A page that is one long shelf reads better as a grid / list.
    final single = sections.length == 1 ? sections.first : null;
    return LargeTitleScaffold(
      title: title ?? data?.title ?? 'Browse',
      slivers: [
        if (data == null)
          SliverToBoxAdapter(
            child: page.hasError
                ? PageStatus.error(message: friendlyError(page.error!), onRetry: () => ref.invalidate(browsePageProvider(key)))
                : const PageStatus.loading(),
          )
        else if (sections.isEmpty)
          const SliverToBoxAdapter(child: PageStatus.empty(message: 'Nothing here right now.'))
        else if (single != null)
          ...itemsSlivers(context, ref, single.items)
        else
          ...sectionSlivers(context, ref, sections),
      ],
    );
  }
}

/// A shelf shown in full: songs as rows, everything else as a grid.
List<Widget> itemsSlivers(BuildContext context, WidgetRef ref, List<MediaItem> items) {
  final moods = [for (final i in items) if (i is BrowseItem) i];
  if (moods.length == items.length) {
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: 46,
          ),
          itemCount: moods.length,
          itemBuilder: (context, i) => MoodTile(item: moods[i], onTap: () => openMediaItem(context, ref, moods[i])),
        ),
      ),
    ];
  }
  final tracks = [for (final i in items) if (i is TrackItem) i.track];
  if (tracks.length > items.length / 2) {
    final engine = ref.read(engineProvider);
    return [
      SliverToBoxAdapter(
        child: PlayShuffleRow(
          onPlay: () => guarded(context, () => engine.playTracks(tracks)),
          onShuffle: () => guarded(context, () => engine.playTracks(tracks, shuffle: true)),
        ),
      ),
      SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, i) => Builder(
          builder: (rowContext) => MediaRow(
            item: items[i],
            onTap: () => items[i] is TrackItem
                ? guarded(context, () => engine.playTracks(tracks, startIndex: tracks.indexOf((items[i] as TrackItem).track)))
                : openMediaItem(context, ref, items[i]),
            onLongPress: () => showItemMenu(context, ref, items[i], globalRectOf(rowContext)),
          ),
        ),
      ),
    ];
  }
  return [ItemGridSliver(items: items)];
}

/// "See all" for a shelf that has no server page.
class ItemsScreen extends ConsumerWidget {
  const ItemsScreen({super.key, required this.title, required this.items});
  final String title;
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      LargeTitleScaffold(title: title, slivers: itemsSlivers(context, ref, items));
}

/// Title, artist and details beside (desktop) or under (narrow) the cover.
class _HeaderText extends StatelessWidget {
  const _HeaderText({
    required this.title,
    required this.subtitle,
    required this.isAlbum,
    required this.data,
    required this.artistRef,
    required this.center,
  });
  final String title;
  final String? subtitle;
  final bool isAlbum;
  final CollectionPage? data;
  final ArtistRef? artistRef;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    final d = data;
    final artist = artistRef;
    final sub = subtitle;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (!center)
          Text(
            isAlbum ? 'ALBUM' : 'PLAYLIST',
            style: HydeText.caption.copyWith(letterSpacing: 1, color: HydeColors.secondaryLabel.resolveFrom(context)),
          ),
        Text(
          title,
          textAlign: align,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: (center ? HydeText.title3 : HydeText.largeTitle.copyWith(fontSize: 38))
              .copyWith(color: HydeColors.label.resolveFrom(context)),
        ),
        if (sub != null && sub.isNotEmpty)
          MouseRegion(
            cursor: artist == null ? MouseCursor.defer : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: artist == null
                  ? null
                  : () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(builder: (_) => ArtistScreen(id: artist.id!, name: artist.name)),
                    ),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  isAlbum && d?.album != null && d!.album!.artists.isNotEmpty ? d.album!.artistLine : sub,
                  textAlign: align,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HydeText.title3.copyWith(fontWeight: FontWeight.w400, color: HydeColors.accent),
                ),
              ),
            ),
          ),
        if (d != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [
                if (isAlbum && d.subtitle != null) d.subtitle!,
                if (d.secondSubtitle != null) d.secondSubtitle!,
              ].join(' • '),
              textAlign: align,
              style: HydeText.footnote.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
            ),
          ),
      ],
    );
  }
}

/// "Suggested Songs" under a playlist: YouTube Music radio for a few of its
/// songs, without the ones it already has. Your own playlists get a + to add
/// each one; any list can be refreshed or AI-shuffled.
class _Suggestions extends ConsumerStatefulWidget {
  const _Suggestions({super.key, required this.page, required this.editable});
  final CollectionPage page;
  final bool editable;

  @override
  ConsumerState<_Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends ConsumerState<_Suggestions> {
  static const _shown = 10;
  List<Track>? _items;
  bool _loading = false;
  bool _failed = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final tracks = widget.page.tracks;
      final items = await ref.read(engineProvider).suggestions(tracks, exclude: {for (final t in tracks) t.id});
      if (mounted) {
        setState(() {
          _items = items;
          _expanded = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(Track t) async {
    await guarded(context, () => ref.read(engineProvider).addToPlaylist(widget.page.id, [t]));
    if (!mounted) return;
    setState(() => _items = [...?_items]..remove(t));
    showGlassToast(context, 'Added to ${widget.page.title}', icon: CupertinoIcons.checkmark_circle);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? const <Track>[];
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    if (!_loading && !_failed && _items != null && items.isEmpty) return const SizedBox.shrink();
    final visible = _expanded ? items : items.take(_shown).toList();
    final engine = ref.read(engineProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 30, HydeMetrics.gutter, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Suggested Songs', style: HydeText.title2.copyWith(color: HydeColors.label.resolveFrom(context))),
                    Text(
                      widget.editable ? 'Based on what’s in this playlist' : 'More like this playlist',
                      style: HydeText.footnote.copyWith(color: secondary),
                    ),
                  ],
                ),
              ),
              if (items.length > 2)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(36, 36),
                  onPressed: () async {
                    await guarded(context, () => engine.playTracks(items, smart: true));
                    ref.invalidate(settingsProvider);
                  },
                  child: const Icon(CupertinoIcons.sparkles, size: 21, color: HydeColors.accent),
                ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(36, 36),
                onPressed: _loading ? null : _load,
                child: _loading
                    ? const CupertinoActivityIndicator(radius: 9)
                    : const Icon(CupertinoIcons.arrow_clockwise, size: 20, color: HydeColors.accent),
              ),
            ],
          ),
        ),
        if (_failed && items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4, vertical: 12),
            child: Text('Couldn’t load suggestions', style: HydeText.subhead.copyWith(color: secondary)),
          )
        else if (_items == null)
          const Padding(padding: EdgeInsets.all(24), child: CupertinoActivityIndicator()),
        for (final (i, t) in visible.indexed)
          Builder(
            builder: (rowContext) => MediaRow(
              key: ValueKey('sugg-${t.id}'),
              item: TrackItem(t),
              dense: true,
              onTap: () => guarded(context, () => engine.playTracks(items, startIndex: i)),
              onLongPress: () => showSongMenu(context, ref, t, globalRectOf(rowContext)),
              trailing: widget.editable
                  ? CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(36, 36),
                      onPressed: () => _add(t),
                      child: const Icon(CupertinoIcons.plus_circle, size: 24, color: HydeColors.accent),
                    )
                  : GlassPressable(
                      onTap: () => showSongMenu(context, ref, t, globalRectOf(rowContext)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                        child: Icon(CupertinoIcons.ellipsis, size: 20, color: secondary),
                      ),
                    ),
            ),
          ),
        if (!_expanded && items.length > _shown)
          CupertinoButton(
            onPressed: () => setState(() => _expanded = true),
            child: Text('Show ${items.length - _shown} more', style: HydeText.subhead.copyWith(color: HydeColors.accent)),
          ),
      ],
    );
  }
}
