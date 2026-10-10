import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import 'codec.dart';
import 'dart_engine.dart';
import 'database.dart';
import 'discord.dart';
import 'hyde_sync.dart';
import 'lastfm.dart';
import 'listen_together.dart';
import 'nearby_sync.dart';
import 'recognition.dart';
import 'settings_store.dart';

/// A feature that isn't available, with a message the UI can show as is.
class FeatureUnavailable implements Exception {
  const FeatureUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Named feature calls behind `HydeEngine.feature` — everything that isn't
/// core playback / browse: history, stats, storage, account, integrations.
class Features {
  Features(this.engine);
  final DartEngine engine;

  HydeDatabase get _db => engine.db;
  SettingsStore get _settings => engine.settings;

  final _lastfm = LastFm();
  DiscordPresence? _discord;
  late final Recognizer _recognizer = Recognizer();

  late final ListenTogether _listenTogether = ListenTogether(
    player: engine.player,
    setting: (key) => _settings[key],
    emit: engine.emitFeature,
    saveBlocked: (blocked) => _settings.write('listenTogetherBlockedUsernames', blocked),
  );
  late final NearbySync _nearby = NearbySync(
    player: engine.player,
    emit: engine.emitFeature,
    deviceName: _nonEmpty(_settings.string('listenTogetherUsername')) ?? 'Hyde Music',
  );
  late final HydeSync _hydeSync = HydeSync(
    db: _db,
    settings: _settings,
    youtube: engine.youtube,
    emit: engine.emitFeature,
    onLibraryChanged: engine.notifyLibraryChanged,
  );

  Future<void> start() async {
    _lastfm.sessionKey = _nonEmpty(_settings.string('lastfmSession'));
    _syncDiscord();
    // Presence follows play / pause / track changes.
    String? shown;
    engine.playback.listen((s) {
      final key = s.track == null || !s.isPlaying ? null : s.track!.id;
      if (key == shown) return;
      shown = key;
      _updateDiscord(s);
    });
    if (engine.tube.signedIn && _settings.boolean('ytmSync', true)) {
      // Keep the library in step with the account, at most once a day.
      final last = _settings['ytmLastSync'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last > const Duration(hours: 24).inMilliseconds) {
        unawaited(syncAccountLibrary().catchError((_) => 0));
      }
    }
  }

  static String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;

  // ── Hooks from the engine ────────────────────────────────────────────────

  DateTime _startedAt = DateTime.now();

  void onTrackChanged(Track? track) {
    _startedAt = DateTime.now();
    if (track == null) return;
    if (_lastfm.sessionKey != null &&
        _settings.boolean('lastfmScrobblingEnable') &&
        _settings.boolean('lastfmUseNowPlaying', true)) {
      unawaited(_lastfm.nowPlaying(track).catchError((_) {}));
    }
  }

  void onListened(Track track, Duration listened) {
    if (_lastfm.sessionKey == null || !_settings.boolean('lastfmScrobblingEnable')) return;
    // Last.fm rule: longer than 30 s, and half the track or the configured delay.
    final total = track.duration;
    if (total > Duration.zero && total < const Duration(seconds: 30)) return;
    final delay = Duration(seconds: ((_settings['scrobbleDelaySeconds'] as num?) ?? 180).round());
    final half = total > Duration.zero ? total * 0.5 : delay;
    if (listened < (half < delay ? half : delay)) return;
    unawaited(_lastfm.scrobble(track, _startedAt).catchError((_) {}));
  }

  void onLiked(Track track, bool liked) {
    if (_lastfm.sessionKey != null && _settings.boolean('lastfmUseSendLikes')) {
      unawaited(_lastfm.love(track, liked).catchError((_) {}));
    }
  }

  void onSettingChanged(String key, Object? value) {
    if (key.startsWith('discord')) {
      _syncDiscord();
      _updateDiscord(engine.currentPlayback);
    }
  }

  void _syncDiscord() {
    final token = _nonEmpty(_settings.string('discordToken'));
    final enabled = token != null && _settings.boolean('discordRPCEnable');
    if (!enabled) {
      unawaited(_discord?.close());
      _discord = null;
    } else if (_discord?.token != token) {
      unawaited(_discord?.close());
      _discord = DiscordPresence(token);
    }
  }

  void _updateDiscord(PlaybackSnapshot s) {
    final d = _discord;
    if (d == null) return;
    final t = s.track;
    if (t == null || !s.isPlaying) return d.clear();
    unawaited(
      d
          .update(
            t,
            position: s.position,
            duration: s.duration,
            speed: engine.player.playbackParameters.speed,
            useDetails: _settings.boolean('discordUseDetails'),
            status: _settings.string('discordStatus') ?? 'online',
            activityType: _settings.string('discordActivityType') ?? 'listening',
            activityName: _settings.string('discordActivityName') ?? '',
            button1Text: _settings.string('discordButton1Text') ?? '',
            button1Visible: _settings.boolean('discordButton1Visible', true),
            button2Text: _settings.string('discordButton2Text') ?? '',
            button2Visible: _settings.boolean('discordButton2Visible', true),
          )
          .catchError((_) {}),
    );
  }

  /// Listens through the microphone and identifies the song (Find tab).
  Stream<RecognitionState> recognize() async* {
    if (!await Permission.microphone.request().isGranted) {
      yield const RecognitionFailed('Allow microphone access to identify songs');
      return;
    }
    await for (final e in _recognizer.listen()) {
      switch (e) {
        case RecognizerLevel(:final level):
          yield RecognitionListening(level);
        case RecognizerMatch(:final title, :final artist):
          // Find the same song on YouTube Music so it can be played.
          Track? track;
          try {
            track = await match(title, artist);
          } catch (_) {}
          yield RecognitionMatched(
            track ?? Track(id: '', title: title, artists: [ArtistRef(id: null, name: artist)], thumbnailUrl: e.coverUrl),
          );
        case RecognizerFailure(:final reason):
          yield RecognitionFailed(reason);
      }
    }
  }

  // ── Router ───────────────────────────────────────────────────────────────

  Future<Object?> call(String method, Map<String, Object?> args) async {
    switch (method) {
      // Re-publish the live state of a topic (a screen just opened).
      case 'state':
        switch (args['topic']) {
          case 'downloads':
            engine.emitFeature(engine.downloader.state);
          case 'local':
            engine.emitFeature({'topic': 'local', 'scanning': _scanning, 'progress': 0.0, 'count': (await _db.localSongs()).length});
          case 'spotify':
            _emitSpotify();
          case 'listenTogether':
            _listenTogether.publish();
          case 'nearby':
            _nearby.publish();
          case 'hydesync':
            _hydeSync.publish();
        }
        return true;

      // History & privacy
      case 'history.list':
        return [
          for (final e in await _db.history())
            {'id': e.id, 'timestamp': e.at.millisecondsSinceEpoch, 'track': Codec.track(e.track)},
        ];
      case 'history.remove':
        await _db.removeEvent((args['id'] as num).toInt());
        engine.notifyLibraryChanged();
        return true;
      case 'privacy.clearListenHistory':
        await _db.clearHistory();
        engine.notifyLibraryChanged();
        return true;
      case 'privacy.clearSearchHistory':
        await _db.clearSearches();
        return true;

      case 'stats':
        return _stats(args['period'] as String? ?? 'month');

      // Storage
      case 'storage.usage':
        return {
          'song': await _dirSize(Directory(p.join(engine.dirs.cache.path, 'just_audio_cache'))),
          'download': await _db.downloadedBytes(),
          'image': await _dirSize(Directory(p.join(engine.dirs.cache.path, DefaultCacheManager.key))),
        };
      case 'storage.clear':
        switch (args['kind']) {
          case 'download':
            await engine.downloader.removeAll();
            engine.notifyLibraryChanged();
          case 'image':
            await DefaultCacheManager().emptyCache();
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
          case 'song':
            final dir = Directory(p.join(engine.dirs.cache.path, 'just_audio_cache'));
            if (dir.existsSync()) await dir.delete(recursive: true);
        }
        return true;

      // Downloads
      case 'downloads.state':
        return engine.downloader.state;
      case 'downloads.pending':
        return [for (final t in await _db.pendingDownloads()) Codec.track(t)];
      case 'downloads.redownload':
        final pending = await _db.pendingDownloads();
        engine.downloader.enqueue(pending);
        return pending.length;
      case 'downloads.dismissPending':
        await _db.clearPendingDownloads();
        return true;

      // Local media
      case 'local.songs':
        return [for (final t in await _db.localSongs()) Codec.track(t)];
      case 'local.scan':
        return _scanLocal();

      // Lyrics tools
      case 'lyrics.search':
        return [
          for (final r in await engine.lyricsService.search(args['title'] as String? ?? '', args['artist'] as String? ?? ''))
            {
              'title': r.title,
              'artist': r.artist,
              'album': r.album,
              'duration': r.duration.inSeconds,
              'synced': r.synced,
              'text': r.text,
            },
        ];
      case 'lyrics.save':
        await engine.lyricsService.save(Codec.trackFrom(args['track'] as Map), args['text'] as String? ?? '');
        return true;
      case 'lyrics.refetch':
        final l = await engine.lyricsService.get(Codec.trackFrom(args['track'] as Map), refresh: true);
        return l.lines.isNotEmpty;

      // Account
      case 'account.state':
        return _accountState();
      case 'account.prepareLogin':
        await DartEngine.host.invokeMethod<void>('clearCookies');
        return true;
      case 'account.webCookies':
        return await DartEngine.host.invokeMethod<String>('getCookies', {'url': args['url']}) ?? '';
      case 'account.completeLogin':
        return _completeLogin(args);
      case 'account.sync':
        return syncAccountLibrary();
      case 'account.switch':
        await _db.setActiveAccount(args['id'] as String?);
        await _syncAccountSettings();
        await engine.reloadAccount();
        return true;
      case 'account.logout':
        final active = await _db.activeAccount();
        if (active != null) await _db.removeAccount(active['id'] as String);
        final next = (await _db.accounts()).firstOrNull;
        await _db.setActiveAccount(next?['id'] as String?);
        await _syncAccountSettings();
        await engine.reloadAccount();
        return true;

      // Discord
      case 'discord.setToken':
        final token = (args['token'] as String? ?? '').trim();
        if (token.isEmpty) throw const FormatException('Discord sign-in didn’t finish');
        final profile = await DiscordPresence.profile(token);
        if (profile == null) throw const FormatException('Discord didn’t accept the sign-in');
        await _settings.write('discordToken', token);
        await _settings.write('discordUsername', profile.username);
        await _settings.write('discordName', profile.name);
        _syncDiscord();
        _updateDiscord(engine.currentPlayback);
        return {'username': profile.username, 'name': profile.name};
      case 'discord.profile':
        final token = _nonEmpty(_settings.string('discordToken'));
        if (token == null) return null;
        final profile = await DiscordPresence.profile(token);
        return profile == null ? null : {'username': profile.username, 'name': profile.name};
      case 'discord.logout':
        await _settings.write('discordToken', null);
        await _settings.write('discordUsername', null);
        await _settings.write('discordName', null);
        _syncDiscord();
        return true;

      // Last.fm
      case 'lastfm.login':
        final String name;
        try {
          name = await _lastfm.login(args['username'] as String? ?? '', args['password'] as String? ?? '');
        } on StateError catch (e) {
          if (!LastFm.configured) rethrow;
          throw FormatException('Couldn’t sign in — ${e.message}');
        }
        await _settings.write('lastfmUsername', name);
        await _settings.write('lastfmSession', _lastfm.sessionKey);
        return name;
      case 'lastfm.logout':
        _lastfm.sessionKey = null;
        await _settings.write('lastfmUsername', null);
        await _settings.write('lastfmSession', null);
        return true;

      // Backup / restore / import
      case 'backup.create':
        return _backup();
      case 'backup.restore':
        return _restore();
      case 'import.csv':
        return _importFile(csv: true);
      case 'import.m3u':
        return _importFile(csv: false);
      case 'spotify.fetch':
        unawaited(_spotifyFetch(args['url'] as String? ?? ''));
        return true;
      case 'spotify.save':
        unawaited(_spotifySave(args['name'] as String?));
        return true;
      case 'spotify.reset':
        _spotify = null;
        _emitSpotify(fetch: {'state': 'idle'}, save: {'state': 'idle'});
        return true;

      // Listen Together
      case 'lt.create':
        _listenTogether.createRoom(args['username'] as String?);
        return true;
      case 'lt.join':
        _listenTogether.joinRoom(args['code'] as String? ?? '', args['username'] as String?);
        return true;
      case 'lt.leave':
        _listenTogether.leaveRoom();
        return true;
      case 'lt.approve':
        _listenTogether.approveJoin(args['userId'] as String);
        return true;
      case 'lt.reject':
        _listenTogether.rejectJoin(args['userId'] as String);
        return true;
      case 'lt.kick':
        _listenTogether.kick(args['userId'] as String);
        return true;
      case 'lt.block':
        _listenTogether.block(args['username'] as String);
        return true;
      case 'lt.unblock':
        _listenTogether.unblock(args['username'] as String);
        return true;
      case 'lt.transferHost':
        _listenTogether.transferHost(args['userId'] as String);
        return true;
      case 'lt.allowControl':
        _listenTogether.setAllowControl(args['allow'] == true);
        return true;
      case 'lt.chat':
        _listenTogether.chat(args['message'] as String? ?? '');
        return true;
      case 'lt.suggest':
        _listenTogether.suggest(Codec.trackFrom(args['track'] as Map));
        return true;
      case 'lt.approveSuggestion':
        _listenTogether.approveSuggestion(args['id'] as String);
        return true;
      case 'lt.rejectSuggestion':
        _listenTogether.rejectSuggestion(args['id'] as String);
        return true;
      case 'lt.reconnect':
        _listenTogether.forceReconnect();
        return true;
      case 'lt.clearLogs':
        _listenTogether.clearLogs();
        return true;

      // Nearby Sync
      case 'nearby.host':
        await _nearby.host();
        return true;
      case 'nearby.discover':
        await _nearby.discover();
        return true;
      case 'nearby.stopDiscovery':
        await _nearby.stopDiscovery();
        return true;
      case 'nearby.connect':
        await _nearby.connect(args['name'] as String? ?? '');
        return true;
      case 'nearby.stop':
        await _nearby.stop();
        return true;

      // Hyde Sync
      case 'hydesync.signIn':
        await _hydeSync.signIn(args['email'] as String? ?? '', args['password'] as String? ?? '');
        return true;
      case 'hydesync.signUp':
        await _hydeSync.signIn(args['email'] as String? ?? '', args['password'] as String? ?? '', create: true);
        return true;
      case 'hydesync.sync':
        await _hydeSync.sync();
        return true;
      case 'hydesync.signOut':
        await _hydeSync.signOut();
        return true;

      case 'url.open':
        final url = Uri.tryParse(args['url'] as String? ?? '');
        if (url == null) return false;
        return launchUrl(url, mode: LaunchMode.externalApplication);
    }
    throw FeatureUnavailable('“$method” isn’t available');
  }

  // ── Stats ────────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _stats(String period) async {
    final now = DateTime.now();
    final from = switch (period) {
      'day' => now.subtract(const Duration(days: 1)),
      'week' => now.subtract(const Duration(days: 7)),
      'month' => now.subtract(const Duration(days: 30)),
      // Calendar year, like the native stats and the Wrapped story.
      'year' => DateTime(now.year),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    }.millisecondsSinceEpoch;
    final totals = await _db.totals(from);
    final songs = await _db.mostPlayedSongs(from, limit: 30);
    final artists = await _db.mostPlayedArtists(from, limit: 20);
    final albums = await _db.mostPlayedAlbums(from, limit: 20);
    return {
      'totalMs': totals.ms,
      'totalPlays': totals.plays,
      'songs': [
        for (final s in songs) {...Codec.track(s.track), 'plays': s.plays, 'ms': s.ms},
      ],
      'artists': [
        for (final a in artists) {...Codec.artist(a.artist), 'plays': a.plays, 'ms': a.ms},
      ],
      'albums': [
        for (final a in albums) {...Codec.album(a.album), 'plays': a.plays, 'ms': a.ms},
      ],
    };
  }

  static Future<int> _dirSize(Directory dir) async {
    if (!dir.existsSync()) return 0;
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }

  // ── Local media ──────────────────────────────────────────────────────────

  bool _scanning = false;

  Future<bool> _scanLocal() async {
    if (_scanning) return true;
    // Android 13+: READ_MEDIA_AUDIO; older: READ_EXTERNAL_STORAGE.
    final granted = await Permission.audio.request().isGranted || await Permission.storage.request().isGranted;
    if (!granted) throw const FormatException('Allow access to music files to scan your device');
    _scanning = true;
    engine.emitFeature({'topic': 'local', 'scanning': true, 'progress': 0.0, 'count': (await _db.localSongs()).length});
    try {
      final files = (await DartEngine.host.invokeMethod<List>('queryAudio') ?? const []).cast<Map>();
      final excluded = (_settings['excludedScanPaths'] as String? ?? '').split('\n').where((s) => s.trim().isNotEmpty).toList();
      final keep = <String>{};
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final path = f['path'] as String? ?? '';
        final durationMs = (f['durationMs'] as num?)?.toInt() ?? 0;
        // Skip ringtones / voice notes and excluded folders.
        if (durationMs < 30000 || excluded.any(path.startsWith)) continue;
        final id = 'LA${f['id']}_local';
        keep.add(id);
        await _db.upsertLocalSong(
          id: id,
          title: (f['title'] as String?)?.trim().isNotEmpty ?? false ? f['title'] as String : p.basenameWithoutExtension(path),
          path: (f['uri'] as String?) ?? path,
          durationSec: durationMs ~/ 1000,
          artist: f['artist'] as String?,
          album: f['album'] as String?,
          artworkUri: f['artworkUri'] as String?,
        );
        if (i % 25 == 0) {
          engine.emitFeature({'topic': 'local', 'scanning': true, 'progress': i / files.length, 'count': keep.length});
        }
      }
      await _db.removeLocalSongsExcept(keep);
      engine.emitFeature({'topic': 'local', 'scanning': false, 'progress': 1.0, 'count': keep.length});
      engine.notifyLibraryChanged();
      return true;
    } finally {
      _scanning = false;
    }
  }

  // ── Matching (imports, recognition) ─────────────────────────────────────

  /// Best YouTube Music song for a title + artist, or null.
  Future<Track?> match(String title, String artist) async {
    final page = await engine.youtube.search('$title $artist'.trim(), SearchFilter.songs);
    final track = page.items.whereType<TrackItem>().firstOrNull?.track;
    return track == null ? null : (await _db.decorate([track])).first;
  }

  /// Matches many (title, artist) pairs, four at a time; unmatched are dropped.
  Future<List<Track>> _matchAll(List<(String, String)> wanted, {void Function(int done, int matched, String current)? onProgress}) async {
    final out = List<Track?>.filled(wanted.length, null);
    var next = 0, done = 0, matched = 0;
    Future<void> worker() async {
      while (next < wanted.length) {
        final i = next++;
        try {
          out[i] = await match(wanted[i].$1, wanted[i].$2);
          if (out[i] != null) matched++;
        } catch (_) {}
        done++;
        onProgress?.call(done, matched, wanted[i].$1);
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    final seen = <String>{};
    return [
      for (final t in out)
        if (t != null && seen.add(t.id)) t,
    ];
  }

  // ── Backup / restore ─────────────────────────────────────────────────────

  static const _dbEntry = 'song.db';
  static const _settingsEntry = 'settings.json';
  static const _legacySettingsEntry = 'settings.preferences_pb';

  Future<bool> _backup() async {
    final dbFile = File(_db.db.path);
    await _db.db.execute('PRAGMA wal_checkpoint(FULL)');
    final archive = Archive()
      ..addFile(ArchiveFile.bytes(_dbEntry, await dbFile.readAsBytes()))
      ..addFile(ArchiveFile.string(_settingsEntry, jsonEncode(_settings.all)));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${d.year}${two(d.month)}${two(d.day)}${two(d.hour)}${two(d.minute)}${two(d.second)}';
    final saved = await FilePicker.saveFile(fileName: 'Hyde Music_$stamp.backup', bytes: bytes);
    return saved != null;
  }

  /// Restores a backup made by this app or by the native 4.x app (same zip:
  /// song.db + settings). The app must be reopened afterwards.
  Future<bool> _restore() async {
    final file = (await FilePicker.pickFiles()).firstOrNull;
    if (file == null) return false;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      throw const FormatException('Couldn’t read that file');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('That isn’t a Hyde Music backup');
    }
    final dbEntry = archive.findFile(_dbEntry);
    if (dbEntry == null) throw const FormatException('That isn’t a Hyde Music backup');

    final json = archive.findFile(_settingsEntry);
    final legacy = archive.findFile(_legacySettingsEntry);
    if (json != null) {
      await _settings.replaceAll((jsonDecode(utf8.decode(json.content as List<int>)) as Map).cast<String, Object?>());
    } else if (legacy != null) {
      await _settings.replaceAll(SettingsStore.decodeDataStore(Uint8List.fromList(legacy.content as List<int>)));
    }

    await engine.player.stop();
    final path = _db.db.path;
    await _db.close();
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (f.existsSync()) await f.delete();
    }
    await File(path).writeAsBytes(dbEntry.content as List<int>, flush: true);
    // The engine holds the old database handle; a clean start is the safe way
    // to pick everything up.
    Timer(const Duration(milliseconds: 1500), () => exit(0));
    throw const FeatureUnavailable('Backup restored. Hyde Music will close — open it again to finish.');
  }

  Future<List<Map<String, Object?>>> _importFile({required bool csv}) async {
    final file = (await FilePicker.pickFiles()).firstOrNull;
    if (file == null) return const [];
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      throw const FormatException('Couldn’t read that file');
    }
    final lines = const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true));
    final wanted = <(String, String)>[];
    if (csv) {
      for (final line in lines) {
        final parts = _csvFields(line);
        if (parts.isEmpty || parts.first.trim().isEmpty) continue;
        final title = parts.first.trim();
        // Skip a header row.
        if (wanted.isEmpty && const {'title', 'track name', 'name', 'song'}.contains(title.toLowerCase())) continue;
        wanted.add((title, parts.length > 1 ? parts[1].split(';').first.trim() : ''));
      }
    } else {
      if (lines.isEmpty || !lines.first.startsWith('#EXTM3U')) throw const FormatException('That isn’t an M3U playlist');
      for (final line in lines) {
        if (!line.startsWith('#EXTINF:')) continue;
        final info = line.substring(line.indexOf(',') + 1);
        final dash = info.indexOf(' - ');
        wanted.add(dash < 0 ? (info.trim(), '') : (info.substring(dash + 3).trim(), info.substring(0, dash).split(';').first.trim()));
      }
    }
    if (wanted.isEmpty) throw const FormatException('No songs found in that file');
    final tracks = await _matchAll(wanted.take(500).toList());
    if (tracks.isEmpty) throw const FormatException('None of the songs could be found');
    return [for (final t in tracks) Codec.track(t)];
  }

  /// One CSV line → fields (quotes and doubled quotes handled).
  static List<String> _csvFields(String line) {
    final out = <String>[];
    final cur = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (c == ',' && !quoted) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(c);
      }
    }
    out.add(cur.toString());
    return out;
  }

  // ── Spotify import ───────────────────────────────────────────────────────

  ({String name, List<(String, String)> tracks})? _spotify;
  Map<String, Object?> _spotifyFetchState = {'state': 'idle'};
  Map<String, Object?> _spotifySaveState = {'state': 'idle'};

  void _emitSpotify({Map<String, Object?>? fetch, Map<String, Object?>? save}) {
    _spotifyFetchState = fetch ?? _spotifyFetchState;
    _spotifySaveState = save ?? _spotifySaveState;
    engine.emitFeature({'topic': 'spotify', 'fetch': _spotifyFetchState, 'save': _spotifySaveState});
  }

  static final _spotifyId = RegExp(r'playlist(?:[/:]|%2F)([A-Za-z0-9]+)');
  static const _browserUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// Reads a public Spotify playlist from its embed page (no Spotify account).
  Future<void> _spotifyFetch(String url) async {
    final id = _spotifyId.firstMatch(url)?.group(1);
    if (id == null) return _emitSpotify(fetch: {'state': 'error', 'message': 'Paste a Spotify playlist link'});
    _emitSpotify(fetch: {'state': 'loading'}, save: {'state': 'idle'});
    final client = http.Client();
    try {
      final res = await client
          .get(Uri.parse('https://open.spotify.com/embed/playlist/$id'), headers: {'User-Agent': _browserUa})
          .timeout(const Duration(seconds: 20));
      final m = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true).firstMatch(utf8.decode(res.bodyBytes));
      if (res.statusCode != 200 || m == null) throw const FormatException('Couldn’t open that playlist — is it public?');
      final data = jsonDecode(m.group(1)!) as Map;
      final state = ((data['props'] as Map?)?['pageProps'] as Map?)?['state'] as Map?;
      final entity = (state?['data'] as Map?)?['entity'] as Map?;
      if (entity == null) throw const FormatException('Couldn’t read that playlist');
      final name = entity['name'] as String? ?? entity['title'] as String? ?? 'Spotify playlist';
      final tracks = <(String, String)>[
        for (final t in (entity['trackList'] as List? ?? const []).cast<Map>())
          if (t['title'] is String) (t['title'] as String, (t['subtitle'] as String? ?? '').split(',').first.replaceAll(' ', ' ').trim()),
      ];
      // The embed page lists the first 100 tracks; the web API has the rest.
      final token = ((state?['settings'] as Map?)?['session'] as Map?)?['accessToken'] as String?;
      if (token != null && tracks.length >= 100) {
        var next = 'https://api.spotify.com/v1/playlists/$id/tracks?offset=100&limit=100&fields=next,items(track(name,artists(name)))';
        while (next.isNotEmpty && tracks.length < 2000) {
          final page = await client.get(Uri.parse(next), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 20));
          if (page.statusCode != 200) break;
          final j = jsonDecode(utf8.decode(page.bodyBytes)) as Map;
          for (final item in (j['items'] as List? ?? const []).cast<Map>()) {
            final t = item['track'] as Map?;
            if (t?['name'] is String) {
              tracks.add((t!['name'] as String, (((t['artists'] as List?)?.firstOrNull as Map?)?['name'] as String?) ?? ''));
            }
          }
          next = j['next'] as String? ?? '';
          _emitSpotify(fetch: {'state': 'progress', 'loaded': tracks.length, 'total': tracks.length});
        }
      }
      if (tracks.isEmpty) throw const FormatException('That playlist is empty');
      _spotify = (name: name, tracks: tracks);
      _emitSpotify(fetch: {'state': 'ready', 'name': name, 'count': tracks.length});
    } catch (e) {
      _emitSpotify(fetch: {'state': 'error', 'message': e is FormatException ? e.message : 'Couldn’t reach Spotify'});
    } finally {
      client.close();
    }
  }

  Future<void> _spotifySave(String? name) async {
    final src = _spotify;
    if (src == null) return;
    final total = src.tracks.length;
    _emitSpotify(save: {'state': 'saving', 'matched': 0, 'failed': 0, 'total': total, 'current': ''});
    try {
      final tracks = await _matchAll(
        src.tracks,
        onProgress: (done, matched, current) =>
            _emitSpotify(save: {'state': 'saving', 'matched': matched, 'failed': done - matched, 'total': total, 'current': current}),
      );
      if (tracks.isEmpty) throw const FormatException('None of the songs could be found');
      final playlistName = (name == null || name.trim().isEmpty) ? src.name : name.trim();
      final playlist = await _db.createPlaylist(playlistName);
      await _db.setPlaylistSongs(playlist.id, tracks);
      engine.notifyLibraryChanged();
      _emitSpotify(save: {'state': 'done', 'matched': tracks.length, 'failed': total - tracks.length, 'name': playlistName});
    } catch (e) {
      _emitSpotify(save: {'state': 'error', 'message': e is FormatException ? e.message : 'Import failed — check your connection'});
    }
  }

  // ── Account ──────────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _accountState() async {
    final accounts = await _db.accounts();
    final active = accounts.where((a) => a['isActive'] == 1).firstOrNull;
    final legacy = _settings.string('innerTubeCookie');
    final signedIn = engine.tube.signedIn;
    return {
      'signedIn': signedIn,
      'name': active?['name'] ?? _settings.string('accountName'),
      'email': active?['email'] ?? _settings.string('accountEmail'),
      'handle': active?['channelHandle'] ?? _settings.string('accountChannelHandle'),
      'thumbnailUrl': active?['thumbnailUrl'],
      'accounts': [
        for (final a in accounts)
          {
            'id': a['id'],
            'name': a['name'],
            'email': a['email'],
            'thumbnailUrl': a['thumbnailUrl'],
            'active': a['isActive'] == 1,
          },
        // Signed in by the old app before it had an account table.
        if (accounts.isEmpty && signedIn && legacy != null)
          {
            'id': 'legacy',
            'name': _settings.string('accountName') ?? 'Account',
            'email': _settings.string('accountEmail') ?? '',
            'active': true,
          },
      ],
    };
  }

  /// Stores the cookie captured by the sign-in web view and loads the profile.
  Future<bool> _completeLogin(Map<String, Object?> args) async {
    final cookie = (args['cookie'] as String?)?.trim() ?? '';
    if (!cookie.contains('SAPISID')) throw const FormatException('Sign-in didn’t finish');
    final tube = engine.tube;
    final previous = (cookie: tube.cookie, visitor: tube.visitorData, sync: tube.dataSyncId);
    tube.cookie = cookie;
    final visitor = args['visitorData'] as String?;
    if (visitor != null && visitor.isNotEmpty) tube.visitorData = visitor;
    final sync = args['dataSyncId'] as String?;
    tube.dataSyncId = (sync == null || sync.isEmpty) ? null : sync.split('||').first;
    final info = await engine.youtube.accountInfo().catchError((_) => null);
    if (info == null) {
      tube
        ..cookie = previous.cookie
        ..visitorData = previous.visitor
        ..dataSyncId = previous.sync;
      throw const FormatException('Couldn’t load your account');
    }
    await _db.saveAccount(
      email: info.email ?? info.handle ?? info.name,
      name: info.name,
      cookie: cookie,
      handle: info.handle,
      thumbnailUrl: info.thumbnailUrl,
      visitorData: tube.visitorData,
      dataSyncId: tube.dataSyncId,
    );
    await _syncAccountSettings();
    await engine.reloadAccount();
    if (_settings.boolean('ytmSync', true)) unawaited(syncAccountLibrary().catchError((_) => 0));
    return true;
  }

  /// Mirrors the active account into the legacy settings keys other code reads.
  Future<void> _syncAccountSettings() async {
    final a = await _db.activeAccount();
    await _settings.write('innerTubeCookie', a?['innerTubeCookie']);
    await _settings.write('accountName', a?['name']);
    await _settings.write('accountEmail', a?['email']);
    await _settings.write('accountChannelHandle', a?['channelHandle']);
    await _settings.write('dataSyncId', a?['dataSyncId']);
    if (a?['visitorData'] case final String v when v.isNotEmpty) await _settings.write('visitorData', v);
  }

  /// Pulls the account's liked songs and saved playlists into the library.
  /// Returns how many songs were added.
  Future<int> syncAccountLibrary() async {
    if (!engine.tube.signedIn) return 0;
    var added = 0;
    // Liked music ("LM").
    final liked = await engine.youtube.playlist('LM', maxPages: 20);
    final have = (await _db.likedSongs()).map((t) => t.id).toSet();
    for (final t in liked.tracks.reversed) {
      if (have.contains(t.id)) continue;
      await _db.setLiked(t, true);
      added++;
    }
    // Saved / own playlists become library playlists linked by browseId.
    final playlists = (await engine.youtube.library('FEmusic_liked_playlists')).whereType<PlaylistItem>();
    for (final item in playlists) {
      final id = item.playlist.id;
      if (id == 'LM' || id == 'SE' || id.isEmpty) continue;
      if (await _db.playlistRow(id) != null) continue;
      try {
        final page = await engine.youtube.playlist(id, maxPages: 10);
        final local = await _db.createPlaylist(
          page.title,
          browseId: id,
          thumbnailUrl: page.thumbnailUrl,
          editable: page.playlist?.isEditable ?? false,
        );
        await _db.setPlaylistSongs(local.id, page.tracks);
      } catch (_) {}
    }
    await _settings.write('ytmLastSync', DateTime.now().millisecondsSinceEpoch);
    engine.notifyLibraryChanged();
    return added;
  }
}
