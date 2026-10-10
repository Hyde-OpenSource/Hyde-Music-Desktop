import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as svc;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../hyde_engine.dart';
import '../models.dart';
import 'codec.dart';
import 'database.dart';
import 'downloader.dart';
import 'features.dart';
import 'innertube.dart';
import 'lyrics.dart';
import 'player.dart';
import 'settings_store.dart';
import 'stream_resolver.dart';
import 'updater.dart';
import 'youtube.dart';
import 'yt_parser.dart';

/// The app's engine, entirely in Dart: just_audio + audio_service playback,
/// YouTube Music over InnerTube, the song.db library, lyrics, downloads,
/// updater. See docs/04_ARCHITECTURE.md.
class DartEngine implements HydeEngine {
  DartEngine._({
    required this.db,
    required this.settings,
    required this.tube,
    required this.youtube,
    required this.resolver,
    required this.player,
    required this.lyricsService,
    required this.downloader,
    required this.updater,
    required this.dirs,
  });

  final HydeDatabase db;
  final SettingsStore settings;
  final InnerTube tube;
  final YouTube youtube;
  final StreamResolver resolver;
  final HydePlayer player;
  final LyricsService lyricsService;
  final Downloader downloader;
  final Updater updater;
  final ({Directory documents, Directory cache, Directory support}) dirs;

  static const host = MethodChannel('hyde/host');

  late final Features _features = Features(this);
  final _libraryChanged = StreamController<void>.broadcast();
  final _navigation = StreamController<NavigationEvent>.broadcast();
  final _featureEvents = StreamController<Map<String, Object?>>.broadcast();

  static Future<DartEngine> create() async {
    final documents = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final cache = await getTemporaryDirectory();

    final db = await HydeDatabase.open();
    // Native DataStore lived in <files>/datastore/settings.preferences_pb.
    final settings = await SettingsStore.open(
      legacyDataStore: File(p.join(support.path, 'datastore', 'settings.preferences_pb')),
    );

    final tube = InnerTube();
    final youtube = YouTube(tube);
    final resolver = StreamResolver(tube);
    final info = await PackageInfo.fromPlatform();

    HydePlayer build() => HydePlayer(
      db: db,
      resolver: resolver,
      youtube: youtube,
      setting: (key) => settings[key],
      queueFile: File(p.join(support.path, 'queue.json')),
    );
    // audio_service (notification, lock screen, media buttons) is mobile
    // only; on desktop the handler runs on its own.
    final player = !(Platform.isAndroid || Platform.isIOS)
        ? build()
        : await svc.AudioService.init(
            builder: build,
            config: const svc.AudioServiceConfig(
              androidNotificationChannelId: 'iad1tya.echo.music.playback',
              androidNotificationChannelName: 'Playback',
              androidNotificationIcon: 'drawable/ic_notification',
              androidNotificationOngoing: true,
              androidStopForegroundOnPause: true,
            ),
          );

    final engine = DartEngine._(
      db: db,
      settings: settings,
      tube: tube,
      youtube: youtube,
      resolver: resolver,
      player: player,
      lyricsService: LyricsService(db, youtube),
      downloader: Downloader(db: db, resolver: resolver, directory: Directory(p.join(documents.path, 'downloads'))),
      updater: Updater(settings: settings, currentVersion: info.version, cacheDir: cache, host: host),
      dirs: (documents: documents, cache: cache, support: support),
    );
    await engine._start();
    return engine;
  }

  Future<void> _start() async {
    await _applyAccount();
    _applyLocale();
    await player.init();

    player.onListened = (track, listened) {
      _libraryChanged.add(null);
      _homeCache = null;
      _features.onListened(track, listened);
    };
    player.onTrackChanged = _features.onTrackChanged;

    downloader.onChanged = (id, downloaded) {
      player.patchTrack(id, (t) => t.copyWith(isDownloaded: downloaded));
      _libraryChanged.add(null);
    };
    downloader.events.listen(_featureEvents.add);

    host.setMethodCallHandler((call) async {
      if (call.method == 'onIntent') _handleIntent((call.arguments as Map).cast<String, Object?>());
    });
    // Link / share that launched the app.
    unawaited(() async {
      try {
        final initial = await host.invokeMethod<Map>('initialIntent');
        if (initial != null) _handleIntent(initial.cast<String, Object?>());
      } catch (_) {}
    }());
    _applyWindowFlags();
    // Android 13+: without this the playback notification isn't shown.
    unawaited(Permission.notification.request().then<void>((_) {}).catchError((_) {}));
    unawaited(updater.autoCheck());
    unawaited(_features.start());
  }

  /// Sign-in state: the active row of the native `account` table, else the
  /// DataStore keys the old app used.
  Future<void> _applyAccount() async {
    final account = await db.activeAccount();
    final cookie = (account?['innerTubeCookie'] as String?) ?? settings.string('innerTubeCookie');
    tube.cookie = cookie;
    final visitor = (account?['visitorData'] as String?) ?? settings.string('visitorData');
    if (visitor != null && visitor.isNotEmpty) tube.visitorData = visitor;
    final sync = (account?['dataSyncId'] as String?) ?? settings.string('dataSyncId');
    // Stored as "id||" by the web client; InnerTube wants the id only.
    tube.dataSyncId = (sync == null || sync.isEmpty) ? null : sync.split('||').first;
    tube.useLoginForBrowse = settings.boolean('useLoginForBrowse', true);
  }

  void _applyLocale() {
    final lang = settings.string('contentLanguage');
    final country = settings.string('contentCountry');
    if (lang != null && lang.isNotEmpty && lang != 'system') tube.hl = lang;
    if (country != null && country.isNotEmpty && country != 'system') tube.gl = country.toUpperCase();
  }

  /// Block screenshots / keep the screen awake, as chosen in Settings.
  void _applyWindowFlags() {
    unawaited(
      host
          .invokeMethod<void>('windowFlags', {
            'secure': _bool('disableScreenshot'),
            'keepScreenOn': _bool('keepScreenOn'),
          })
          .catchError((_) {}),
    );
  }

  Future<void> reloadAccount() async {
    await _applyAccount();
    _homeCache = null;
    _libraryChanged.add(null);
  }

  void notifyLibraryChanged() {
    _homeCache = null;
    _libraryChanged.add(null);
  }

  void emitFeature(Map<String, Object?> event) {
    if (!_featureEvents.isClosed) _featureEvents.add(event);
  }

  bool _bool(String key, [bool fallback = false]) => settings.boolean(key, fallback);

  // ── Playback ────────────────────────────────────────────────────────────

  @override
  Stream<PlaybackSnapshot> get playback => player.snapshots;

  @override
  PlaybackSnapshot get currentPlayback => player.current;

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false, bool smart = false}) async {
    // The Shuffle / AI Shuffle buttons also choose the queue's shuffle style.
    if (shuffle || smart) await settings.write('smartShuffleEnabled', smart);
    await player.playTracks(tracks, startIndex: startIndex, shuffle: shuffle || smart);
  }

  @override
  Future<void> playPause() => player.hasRestoredQueue ? player.resumeRestored() : player.playPause();

  @override
  Future<void> next() => player.skipToNext();

  @override
  Future<void> previous() => player.skipToPrevious();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> setShuffle(bool enabled, {bool? smart}) async {
    if (smart != null) {
      await settings.write('smartShuffleEnabled', smart);
      // Switching style while shuffled: rebuild the order.
      if (enabled && player.isShuffled) await player.setShuffle(false);
    }
    await player.setShuffle(enabled);
  }

  @override
  Future<void> setRepeat(QueueRepeat mode) => player.setRepeat(mode);

  @override
  Future<void> setVolume(double volume) => player.setUserVolume(volume);

  @override
  Future<void> playNext(List<Track> tracks) => player.playNext(tracks);

  @override
  Future<void> addToQueue(List<Track> tracks) => player.addToQueue(tracks);

  @override
  Future<void> moveQueueItem(int from, int to) => player.moveQueueItem(from, to);

  @override
  Future<void> removeQueueItem(int index) => player.removeAt(index);

  @override
  Future<void> skipToQueueItem(int index) => player.skipToIndex(index);

  @override
  Future<void> startRadio(Track seed) => player.startRadio(seed);

  @override
  Future<void> playOnline({String? playlistId, String? videoId, String? params, bool shuffle = false}) async {
    final page = await youtube.next(videoId: videoId, playlistId: playlistId, params: params);
    final tracks = await _visible(await db.decorate(page.tracks));
    if (tracks.isEmpty) throw StateError('Nothing to play');
    await player.playTracks(tracks, startIndex: shuffle ? 0 : (page.currentIndex ?? 0), shuffle: shuffle, radio: false);
    await player.setRadioContinuation(
      continuation: page.continuation,
      playlistId: page.playlistId,
      params: page.params,
    );
  }

  @override
  Future<void> setSleepTimer(Duration? duration, {bool endOfTrack = false}) async =>
      player.setSleepTimer(duration, endOfTrack: endOfTrack);

  @override
  Future<void> setPlaybackParameters({required double speed, required double pitch}) =>
      player.setPlaybackParameters(speed: speed, pitch: pitch);

  @override
  Future<({double speed, double pitch})> playbackParameters() async => player.playbackParameters;

  // ── Library actions ─────────────────────────────────────────────────────

  @override
  Future<void> setLiked(Track track, bool liked) async {
    await db.setLiked(track, liked);
    player.patchTrack(track.id, (t) => t.copyWith(liked: liked, inLibrary: liked ? true : null));
    notifyLibraryChanged();
    if (!track.isLocal && tube.signedIn && _bool('ytmSync', true)) {
      unawaited(tube.like(track.id, liked).catchError((_) {}));
    }
    _features.onLiked(track, liked);
    if (liked && _bool('autoDownloadOnLike')) downloader.enqueue([track]);
  }

  @override
  Future<void> setInLibrary(Track track, bool inLibrary) async {
    await db.setInLibrary(track, inLibrary);
    player.patchTrack(track.id, (t) => t.copyWith(inLibrary: inLibrary));
    notifyLibraryChanged();
  }

  @override
  Future<void> download(List<Track> tracks) async {
    await db.ensureTracks(tracks);
    downloader.enqueue(tracks);
  }

  @override
  Future<void> removeDownload(List<Track> tracks) => downloader.remove(tracks);

  @override
  Future<void> addToPlaylist(String playlistId, List<Track> tracks) async {
    if (playlistId.startsWith('auto:')) {
      if (playlistId == 'auto:liked') {
        for (final t in tracks) {
          await setLiked(t, true);
        }
      }
      return;
    }
    await db.addToPlaylist(playlistId, tracks);
    notifyLibraryChanged();
    final row = await db.playlistRow(playlistId);
    final browseId = row?['browseId'] as String?;
    if (browseId != null && tube.signedIn && row?['isEditable'] != 0) {
      unawaited(
        tube
            .editPlaylist(browseId, [
              for (final t in tracks)
                if (!t.isLocal) {'action': 'ACTION_ADD_VIDEO', 'addedVideoId': t.id},
            ])
            .catchError((_) => <String, Object?>{}),
      );
    }
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final playlist = await db.createPlaylist(name);
    notifyLibraryChanged();
    return playlist;
  }

  @override
  Future<void> renamePlaylist(String playlistId, String name) async {
    await db.renamePlaylist(playlistId, name);
    notifyLibraryChanged();
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await db.deletePlaylist(playlistId);
    notifyLibraryChanged();
  }

  @override
  Future<void> removeFromPlaylist(String playlistId, Track track) async {
    if (playlistId == 'auto:liked') return setLiked(track, false);
    if (playlistId == 'auto:downloaded') return removeDownload([track]);
    await db.removeFromPlaylist(playlistId, track.id);
    notifyLibraryChanged();
  }

  @override
  Future<void> movePlaylistTrack(String playlistId, int from, int to) async {
    await db.movePlaylistSong(playlistId, from, to);
    notifyLibraryChanged();
  }

  @override
  Future<Playlist> importPlaylist(CollectionPage page) async {
    final existing = await db.playlistRow(page.id);
    final Playlist playlist;
    if (existing != null) {
      playlist = Playlist(id: existing['id'] as String, name: existing['name'] as String);
    } else {
      playlist = await db.createPlaylist(
        page.title,
        browseId: page.playlist?.kind == PlaylistKind.online ? page.id : null,
        thumbnailUrl: page.thumbnailUrl,
        editable: page.playlist?.kind != PlaylistKind.online,
      );
    }
    await db.setPlaylistSongs(playlist.id, page.tracks);
    notifyLibraryChanged();
    return playlist;
  }

  @override
  Future<void> setAlbumSaved(CollectionPage album, bool saved) async {
    final a =
        album.album ?? Album(id: album.id, title: album.title, artists: const [], thumbnailUrl: album.thumbnailUrl);
    await db.saveAlbum(a, album.tracks, bookmarked: saved);
    notifyLibraryChanged();
  }

  @override
  Future<void> setArtistFollowed(Artist artist, bool followed) async {
    await db.setArtistBookmarked(artist, followed);
    notifyLibraryChanged();
    final channel = artist.channelId ?? (artist.id.startsWith('UC') ? artist.id : null);
    if (channel != null && tube.signedIn && _bool('ytmSync', true)) {
      unawaited(tube.subscribe(channel, followed).catchError((_) {}));
    }
  }

  @override
  Stream<void> get libraryChanged => _libraryChanged.stream;

  @override
  Future<String> shareLink(MediaItem item) async => switch (item) {
    TrackItem(:final track) => 'https://music.youtube.com/watch?v=${track.id}',
    AlbumItem(:final album) =>
      album.playlistId != null
          ? 'https://music.youtube.com/playlist?list=${album.playlistId}'
          : 'https://music.youtube.com/browse/${album.id}',
    ArtistItem(:final artist) => 'https://music.youtube.com/channel/${artist.id}',
    PlaylistItem(:final playlist) => await _playlistShareLink(playlist),
    BrowseItem(:final browseId) => 'https://music.youtube.com/browse/$browseId',
  };

  Future<String> _playlistShareLink(Playlist playlist) async {
    if (playlist.kind == PlaylistKind.online) return 'https://music.youtube.com/playlist?list=${playlist.id}';
    final row = await db.playlistRow(playlist.id);
    final browseId = row?['browseId'] as String?;
    if (browseId != null) return 'https://music.youtube.com/playlist?list=$browseId';
    // A local playlist has no URL: share it as a watch link of its songs.
    final ids = (await playlistTracks(playlist.id)).where((t) => !t.isLocal).take(50).map((t) => t.id).join(',');
    return ids.isEmpty ? playlist.name : 'https://www.youtube.com/watch_videos?video_ids=$ids';
  }

  // ── Content filters ─────────────────────────────────────────────────────

  Future<List<Track>> _visible(List<Track> tracks) async {
    final hideExplicit = _bool('hideExplicit');
    final hideVideos = _bool('hideVideoSongs');
    // Always a new, growable list: callers shuffle it, and the database can
    // hand back a read-only one (a fresh library returns `const []`).
    if (!hideExplicit && !hideVideos) return List.of(tracks);
    return [
      for (final t in tracks)
        if (!(hideExplicit && t.explicit) && !(hideVideos && t.isVideo)) t,
    ];
  }

  bool _allowed(MediaItem i) {
    if (i is TrackItem) {
      if (_bool('hideExplicit') && i.track.explicit) return false;
      if (_bool('hideVideoSongs') && i.track.isVideo) return false;
    }
    if (i is AlbumItem && _bool('hideExplicit') && i.album.explicit) return false;
    return true;
  }

  /// Filters by the content settings and stamps liked / library / downloaded.
  Future<List<MediaItem>> _prepare(List<MediaItem> items) async {
    final kept = items.where(_allowed).toList();
    final tracks = [
      for (final i in kept)
        if (i is TrackItem) i.track,
    ];
    if (tracks.isEmpty) return kept;
    final flags = await db.flags(tracks.map((t) => t.id));
    if (flags.isEmpty) return kept;
    return [
      for (final i in kept)
        if (i is TrackItem && flags[i.track.id] != null)
          TrackItem(
            i.track.copyWith(
              liked: flags[i.track.id]!.liked,
              inLibrary: flags[i.track.id]!.inLibrary,
              isDownloaded: flags[i.track.id]!.downloaded,
            ),
          )
        else
          i,
    ];
  }

  Future<List<HomeSection>> _prepareSections(List<HomeSection> sections) async {
    final out = <HomeSection>[];
    for (final s in sections) {
      final items = await _prepare(s.items);
      if (items.isEmpty) continue;
      out.add(
        HomeSection(
          title: s.title,
          label: s.label,
          items: items,
          style: s.style,
          moreBrowseId: s.moreBrowseId,
          moreParams: s.moreParams,
          thumbnailUrl: s.thumbnailUrl,
        ),
      );
    }
    return out;
  }

  // ── Home ─────────────────────────────────────────────────────────────────

  HomeFeed? _homeCache;
  DateTime _homeCachedAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<HomeFeed> home({bool refresh = false, String? chipParams}) async {
    if (chipParams != null) {
      final feed = await youtube.home(params: chipParams);
      return HomeFeed(
        sections: await _prepareSections(feed.sections),
        chips: feed.chips,
        continuation: feed.continuation,
      );
    }
    final cached = _homeCache;
    if (!refresh && cached != null && DateTime.now().difference(_homeCachedAt) < const Duration(minutes: 30)) {
      return cached;
    }

    // Everything in parallel; each online part is optional so Home still
    // shows the personal sections offline.
    Future<T?> optional<T>(Future<T> f, [Duration limit = const Duration(seconds: 12)]) =>
        f.timeout(limit).then<T?>((v) => v).catchError((_) => null);

    final personalF = _personalSections();
    final feedF = optional(youtube.home());
    final exploreF = optional(youtube.explore());
    final similarF = optional(_similarSections(), const Duration(seconds: 10));
    final accountF = optional(_accountPlaylists(), const Duration(seconds: 10));

    final personal = await personalF;
    final feed = await feedF;
    final explore = await exploreF;
    final similar = await similarF ?? const <HomeSection>[];
    final account = await accountF;

    if (feed == null && personal.isEmpty) {
      throw const SocketException('Couldn’t reach YouTube Music');
    }

    // Order (native HomeScreen): quick picks, keep listening, account
    // playlists, then YouTube shelves interleaved with "similar to", then
    // forgotten favorites, new releases and moods.
    final quick = personal.where((s) => s.style == HomeSectionStyle.quickPicks && s.title == 'Quick picks').toList();
    final forgotten = personal.where((s) => s.title == 'Forgotten favorites').toList();
    final rest = personal.where((s) => !quick.contains(s) && !forgotten.contains(s)).toList();
    final ytSections = [...?feed?.sections];
    // YouTube sends its own "Quick picks" shelf; keep ours when we have one.
    if (quick.isNotEmpty) ytSections.removeWhere((s) => s.title.toLowerCase() == 'quick picks');

    final sections = <HomeSection>[...quick, ...rest, ?account];
    for (var i = 0; i < ytSections.length; i++) {
      sections.add(ytSections[i]);
      if (i.isOdd && similar.length > i ~/ 2) sections.add(similar[i ~/ 2]);
    }
    sections.addAll(similar.skip(ytSections.length ~/ 2));
    sections.addAll(forgotten);
    for (final s in explore?.sections ?? const <HomeSection>[]) {
      if (s.title.isEmpty) continue;
      if (s.moreBrowseId == 'FEmusic_new_releases_albums' || s.style == HomeSectionStyle.moods) sections.add(s);
    }

    if (_bool('randomizeHomeOrder') && sections.length > 2) {
      // Keep the first shelf where people expect it; shuffle the rest.
      final rest = sections.sublist(1)..shuffle();
      sections
        ..removeRange(1, sections.length)
        ..addAll(rest);
    }

    final result = HomeFeed(
      sections: await _prepareSections(sections),
      chips: feed?.chips ?? const [],
      continuation: feed?.continuation,
    );
    if (feed != null) {
      _homeCache = result;
      _homeCachedAt = DateTime.now();
    }
    return result;
  }

  @override
  Future<HomeFeed> homeMore(String continuation) async {
    final feed = await youtube.home(continuation: continuation);
    return HomeFeed(sections: await _prepareSections(feed.sections), continuation: feed.continuation);
  }

  Future<List<HomeSection>> _personalSections() async {
    final out = <HomeSection>[];
    final twoWeeks = HydeDatabase.now() - 14 * 86400000;

    var picks = <Track>[];
    if (settings.string('discover') == 'LAST_LISTEN') {
      final last = await db.lastPlayed();
      if (last != null) {
        picks = (await db.quickPicks()).toList(); // related to recent plays, newest weighted first
      }
    } else {
      picks = await db.quickPicks();
    }
    picks = (await _visible(picks))..shuffle();
    if (picks.length >= 4) {
      out.add(
        HomeSection(
          title: 'Quick picks',
          label: 'Start radio from a song',
          style: HomeSectionStyle.quickPicks,
          items: [for (final t in picks.take(20)) TrackItem(t)],
        ),
      );
    }

    final songs = await db.mostPlayedSongs(twoWeeks, limit: 12);
    final albums = await db.mostPlayedAlbums(twoWeeks, limit: 6);
    final artists = await db.mostPlayedArtists(twoWeeks, limit: 6);
    final keep = <MediaItem>[
      for (final s in songs) TrackItem(s.track),
      for (final a in albums)
        if (a.album.thumbnailUrl != null && a.album.id.startsWith('MPRE')) AlbumItem(a.album),
      for (final a in artists)
        if (a.artist.thumbnailUrl != null && a.artist.id.startsWith('UC')) ArtistItem(a.artist),
    ]..shuffle();
    if (keep.length >= 3) out.add(HomeSection(title: 'Keep listening', items: keep.take(16).toList()));

    final playlists = await db.playlists();
    if (playlists.isNotEmpty) {
      out.add(HomeSection(title: 'Your playlists', items: [for (final pl in playlists.take(12)) PlaylistItem(pl)]));
    }

    final forgotten = (await _visible(await db.forgottenFavorites()))..shuffle();
    if (forgotten.length >= 4) {
      out.add(
        HomeSection(
          title: 'Forgotten favorites',
          style: HomeSectionStyle.quickPicks,
          items: [for (final t in forgotten.take(20)) TrackItem(t)],
        ),
      );
    }
    return out;
  }

  /// "Similar to <artist>" rows from the pages of the most played artists.
  Future<List<HomeSection>> _similarSections() async {
    final twoWeeks = HydeDatabase.now() - 14 * 86400000;
    final top = (await db.mostPlayedArtists(twoWeeks, limit: 10)).where((a) => a.artist.id.startsWith('UC')).toList()
      ..shuffle();
    final pages = await Future.wait([
      for (final a in top.take(3)) youtube.artist(a.artist.id).then<ArtistPage?>((v) => v).catchError((_) => null),
    ]);
    final out = <HomeSection>[];
    for (final page in pages) {
      if (page == null || page.sections.length < 2) continue;
      unawaited(db.updateArtistArtwork(page.artist.id, page.artist.thumbnailUrl).catchError((_) {}));
      // Last shelves of an artist page: "Fans might also like", playlists, featured on.
      final items = [...page.sections[page.sections.length - 2].items, ...page.sections.last.items]..shuffle();
      if (items.isEmpty) continue;
      out.add(
        HomeSection(
          title: page.artist.name,
          label: 'Similar to',
          items: items.take(16).toList(),
          thumbnailUrl: page.artist.thumbnailUrl,
        ),
      );
    }
    return out;
  }

  Future<HomeSection?> _accountPlaylists() async {
    if (!tube.signedIn) return null;
    final items = (await youtube.library('FEmusic_liked_playlists'))
        .whereType<PlaylistItem>()
        .where((pl) => pl.playlist.id != 'SE' && pl.playlist.id != 'LM')
        .toList();
    return items.isEmpty ? null : HomeSection(title: 'From your account', items: items);
  }

  @override
  Future<({String? title, List<HomeSection> sections})> browse(String browseId, {String? params}) async {
    final page = await youtube.browse(browseId, params: params);
    return (title: page.title, sections: await _prepareSections(page.sections));
  }

  // ── Pages ────────────────────────────────────────────────────────────────

  @override
  Future<ArtistPage> artist(String artistId) async {
    if (!artistId.startsWith('UC') && !artistId.startsWith('MP')) {
      // Local-only artist: the songs we have.
      final songs = await db.artistSongs(artistId);
      final row = (await db.libraryArtists()).where((a) => a.id == artistId).firstOrNull;
      return ArtistPage(
        artist: row ?? Artist(id: artistId, name: songs.firstOrNull?.artistLine ?? 'Artist'),
        sections: [
          if (songs.isNotEmpty)
            HomeSection(
              title: 'Songs',
              style: HomeSectionStyle.quickPicks,
              items: [for (final t in songs) TrackItem(t)],
            ),
        ],
      );
    }
    try {
      final page = await youtube.artist(artistId);
      unawaited(db.updateArtistArtwork(artistId, page.artist.thumbnailUrl).catchError((_) {}));
      final followed = await db.isArtistBookmarked(artistId);
      final mine = await db.artistSongs(artistId);
      return ArtistPage(
        artist: Artist(
          id: page.artist.id,
          name: page.artist.name,
          thumbnailUrl: page.artist.thumbnailUrl,
          channelId: page.artist.channelId,
          subscribed: followed,
        ),
        sections: [
          ...await _prepareSections(page.sections),
          if (mine.isNotEmpty)
            HomeSection(
              title: 'In your library',
              style: HomeSectionStyle.quickPicks,
              items: [for (final t in mine) TrackItem(t)],
            ),
        ],
        description: page.description,
        subscriberText: page.subscriberText,
        shufflePlaylistId: page.shufflePlaylistId,
        radioPlaylistId: page.radioPlaylistId,
      );
    } catch (_) {
      // Offline: fall back to library songs.
      final songs = await db.artistSongs(artistId);
      if (songs.isEmpty) rethrow;
      final row = (await db.libraryArtists()).where((a) => a.id == artistId).firstOrNull;
      return ArtistPage(
        artist: row ?? Artist(id: artistId, name: 'Artist'),
        sections: [
          HomeSection(
            title: 'In your library',
            style: HomeSectionStyle.quickPicks,
            items: [for (final t in songs) TrackItem(t)],
          ),
        ],
      );
    }
  }

  @override
  Future<CollectionPage> album(String albumId) async {
    final saved = await db.isAlbumBookmarked(albumId);
    try {
      final page = await youtube.album(albumId);
      final tracks = await _visible(await db.decorate(page.tracks));
      return _withTracks(page, tracks, saved: saved, related: await _prepareSections(page.related));
    } catch (_) {
      // Offline: the saved copy.
      final songs = await db.albumSongs(albumId);
      final row = (await db.libraryAlbums()).where((a) => a.id == albumId).firstOrNull;
      if (songs.isEmpty || row == null) rethrow;
      return CollectionPage(
        id: albumId,
        title: row.title,
        tracks: songs,
        subtitle: row.artistLine,
        secondSubtitle: '${songs.length} songs',
        thumbnailUrl: row.thumbnailUrl,
        album: row,
        saved: saved,
      );
    }
  }

  static CollectionPage _withTracks(
    CollectionPage page,
    List<Track> tracks, {
    bool? saved,
    List<HomeSection>? related,
  }) => CollectionPage(
    id: page.id,
    title: page.title,
    tracks: tracks,
    subtitle: page.subtitle,
    secondSubtitle: page.secondSubtitle,
    description: page.description,
    thumbnailUrl: page.thumbnailUrl,
    album: page.album,
    playlist: page.playlist,
    related: related ?? page.related,
    saved: saved ?? page.saved,
  );

  static String _count(int n) => n == 1 ? '1 song' : '$n songs';

  static String _totalTime(List<Track> tracks) {
    final mins = tracks.fold<int>(0, (a, t) => a + t.duration.inSeconds) ~/ 60;
    if (mins == 0) return '';
    return mins < 60 ? ' • $mins min' : ' • ${mins ~/ 60} hr ${mins % 60} min';
  }

  @override
  Future<CollectionPage> playlist(String playlistId) async {
    CollectionPage auto(String title, PlaylistKind kind, List<Track> tracks) => CollectionPage(
      id: playlistId,
      title: title,
      tracks: tracks,
      secondSubtitle: '${_count(tracks.length)}${_totalTime(tracks)}',
      thumbnailUrl: tracks.firstOrNull?.thumbnailUrl,
      playlist: Playlist(id: playlistId, name: title, kind: kind, songCount: tracks.length),
      saved: true,
    );
    switch (playlistId) {
      case 'auto:liked':
        return auto('Liked Songs', PlaylistKind.liked, await db.likedSongs());
      case 'auto:downloaded':
        return auto('Downloaded', PlaylistKind.downloaded, await db.downloadedSongs());
      case 'auto:top':
        final n = int.tryParse(settings.string('topSize') ?? '') ?? 50;
        return auto('My Top $n', PlaylistKind.top, await db.topSongs(limit: n));
      case 'auto:local':
        return auto('On This Device', PlaylistKind.local, await db.localSongs());
    }

    final row = await db.playlistRow(playlistId);
    if (row != null) {
      final id = row['id'] as String;
      var tracks = await db.playlistSongs(id);
      final browseId = row['browseId'] as String?;
      if (tracks.isEmpty && browseId != null) {
        // Synced playlist whose songs were never stored: fetch them once.
        try {
          final online = await youtube.playlist(browseId);
          await db.setPlaylistSongs(id, online.tracks);
          tracks = await db.playlistSongs(id);
        } catch (_) {}
      }
      return CollectionPage(
        id: id,
        title: row['name'] as String,
        tracks: tracks,
        secondSubtitle: '${_count(tracks.length)}${_totalTime(tracks)}',
        thumbnailUrl: (row['thumbnailUrl'] as String?) ?? tracks.firstOrNull?.thumbnailUrl,
        playlist: Playlist(
          id: id,
          name: row['name'] as String,
          kind: PlaylistKind.local,
          songCount: tracks.length,
          isEditable: true,
        ),
        saved: true,
      );
    }

    final page = await youtube.playlist(playlistId);
    return _withTracks(
      page,
      await _visible(await db.decorate(page.tracks)),
      saved: false,
      related: await _prepareSections(page.related),
    );
  }

  @override
  Future<List<Track>> playlistTracks(String id) async {
    if (id.startsWith('MPRE') || id.startsWith('FEmusic_library_privately_owned_release'))
      return (await album(id)).tracks;
    if (id.startsWith('UC') || id.startsWith('MPLA') || id.startsWith('LA')) {
      final page = await artist(id);
      // "Top songs" links to the artist's full songs playlist.
      final top = page.sections.where((s) => s.style == HomeSectionStyle.quickPicks).firstOrNull;
      final more = top?.moreBrowseId;
      if (more != null && more.startsWith('VL')) {
        try {
          return (await playlist(more.substring(2))).tracks;
        } catch (_) {}
      }
      return [
        for (final i in top?.items ?? const <MediaItem>[])
          if (i is TrackItem) i.track,
      ];
    }
    return (await playlist(id)).tracks;
  }

  // ── Search ───────────────────────────────────────────────────────────────

  final _searchContinuations = <String, String?>{};

  bool get _onlineSearch => (settings.string('searchSource') ?? 'ONLINE') == 'ONLINE';

  /// A pasted YouTube / YouTube Music link → the item it points to.
  Future<List<MediaItem>?> _fromLink(String text) async {
    final link = parseYouTubeLink(text);
    if (link == null) return null;
    switch (link.type) {
      case 'video':
        final tracks = await youtube.queue([link.id]);
        return [for (final t in await db.decorate(tracks)) TrackItem(t)];
      case 'playlist':
        final page = await youtube.playlist(link.id, maxPages: 0);
        return [if (page.playlist != null) PlaylistItem(page.playlist!)];
      case 'album':
        final page = await youtube.album(link.id);
        return [if (page.album != null) AlbumItem(page.album!)];
      case 'artist':
        final page = await youtube.artist(link.id);
        return [ArtistItem(page.artist)];
    }
    return null;
  }

  @override
  Future<List<MediaItem>> search(String query, {SearchFilter filter = SearchFilter.songs}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    List<MediaItem> items;
    final linked = q.contains('youtu') ? await _fromLink(q).catchError((_) => null) : null;
    if (linked != null && linked.isNotEmpty) {
      items = linked;
    } else if (_onlineSearch) {
      final page = await youtube.search(q, filter);
      _searchContinuations['${filter.name}|$q'] = page.continuation;
      items = await _prepare(page.items);
    } else {
      items = await _localSearch(q, filter);
    }
    if (!_bool('pauseSearchHistory') && linked == null) {
      final first = items.firstOrNull;
      await db.addSearch(q, itemJson: first == null ? null : jsonEncode(Codec.item(first)));
    }
    return items;
  }

  @override
  Future<List<MediaItem>> searchMore(String query, {SearchFilter filter = SearchFilter.songs}) async {
    final key = '${filter.name}|${query.trim()}';
    final cont = _searchContinuations[key];
    if (cont == null) return const [];
    final page = await youtube.search(query, filter, continuation: cont);
    _searchContinuations[key] = page.continuation;
    return _prepare(page.items);
  }

  Future<List<MediaItem>> _localSearch(String q, SearchFilter filter) async {
    final lower = q.toLowerCase();
    bool hit(String s) => s.toLowerCase().contains(lower);
    return switch (filter) {
      SearchFilter.albums => [
        for (final a in await db.libraryAlbums())
          if (hit(a.title) || hit(a.artistLine)) AlbumItem(a),
      ],
      SearchFilter.artists => [
        for (final a in await db.libraryArtists())
          if (hit(a.name)) ArtistItem(a),
      ],
      SearchFilter.playlists || SearchFilter.communityPlaylists || SearchFilter.featuredPlaylists => [
        for (final pl in await db.playlists())
          if (hit(pl.name)) PlaylistItem(pl),
      ],
      _ => [for (final t in await db.searchSongs(q)) TrackItem(t)],
    };
  }

  @override
  Future<List<Track>> searchSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    if (!_onlineSearch) return db.searchSongs(q, limit: 8);
    final s = await youtube.suggestions(q);
    var tracks = [
      for (final i in s.items)
        if (i is TrackItem) i.track,
    ];
    if (tracks.length < 3) {
      // Few direct suggestions: show the top songs for the query instead.
      final page = await youtube.search(q, SearchFilter.songs);
      final have = tracks.map((t) => t.id).toSet();
      tracks = [
        ...tracks,
        for (final i in page.items)
          if (i is TrackItem && have.add(i.track.id)) i.track,
      ];
    }
    return _visible(await db.decorate(tracks.take(8).toList()));
  }

  @override
  Future<List<RecentSearch>> recentSearches() async => [
    for (final s in await db.searches()) RecentSearch(query: s.query, item: s.json == null ? null : _tryItem(s.json!)),
  ];

  static MediaItem? _tryItem(String json) {
    try {
      return Codec.itemFrom(jsonDecode(json) as Map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> removeRecentSearch(String query) => db.removeSearch(query);

  @override
  Future<void> clearRecentSearches() => db.clearSearches();

  // ── Library ──────────────────────────────────────────────────────────────

  @override
  Future<List<Playlist>> libraryPlaylists() async {
    final liked = await db.likedSongs();
    final downloaded = await db.downloadedSongs();
    final top = await db.topSongs(limit: 1);
    final n = int.tryParse(settings.string('topSize') ?? '') ?? 50;
    return [
      if (_bool('show_liked_playlist', true))
        Playlist(
          id: 'auto:liked',
          name: 'Liked Songs',
          kind: PlaylistKind.liked,
          songCount: liked.length,
          thumbnailUrl: liked.firstOrNull?.thumbnailUrl,
        ),
      if (_bool('show_downloaded_playlist', true))
        Playlist(
          id: 'auto:downloaded',
          name: 'Downloaded',
          kind: PlaylistKind.downloaded,
          songCount: downloaded.length,
          thumbnailUrl: downloaded.firstOrNull?.thumbnailUrl,
        ),
      if (_bool('show_top_playlist', true) && top.isNotEmpty)
        Playlist(
          id: 'auto:top',
          name: 'My Top $n',
          kind: PlaylistKind.top,
          songCount: (await db.topSongs(limit: n)).length,
          thumbnailUrl: top.first.thumbnailUrl,
        ),
      ...await db.playlists(
        sort: settings.string('playlistSortType'),
        descending: _bool('playlistSortDescending', true),
      ),
    ];
  }

  @override
  Future<List<Artist>> libraryArtists() => db.libraryArtists();

  @override
  Future<List<Album>> libraryAlbums() => db.libraryAlbums();

  @override
  Future<List<Track>> librarySongs() =>
      db.librarySongs(sort: settings.string('songSortType'), descending: _bool('songSortDescending', true));

  @override
  Future<List<MediaItem>> recentlyAdded() async {
    final songs = await db.librarySongs();
    final albums = await db.libraryAlbums();
    final playlists = await db.playlists();
    final out = <MediaItem>[];
    // Newest first, mixing kinds the way the Library reference shows them.
    final seenAlbums = <String>{};
    for (final a in albums.take(8)) {
      if (seenAlbums.add(a.id)) out.add(AlbumItem(a));
    }
    for (final pl in playlists.take(4)) {
      out.add(PlaylistItem(pl));
    }
    for (final t in songs.take(30)) {
      if (t.albumId != null && seenAlbums.contains(t.albumId)) continue;
      out.add(TrackItem(t));
      if (out.length >= 24) break;
    }
    return out;
  }

  // ── Lyrics ───────────────────────────────────────────────────────────────

  @override
  Future<Lyrics> lyrics(Track track) => lyricsService.get(track, lrclib: _bool('enableLrclib', true));

  // ── Recognition ──────────────────────────────────────────────────────────

  @override
  Stream<RecognitionState> recognize() => _features.recognize();

  // ── Host integration ────────────────────────────────────────────────────

  @override
  Stream<NavigationEvent> get navigation => _navigation.stream;

  void navigate(NavigationEvent event) {
    if (!_navigation.isClosed) _navigation.add(event);
  }

  static final _url = RegExp(r'https?://\S+|vnd\.youtube\S*');

  void _handleIntent(Map<String, Object?> intent) {
    final raw = (intent['data'] as String?) ?? (intent['text'] as String?) ?? '';
    final url = _url.firstMatch(raw)?.group(0) ?? raw;
    final link = parseYouTubeLink(url);
    if (link == null) {
      final text = (intent['text'] as String?)?.trim();
      if (text != null && text.isNotEmpty) navigate(NavigationEvent('search', {'query': text}));
      return;
    }
    switch (link.type) {
      case 'video':
        unawaited(() async {
          try {
            if (link.playlistId != null) {
              await playOnline(videoId: link.id, playlistId: link.playlistId);
            } else {
              final tracks = await youtube.queue([link.id]);
              if (tracks.isNotEmpty) await player.playTracks(await db.decorate(tracks));
            }
            navigate(const NavigationEvent('nowPlaying'));
          } catch (_) {}
        }());
      case 'search':
        navigate(NavigationEvent('search', {'query': link.id}));
      default:
        navigate(NavigationEvent('collection', {'type': link.type, 'id': link.id}));
    }
  }

  @override
  Future<List<Track>> suggestions(List<Track> seeds, {Set<String> exclude = const {}}) async {
    final online = seeds.where((t) => !t.isLocal).toList()..shuffle();
    final radios = await Future.wait([
      for (final t in online.take(4))
        youtube.next(videoId: t.id).then((p) => p.tracks).catchError((_) => const <Track>[]),
    ]);
    final seen = {...exclude, for (final t in seeds) t.id};
    final out = <Track>[];
    final longest = radios.fold(0, (m, r) => r.length > m ? r.length : m);
    for (var i = 0; i < longest && out.length < 25; i++) {
      for (final r in radios) {
        if (i < r.length && seen.add(r[i].id)) out.add(r[i]);
      }
    }
    return db.decorate(await _visible(out.take(25).toList()));
  }

  @override
  Future<Object?> feature(String method, [Map<String, Object?> args = const {}]) => _features.call(method, args);

  @override
  Stream<Map<String, Object?>> get featureEvents => _featureEvents.stream;

  @override
  Future<void> systemAction(String name) async {
    switch (name) {
      case 'equalizer':
        final ok = await host.invokeMethod<bool>('openEqualizer', {'sessionId': player.androidAudioSessionId ?? 0});
        if (ok != true) throw StateError('No equalizer app is installed on this device');
      case 'defaultLinks':
        await host.invokeMethod<void>('openByDefault');
      case 'appSettings':
        await host.invokeMethod<void>('openAppSettings');
      case 'outputSwitcher':
        await host.invokeMethod<void>('outputSwitcher');
    }
  }

  @override
  Future<void> share(String text) => SharePlus.instance.share(ShareParams(text: text));

  // ── Updater ──────────────────────────────────────────────────────────────

  @override
  Stream<UpdateStatus> get updates => updater.states;

  @override
  Future<UpdateStatus> checkForUpdate({bool manual = true}) => updater.check(manual: manual);

  @override
  Future<void> downloadUpdate() => updater.download();

  @override
  Future<void> installUpdate() => updater.install();

  @override
  Future<void> cancelUpdate() => updater.cancel();

  @override
  Future<void> skipUpdate() => updater.skip();

  @override
  Future<void> setUpdatePrefs({bool? beta, bool? autoDownload, bool? wifiOnly, bool? autoCheck}) =>
      updater.setPrefs(beta: beta, autoDownload: autoDownload, wifiOnly: wifiOnly, autoCheck: autoCheck);

  // ── Settings ─────────────────────────────────────────────────────────────

  @override
  Future<Map<String, Object?>> readSettings() async => settings.all;

  @override
  Future<void> writeSetting(String key, Object? value) async {
    await settings.write(key, value);
    switch (key) {
      case 'audioQuality' || 'skipSilence' || 'audioNormalization':
        await player.applySettings();
      case 'contentLanguage' || 'contentCountry':
        _applyLocale();
        _homeCache = null;
      case 'useLoginForBrowse':
        tube.useLoginForBrowse = value as bool? ?? true;
        _homeCache = null;
      case 'hideExplicit' || 'hideVideoSongs' || 'discover' || 'randomizeHomeOrder':
        _homeCache = null;
      case 'disableScreenshot' || 'keepScreenOn':
        _applyWindowFlags();
      case 'sponsorBlockEnabled' || 'sponsorBlockCategories':
        break; // read when the next track loads
      case 'enableDynamicIcon':
        // "Dynamic app icon" on = themed alias; off = the fixed icon.
        unawaited(host.invokeMethod<void>('setStaticIcon', {'enabled': value == false}).catchError((_) {}));
      case 'show_liked_playlist' ||
          'show_downloaded_playlist' ||
          'show_top_playlist' ||
          'songSortType' ||
          'songSortDescending' ||
          'playlistSortType' ||
          'playlistSortDescending' ||
          'topSize':
        _libraryChanged.add(null);
    }
    _features.onSettingChanged(key, value);
  }

  @override
  Future<void> flush() => player.flush();
}

/// A YouTube / YouTube Music URL broken into what it points at.
({String type, String id, String? playlistId})? parseYouTubeLink(String text) {
  var s = text.trim();
  if (s.startsWith('vnd.youtube')) {
    final id = s.split(':').last.split('?').first;
    return id.isEmpty ? null : (type: 'video', id: id, playlistId: null);
  }
  if (!s.startsWith('http')) {
    if (!RegExp(r'^(www\.|m\.|music\.)?(youtube\.com|youtu\.be)/').hasMatch(s)) return null;
    s = 'https://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final seg = uri.pathSegments;
  if (host == 'youtu.be') {
    return seg.isEmpty ? null : (type: 'video', id: seg.first, playlistId: uri.queryParameters['list']);
  }
  if (!host.endsWith('youtube.com')) return null;
  final q = uri.queryParameters;
  if (seg.isEmpty) return null;
  switch (seg.first) {
    case 'watch':
      final v = q['v'];
      if (v != null) return (type: 'video', id: v, playlistId: q['list']);
      final list = q['list'];
      return list == null ? null : (type: 'playlist', id: list, playlistId: null);
    case 'v' || 'embed' || 'shorts' || 'live':
      return seg.length < 2 ? null : (type: 'video', id: seg[1], playlistId: q['list']);
    case 'playlist':
      final list = q['list'];
      if (list == null) return null;
      // Album share links are OLAK5uy_… playlists; they open as playlists.
      return (type: 'playlist', id: list, playlistId: null);
    case 'channel':
      return seg.length < 2 ? null : (type: 'artist', id: seg[1], playlistId: null);
    case 'browse':
      if (seg.length < 2) return null;
      final id = seg[1];
      if (id.startsWith('MPRE')) return (type: 'album', id: id, playlistId: null);
      if (id.startsWith('UC')) return (type: 'artist', id: id, playlistId: null);
      if (id.startsWith('VL')) return (type: 'playlist', id: id.substring(2), playlistId: null);
      return null;
    case 'search':
      final query = q['q'];
      return query == null ? null : (type: 'search', id: query, playlistId: null);
  }
  return null;
}

/// Re-exported for screens that format parser output (thumbnail sizing).
String? hiResThumbnail(String? url, [int size = 544]) => Yt.hiRes(url, size);
