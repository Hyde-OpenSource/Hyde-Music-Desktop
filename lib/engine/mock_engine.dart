import 'dart:async';
import 'dart:math' as math;

import 'hyde_engine.dart';
import 'models.dart';

/// In-memory engine with demo content, for UI development and widget tests
/// (`--dart-define=HYDE_ENGINE=mock`).
class MockEngine implements HydeEngine {
  MockEngine({this.artwork = true}) {
    _snapshot = PlaybackSnapshot(
      track: _tracks[0],
      duration: _tracks[0].duration,
      queue: _tracks,
      format: const AudioFormat(codec: 'opus', bitrateKbps: 160, sampleRateHz: 48000),
    );
  }

  /// Off in tests (no network).
  final bool artwork;

  late PlaybackSnapshot _snapshot;
  final _controller = StreamController<PlaybackSnapshot>.broadcast();
  Timer? _ticker;
  final _settings = <String, Object?>{};
  final _recent = <RecentSearch>[];

  String? _art(String seed) => artwork ? 'https://picsum.photos/seed/hyde-$seed/600/600' : null;

  late final List<Track> _tracks = [
    for (var i = 0; i < _demo.length; i++)
      Track(
        id: 'demo$i',
        title: _demo[i].$1,
        artists: [ArtistRef(id: 'artist${i % 5}', name: _demo[i].$2)],
        albumId: 'album${i % 6}',
        albumName: _demo[i].$3,
        thumbnailUrl: _art('t$i'),
        duration: Duration(seconds: 150 + (i * 37) % 120),
        liked: i.isEven,
        inLibrary: true,
      ),
  ];

  static const _demo = [
    ('Glass Horizon', 'Aurel Vance', 'Prism Days'),
    ('Low Tide Letters', 'Mira Sol', 'Coastlines'),
    ('Paper Satellites', 'The Quiet Hours', 'Orbit'),
    ('Copper Rain', 'Aurel Vance', 'Prism Days'),
    ('Night Bus Home', 'Juno Park', 'City Glow'),
    ('Velvet Static', 'Mira Sol', 'Coastlines'),
    ('Afterlight', 'Neel Arora', 'Monsoon Tapes'),
    ('Small Fires', 'The Quiet Hours', 'Orbit'),
    ('Saffron Skies', 'Neel Arora', 'Monsoon Tapes'),
    ('Northbound', 'Juno Park', 'City Glow'),
  ];

  // ── Playback ────────────────────────────────────────────────────────────
  @override
  Stream<PlaybackSnapshot> get playback => _controller.stream;

  @override
  PlaybackSnapshot get currentPlayback => _snapshot;

  void _emit(PlaybackSnapshot s) {
    _snapshot = s;
    _controller.add(s);
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_snapshot.isPlaying) return;
      final pos = _snapshot.position + const Duration(milliseconds: 250);
      if (pos >= _snapshot.duration) {
        next();
      } else {
        _emit(_snapshot.copyWith(position: pos, buffered: pos + const Duration(seconds: 20)));
      }
    });
  }

  void _load(int index, {bool play = true}) {
    final q = _snapshot.queue;
    if (q.isEmpty) return;
    final i = index.clamp(0, q.length - 1);
    _emit(
      _snapshot.copyWith(track: q[i], queueIndex: i, position: Duration.zero, duration: q[i].duration, isPlaying: play),
    );
    _startTicker();
  }

  @override
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false, bool smart = false}) async {
    shuffle = shuffle || smart;
    final q = [...tracks];
    if (shuffle) q.shuffle(math.Random());
    _snapshot = _snapshot.copyWith(queue: q, shuffle: shuffle);
    _load(shuffle ? 0 : startIndex);
  }

  @override
  Future<void> playPause() async {
    _emit(_snapshot.copyWith(isPlaying: !_snapshot.isPlaying));
    _startTicker();
  }

  @override
  Future<void> next() async {
    final last = _snapshot.queueIndex >= _snapshot.queue.length - 1;
    if (_snapshot.repeat == QueueRepeat.one) return _load(_snapshot.queueIndex);
    if (last && _snapshot.repeat == QueueRepeat.off) {
      return _emit(_snapshot.copyWith(isPlaying: false, position: Duration.zero));
    }
    _load(last ? 0 : _snapshot.queueIndex + 1);
  }

  @override
  Future<void> previous() async {
    if (_snapshot.position > const Duration(seconds: 3)) return seek(Duration.zero);
    _load(math.max(0, _snapshot.queueIndex - 1));
  }

  @override
  Future<void> seek(Duration position) async => _emit(_snapshot.copyWith(position: position));

  @override
  Future<void> setShuffle(bool enabled, {bool? smart}) async => _emit(_snapshot.copyWith(shuffle: enabled));

  @override
  Future<void> setRepeat(QueueRepeat mode) async => _emit(_snapshot.copyWith(repeat: mode));

  @override
  Future<void> setVolume(double volume) async => _emit(_snapshot.copyWith(volume: volume.clamp(0, 1)));

  @override
  Future<void> playNext(List<Track> tracks) async {
    final q = [..._snapshot.queue]..insertAll(_snapshot.queueIndex + 1, tracks);
    _emit(_snapshot.copyWith(queue: q));
  }

  @override
  Future<void> addToQueue(List<Track> tracks) async =>
      _emit(_snapshot.copyWith(queue: [..._snapshot.queue, ...tracks]));

  @override
  Future<void> moveQueueItem(int from, int to) async {
    final q = [..._snapshot.queue];
    final t = q.removeAt(from);
    q.insert(to, t);
    var idx = _snapshot.queueIndex;
    if (from == idx) {
      idx = to;
    } else if (from < idx && to >= idx) {
      idx--;
    } else if (from > idx && to <= idx) {
      idx++;
    }
    _emit(_snapshot.copyWith(queue: q, queueIndex: idx));
  }

  @override
  Future<void> removeQueueItem(int index) async {
    if (index == _snapshot.queueIndex) return;
    final q = [..._snapshot.queue]..removeAt(index);
    _emit(_snapshot.copyWith(queue: q, queueIndex: index < _snapshot.queueIndex ? _snapshot.queueIndex - 1 : null));
  }

  @override
  Future<void> skipToQueueItem(int index) async => _load(index);

  @override
  Future<void> startRadio(Track seed) async => playTracks([seed, ..._tracks.where((t) => t.id != seed.id)]);

  @override
  Future<void> playOnline({String? playlistId, String? videoId, String? params, bool shuffle = false}) =>
      playTracks(_tracks, shuffle: shuffle);

  @override
  Future<void> setSleepTimer(Duration? duration, {bool endOfTrack = false}) async {
    if (duration == null && !endOfTrack) return _emit(_snapshot.copyWith(clearSleepTimer: true));
    final remaining = endOfTrack ? _snapshot.duration - _snapshot.position : duration!;
    _emit(_snapshot.copyWith(sleepTimerEnd: DateTime.now().add(remaining)));
  }

  // ── Library actions ─────────────────────────────────────────────────────
  void _replace(Track updated) {
    for (var i = 0; i < _tracks.length; i++) {
      if (_tracks[i].id == updated.id) _tracks[i] = updated;
    }
    final q = [for (final t in _snapshot.queue) t.id == updated.id ? updated : t];
    _emit(_snapshot.copyWith(queue: q, track: _snapshot.track?.id == updated.id ? updated : null));
  }

  @override
  Future<void> setLiked(Track track, bool liked) async => _replace(track.copyWith(liked: liked));

  @override
  Future<void> setInLibrary(Track track, bool inLibrary) async => _replace(track.copyWith(inLibrary: inLibrary));

  @override
  Future<void> download(List<Track> tracks) async {
    for (final t in tracks) {
      _replace(t.copyWith(isDownloaded: true));
    }
  }

  @override
  Future<void> removeDownload(List<Track> tracks) async {
    for (final t in tracks) {
      _replace(t.copyWith(isDownloaded: false));
    }
  }

  late final List<Playlist> _playlists = [
    for (var i = 0; i < 6; i++)
      Playlist(
        id: 'pl$i',
        name: const ['Late Night Drive', 'Monsoon Mood', 'Focus Flow', 'Sunday Slow', 'Road Trip', 'Gym Pulse'][i],
        thumbnailUrl: _art('p$i'),
        songCount: 8 + i * 9,
      ),
  ];

  @override
  Future<void> addToPlaylist(String playlistId, List<Track> tracks) async {}

  @override
  Future<Playlist> createPlaylist(String name) async {
    final p = Playlist(id: 'pl${_playlists.length}', name: name);
    _playlists.insert(0, p);
    return p;
  }

  @override
  Future<void> renamePlaylist(String playlistId, String name) async {
    final i = _playlists.indexWhere((p) => p.id == playlistId);
    if (i >= 0) _playlists[i] = Playlist(id: playlistId, name: name, songCount: _playlists[i].songCount);
    _libraryChanged.add(null);
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    _playlists.removeWhere((p) => p.id == playlistId);
    _libraryChanged.add(null);
  }

  @override
  Future<void> removeFromPlaylist(String playlistId, Track track) async {}

  @override
  Future<void> movePlaylistTrack(String playlistId, int from, int to) async {}

  @override
  Future<Playlist> importPlaylist(CollectionPage page) => createPlaylist(page.title);

  @override
  Future<void> setAlbumSaved(CollectionPage album, bool saved) async {}

  @override
  Future<void> setArtistFollowed(Artist artist, bool followed) async {}

  final _libraryChanged = StreamController<void>.broadcast();

  @override
  Stream<void> get libraryChanged => _libraryChanged.stream;

  @override
  Future<String> shareLink(MediaItem item) async => switch (item) {
    TrackItem(:final track) => 'https://song.link/y/${track.id}',
    AlbumItem(:final album) => 'https://music.youtube.com/browse/${album.id}',
    ArtistItem(:final artist) => 'https://music.youtube.com/channel/${artist.id}',
    PlaylistItem(:final playlist) => 'https://music.youtube.com/playlist?list=${playlist.id}',
    BrowseItem(:final browseId) => 'https://music.youtube.com/browse/$browseId',
  };

  // ── Browse ──────────────────────────────────────────────────────────────
  List<Album> get _albums => [
    for (var i = 0; i < 6; i++)
      Album(
        id: 'album$i',
        title: _demo[i].$3,
        artists: [ArtistRef(id: 'artist${i % 5}', name: _demo[i].$2)],
        thumbnailUrl: _art('a$i'),
        year: 2019 + i,
        songCount: 9 + i,
      ),
  ];

  List<Artist> get _artists => [
    for (var i = 0; i < 5; i++) Artist(id: 'artist$i', name: _demo[i].$2, thumbnailUrl: _art('r$i')),
  ];

  List<HomeSection> get _sections => [
    HomeSection(
      title: 'Quick picks',
      style: HomeSectionStyle.quickPicks,
      items: [for (final t in _tracks) TrackItem(t)],
    ),
    HomeSection(title: 'Keep listening', items: [for (final a in _albums) AlbumItem(a)]),
    HomeSection(title: 'Your playlists', items: [for (final p in _playlists) PlaylistItem(p)]),
    HomeSection(title: 'Similar to', label: _demo[0].$2, items: [for (final a in _artists) ArtistItem(a)]),
    HomeSection(
      title: 'Moods & genres',
      style: HomeSectionStyle.moods,
      items: const [
        BrowseItem(title: 'Chill', browseId: 'mood-chill', color: 0xFF4FA3F7),
        BrowseItem(title: 'Focus', browseId: 'mood-focus', color: 0xFF7ACB6E),
        BrowseItem(title: 'Workout', browseId: 'mood-workout', color: 0xFFF5B342),
        BrowseItem(title: 'Romance', browseId: 'mood-romance', color: 0xFFF26D92),
      ],
    ),
    HomeSection(title: 'Forgotten favorites', items: [for (final t in _tracks.reversed) TrackItem(t)]),
  ];

  @override
  Future<HomeFeed> home({bool refresh = false, String? chipParams}) async => HomeFeed(
    sections: chipParams == null ? _sections : _sections.reversed.toList(),
    chips: const [HomeChip(title: 'Relax', params: 'relax'), HomeChip(title: 'Energize', params: 'energize')],
  );

  @override
  Future<HomeFeed> homeMore(String continuation) async => const HomeFeed(sections: []);

  @override
  Future<({String? title, List<HomeSection> sections})> browse(String browseId, {String? params}) async =>
      (title: 'Browse', sections: _sections);

  @override
  Future<ArtistPage> artist(String artistId) async {
    final a = _artists.firstWhere((a) => a.id == artistId, orElse: () => _artists.first);
    return ArtistPage(
      artist: a,
      subscriberText: '1.2M subscribers',
      description: 'Demo artist.',
      sections: [
        HomeSection(
          title: 'Top songs',
          style: HomeSectionStyle.quickPicks,
          items: [for (final t in _tracks.take(5)) TrackItem(t)],
        ),
        HomeSection(title: 'Albums', items: [for (final al in _albums) AlbumItem(al)]),
        HomeSection(title: 'Fans might also like', items: [for (final o in _artists) ArtistItem(o)]),
      ],
    );
  }

  @override
  Future<CollectionPage> album(String albumId) async {
    final a = _albums.firstWhere((a) => a.id == albumId, orElse: () => _albums.first);
    return CollectionPage(
      id: a.id,
      title: a.title,
      tracks: List.unmodifiable(_tracks),
      subtitle: a.artistLine,
      secondSubtitle: '${_tracks.length} songs',
      thumbnailUrl: a.thumbnailUrl,
      album: a,
    );
  }

  @override
  Future<CollectionPage> playlist(String playlistId) async {
    final p = _playlists.firstWhere((p) => p.id == playlistId, orElse: () => _playlists.first);
    return CollectionPage(
      id: p.id,
      title: p.name,
      tracks: List.unmodifiable(_tracks),
      secondSubtitle: '${_tracks.length} songs',
      thumbnailUrl: p.thumbnailUrl,
      playlist: p,
      saved: true,
    );
  }

  @override
  Future<List<MediaItem>> searchMore(String query, {SearchFilter filter = SearchFilter.songs}) async => const [];

  @override
  Future<List<MediaItem>> search(String query, {SearchFilter filter = SearchFilter.songs}) async {
    final q = query.toLowerCase();
    final items = <MediaItem>[
      for (final t in _tracks)
        if (t.title.toLowerCase().contains(q) || t.artistLine.toLowerCase().contains(q)) TrackItem(t),
      for (final a in _albums)
        if (a.title.toLowerCase().contains(q)) AlbumItem(a),
      for (final a in _artists)
        if (a.name.toLowerCase().contains(q)) ArtistItem(a),
    ];
    _recent.removeWhere((r) => r.query == query);
    _recent.insert(0, RecentSearch(query: query, item: items.isEmpty ? null : items.first));
    return items;
  }

  @override
  Future<List<Track>> searchSuggestions(String query) async => [
    for (final t in _tracks)
      if (t.title.toLowerCase().contains(query.toLowerCase()) ||
          t.artistLine.toLowerCase().contains(query.toLowerCase()))
        t,
  ];

  @override
  Future<List<RecentSearch>> recentSearches() async {
    if (_recent.isEmpty) {
      _recent.addAll([
        RecentSearch(query: _tracks[0].title, item: TrackItem(_tracks[0])),
        RecentSearch(query: _albums[1].title, item: AlbumItem(_albums[1])),
        RecentSearch(query: _tracks[4].title, item: TrackItem(_tracks[4])),
        RecentSearch(query: _albums[3].title, item: AlbumItem(_albums[3])),
      ]);
    }
    return List.unmodifiable(_recent);
  }

  @override
  Future<void> removeRecentSearch(String query) async => _recent.removeWhere((r) => r.query == query);

  @override
  Future<void> clearRecentSearches() async => _recent.clear();

  @override
  Future<List<Playlist>> libraryPlaylists() async => List.unmodifiable(_playlists);

  @override
  Future<List<Artist>> libraryArtists() async => _artists;

  @override
  Future<List<Album>> libraryAlbums() async => _albums;

  @override
  Future<List<Track>> librarySongs() async => List.unmodifiable(_tracks);

  @override
  Future<List<MediaItem>> recentlyAdded() async => [for (final a in _albums) AlbumItem(a)];

  @override
  Future<List<Track>> playlistTracks(String playlistId) async => List.unmodifiable(_tracks);

  // ── Lyrics ──────────────────────────────────────────────────────────────
  @override
  Future<List<Track>> suggestions(List<Track> seeds, {Set<String> exclude = const {}}) async =>
      _tracks.where((t) => !exclude.contains(t.id) && !seeds.any((s) => s.id == t.id)).take(10).toList();

  @override
  Future<Lyrics> lyrics(Track track) async {
    // Original placeholder verse — demo only.
    const text = [
      'Streetlights hum a quiet tune',
      'Under a paper moon',
      'Every window holds a story',
      'Every story finds its way back home',
      '',
      'Hold the light a little longer',
      'Let the evening fold',
      'We were never meant to hurry',
      'Only meant to hold',
      '',
      'And the city breathes in colour',
      'Through the glass, the rain, the glow',
      'If you listen you can hear it',
      'Every place we used to go',
    ];
    var t = const Duration(seconds: 4);
    final lines = <LyricLine>[];
    for (final l in text) {
      lines.add(LyricLine(start: t, text: l));
      t += Duration(milliseconds: l.isEmpty ? 3000 : 4200);
    }
    return Lyrics(lines: lines, synced: true, provider: 'LRCLIB');
  }

  // ── Recognition ─────────────────────────────────────────────────────────
  @override
  Stream<RecognitionState> recognize() async* {
    final rnd = math.Random();
    for (var i = 0; i < 24; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      yield RecognitionListening(0.3 + rnd.nextDouble() * 0.7);
    }
    yield RecognitionMatched(_tracks[rnd.nextInt(_tracks.length)]);
  }

  // ── Playback parameters ─────────────────────────────────────────────────
  ({double speed, double pitch}) _params = (speed: 1, pitch: 1);

  @override
  Future<void> setPlaybackParameters({required double speed, required double pitch}) async =>
      _params = (speed: speed, pitch: pitch);

  @override
  Future<({double speed, double pitch})> playbackParameters() async => _params;

  // ── Host integration ────────────────────────────────────────────────────
  final _navigation = StreamController<NavigationEvent>.broadcast();

  @override
  Stream<NavigationEvent> get navigation => _navigation.stream;

  final featureCalls = <String>[];
  final _featureEvents = StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<Map<String, Object?>> get featureEvents => _featureEvents.stream;

  void emitFeature(Map<String, Object?> event) => _featureEvents.add(event);

  Map<String, Object?> _trackMap(Track t) => {
    'id': t.id,
    'title': t.title,
    'artists': [
      for (final a in t.artists) {'id': a.id, 'name': a.name},
    ],
    'albumId': t.albumId,
    'albumName': t.albumName,
    'thumbnailUrl': t.thumbnailUrl,
    'duration': t.duration.inSeconds,
    'liked': t.liked,
  };

  @override
  Future<Object?> feature(String method, [Map<String, Object?> args = const {}]) async {
    featureCalls.add(method);
    final now = DateTime.now().millisecondsSinceEpoch;
    return switch (method) {
      'history.list' => [
        for (var i = 0; i < _tracks.length; i++)
          {'id': i, 'timestamp': now - i * 3600 * 1000 * 5, 'track': _trackMap(_tracks[i])},
      ],
      'stats' => {
        'totalMs': 1000 * 60 * 754,
        'totalPlays': 312,
        'songs': [
          for (var i = 0; i < _tracks.length; i++)
            {..._trackMap(_tracks[i]), 'plays': 40 - i * 3, 'ms': (40 - i * 3) * 180000},
        ],
        'artists': [
          for (var i = 0; i < 5; i++)
            {
              'type': 'artist',
              'id': 'artist$i',
              'name': _demo[i].$2,
              'thumbnailUrl': _art('r$i'),
              'plays': 60 - i * 9,
              'ms': (60 - i * 9) * 200000,
            },
        ],
        'albums': [
          for (var i = 0; i < 5; i++)
            {
              'type': 'album',
              'id': 'album$i',
              'title': _demo[i].$3,
              'thumbnailUrl': _art('a$i'),
              'artists': [
                {'id': 'artist$i', 'name': _demo[i].$2},
              ],
              'plays': 30 - i * 4,
              'ms': (30 - i * 4) * 190000,
            },
        ],
      },
      'local.songs' => [for (final t in _tracks.take(4)) _trackMap(t)],
      'storage.usage' => {'song': 812 * 1024 * 1024, 'download': 1536 * 1024 * 1024, 'image': 64 * 1024 * 1024},
      'account.state' => {'signedIn': false, 'accounts': const []},
      'discord.profile' => null,
      'import.csv' || 'import.m3u' => [for (final t in _tracks.take(3)) _trackMap(t)],
      _ => null,
    };
  }

  @override
  Future<void> systemAction(String name) async {}

  @override
  Future<void> flush() async {}

  final shared = <String>[];

  @override
  Future<void> share(String text) async => shared.add(text);

  // ── Updater (simulated) ─────────────────────────────────────────────────
  final _updates = StreamController<UpdateStatus>.broadcast();
  UpdateStatus _update = const UpdateStatus(phase: UpdatePhase.idle, currentVersion: '5.0.0');
  Timer? _updateTimer;

  static const _demoRelease = UpdateRelease(
    version: '5.1.0',
    name: 'Hyde Music 5.1',
    notes: '• Liquid Glass everywhere\n• Faster library loading\n• Fixes and improvements',
    size: 38 * 1024 * 1024,
    verifiedChecksum: true,
  );

  void _setUpdate(UpdateStatus s) {
    _update = s;
    _updates.add(s);
  }

  UpdateStatus _with(UpdatePhase phase, {int bytes = 0, int speed = 0, String? error}) => UpdateStatus(
    phase: phase,
    currentVersion: _update.currentVersion,
    release: phase == UpdatePhase.upToDate || phase == UpdatePhase.checking ? null : _demoRelease,
    bytes: bytes,
    total: _demoRelease.size,
    speed: speed,
    error: error,
    lastChecked: DateTime.now(),
    beta: _update.beta,
    autoDownload: _update.autoDownload,
    wifiOnly: _update.wifiOnly,
    autoCheck: _update.autoCheck,
  );

  @override
  Stream<UpdateStatus> get updates => _updates.stream;

  @override
  Future<UpdateStatus> checkForUpdate({bool manual = true}) async {
    _setUpdate(_with(UpdatePhase.checking));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _setUpdate(_with(UpdatePhase.available));
    return _update;
  }

  @override
  Future<void> downloadUpdate() async {
    var bytes = 0;
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      bytes += 2 * 1024 * 1024;
      if (bytes >= _demoRelease.size) {
        t.cancel();
        _setUpdate(_with(UpdatePhase.ready, bytes: _demoRelease.size));
      } else {
        _setUpdate(_with(UpdatePhase.downloading, bytes: bytes, speed: 10 * 1024 * 1024));
      }
    });
  }

  @override
  Future<void> installUpdate() async => _setUpdate(_with(UpdatePhase.installing));

  @override
  Future<void> cancelUpdate() async {
    _updateTimer?.cancel();
    _setUpdate(_with(UpdatePhase.available));
  }

  @override
  Future<void> skipUpdate() async => _setUpdate(_with(UpdatePhase.upToDate));

  @override
  Future<void> setUpdatePrefs({bool? beta, bool? autoDownload, bool? wifiOnly, bool? autoCheck}) async {
    _setUpdate(
      UpdateStatus(
        phase: _update.phase,
        currentVersion: _update.currentVersion,
        release: _update.release,
        bytes: _update.bytes,
        total: _update.total,
        speed: _update.speed,
        lastChecked: _update.lastChecked,
        beta: beta ?? _update.beta,
        autoDownload: autoDownload ?? _update.autoDownload,
        wifiOnly: wifiOnly ?? _update.wifiOnly,
        autoCheck: autoCheck ?? _update.autoCheck,
      ),
    );
  }

  // ── Settings ────────────────────────────────────────────────────────────
  @override
  Future<Map<String, Object?>> readSettings() async => Map.of(_settings);

  @override
  Future<void> writeSetting(String key, Object? value) async => _settings[key] = value;

  void dispose() {
    _ticker?.cancel();
    _updateTimer?.cancel();
    _navigation.close();
    _featureEvents.close();
    _updates.close();
    _controller.close();
  }
}
