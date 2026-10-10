import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart' as svc;
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../models.dart';
import 'codec.dart';
import 'database.dart';
import 'listen_together.dart' show ListenTogetherPlayer;
import 'smart_shuffle.dart';
import 'stream_resolver.dart';
import 'youtube.dart';
import 'youtube_audio_source.dart';

/// Reads a setting by its DataStore key name.
typedef SettingReader = Object? Function(String key);

/// Playback: queue, transport, radio continuation, history and the system
/// media session (notification, lock screen, headset buttons, Android Auto).
///
/// One just_audio player; each track's source is created when it becomes
/// current, so stream URLs are resolved lazily and never go stale in a queue.
class HydePlayer extends svc.BaseAudioHandler with svc.SeekHandler implements ListenTogetherPlayer {
  HydePlayer({
    required this.db,
    required this.resolver,
    required this.youtube,
    required this.setting,
    required this.queueFile,
  }) : _reader = RangedReader(resolver);

  final HydeDatabase db;
  final StreamResolver resolver;
  final YouTube youtube;
  final SettingReader setting;

  /// Where the queue is persisted between launches (`persistentQueue`).
  final File queueFile;

  final RangedReader _reader;
  final _player = AudioPlayer();
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast();
  final _rand = Random();

  List<Track> _queue = [];

  /// Order before shuffle was switched on, to restore it when switched off.
  List<Track>? _unshuffled;
  int _index = 0;
  bool _shuffle = false;
  QueueRepeat _repeat = QueueRepeat.off;
  AudioFormat? _format;
  String? _error;
  DateTime? _sleepEnd;
  bool _sleepAtEndOfTrack = false;
  Timer? _sleepTimer;
  bool _loading = false;
  int _loadToken = 0;
  int _consecutiveErrors = 0;

  // Radio / automix continuation for the current queue.
  String? _radioContinuation;
  String? _radioPlaylistId;
  String? _radioParams;
  bool _loadingMore = false;

  // Listening time of the current track (for history / stats / scrobbling).
  Track? _timedTrack;
  final _listened = Stopwatch();
  String? _trackingUrl;

  /// Called when a track has been listened to long enough to count
  /// (Last.fm scrobble, Discord, YouTube history live in the engine).
  void Function(Track track, Duration listened)? onListened;

  /// Called whenever the current track changes (now-playing integrations).
  void Function(Track? track)? onTrackChanged;

  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;
  PlaybackSnapshot _current = const PlaybackSnapshot();
  @override
  PlaybackSnapshot get current => _current;
  int? get androidAudioSessionId => _player.androidAudioSessionId;
  Track? get _track => _index >= 0 && _index < _queue.length ? _queue[_index] : null;

  bool _bool(String key, [bool fallback = false]) => setting(key) as bool? ?? fallback;

  // ── Setup ────────────────────────────────────────────────────────────────

  Future<void> init() async {
    // Mobile only: desktop has no audio focus (and no audio_session plugin).
    if (Platform.isAndroid || Platform.isIOS) {
      final session = await AudioSession.instance;
      // just_audio itself reacts to audio focus (calls, other apps) and to
      // headphones being unplugged; it only needs to know this is music.
      await session.configure(const AudioSessionConfiguration.music());
    }

    _player.playerStateStream.listen((_) => _emit());
    _player.durationStream.listen((_) => _emit());
    _player.bufferedPositionStream.listen((_) => _emit(positionOnly: true));
    // 4 Hz position updates while playing.
    _player.createPositionStream(
      minPeriod: const Duration(milliseconds: 250),
      maxPeriod: const Duration(milliseconds: 250),
    ).listen((position) {
      _skipSponsorSegment(position);
      _emit(positionOnly: true);
    });
    _player.playingStream.listen((playing) {
      if (playing) {
        _listened.start();
      } else {
        _listened.stop();
      }
    });
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onCompleted();
    });
    _player.errorStream.listen((e) => _onPlaybackError(e.message ?? 'Playback error'));

    await applySettings();
    if (_bool('persistentQueue', true)) await _restoreQueue();
  }

  // ── SponsorBlock ─────────────────────────────────────────────────────────

  /// Segments of the current track to jump over (non-music intros, talk…).
  List<(Duration start, Duration end)> _sponsorSegments = const [];

  Future<void> _loadSponsorSegments(Track t, int token) async {
    _sponsorSegments = const [];
    if (!_bool('sponsorBlockEnabled') || t.isLocal) return;
    final wanted = ((setting('sponsorBlockCategories') as String?) ?? '').split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
    final categories = wanted.isEmpty ? const ['sponsor', 'intro', 'outro', 'interaction', 'selfpromo', 'music_offtopic'] : wanted;
    try {
      final res = await youtube.tube
          .get(Uri.https('sponsor.ajay.app', '/api/skipSegments', {'videoID': t.id, 'categories': jsonEncode(categories)}))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || token != _loadToken) return; // 404 = no segments
      _sponsorSegments = [
        for (final s in (jsonDecode(res.body) as List).cast<Map>())
          if (s['segment'] case [final num a, final num b] when b - a >= 1)
            (Duration(milliseconds: (a * 1000).round()), Duration(milliseconds: (b * 1000).round())),
      ];
    } catch (_) {}
  }

  void _skipSponsorSegment(Duration position) {
    if (_sponsorSegments.isEmpty || !_player.playing) return;
    for (final (start, end) in _sponsorSegments) {
      if (position >= start && position < end - const Duration(milliseconds: 300)) {
        final total = _player.duration;
        // A segment that runs to the end of the file: let the track finish naturally.
        if (total != null && end >= total - const Duration(seconds: 1)) {
          unawaited(_player.seek(total));
        } else {
          unawaited(_player.seek(end));
        }
        return;
      }
    }
  }

  /// Re-reads playback settings (called at start and when one changes).
  Future<void> applySettings() async {
    resolver.quality = switch (setting('audioQuality')) {
      'DATA_SAVER' => AudioQuality.low,
      'BEST_AVAILABLE' => AudioQuality.high,
      _ => AudioQuality.auto,
    };
    try {
      await _player.setSkipSilenceEnabled(_bool('skipSilence'));
    } catch (_) {}
    await _player.setVolume(_normalizedVolume());
  }

  double _userVolume = 1;

  /// Loudness normalisation: attenuate tracks mastered louder than the
  /// reference (never boosts, so nothing clips).
  double _normalizedVolume() {
    var v = _userVolume;
    final loud = _format?.loudnessDb;
    if (loud != null && loud > 0 && _bool('audioNormalization', true)) {
      v *= pow(10, -loud / 20).toDouble().clamp(0.1, 1.0);
    }
    return v;
  }

  // ── Queue control (called by the engine) ─────────────────────────────────

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false, bool radio = true}) async {
    if (tracks.isEmpty) return;
    await _commitListen();
    var list = List.of(tracks);
    var index = startIndex.clamp(0, list.length - 1);
    final keepShuffle = _bool('persistentShuffleAcrossQueues') && _shuffle;
    _unshuffled = null;
    _shuffle = shuffle || keepShuffle;
    if (_shuffle) {
      _unshuffled = List.of(list);
      final first = shuffle && startIndex == 0 ? list.removeAt(_rand.nextInt(list.length)) : list.removeAt(index);
      list = _shuffled(list, after: first);
      list.insert(0, first);
      index = 0;
    }
    _queue = list;
    _index = index;
    _radioContinuation = null;
    _radioPlaylistId = null;
    _radioParams = null;
    _consecutiveErrors = 0;
    await _load(play: true);
    // A single song (search result, quick pick): continue with its radio, like the native app.
    if (radio && tracks.length == 1) unawaited(_startRadioFor(tracks.first, replaceQueue: false));
  }

  /// Seeds the queue with [seed]'s radio. With [replaceQueue] the seed starts
  /// playing now; otherwise the radio is appended behind what's playing.
  Future<void> startRadio(Track seed, {String? playlistId, String? params}) async {
    await _commitListen();
    _queue = [seed];
    _index = 0;
    _unshuffled = null;
    _consecutiveErrors = 0;
    await _load(play: true);
    await _startRadioFor(seed, replaceQueue: false, playlistId: playlistId, params: params);
  }

  Future<void> _startRadioFor(Track seed, {required bool replaceQueue, String? playlistId, String? params}) async {
    try {
      final page = await youtube.next(videoId: seed.id, playlistId: playlistId ?? 'RDAMVM${seed.id}', params: params);
      if (_track?.id != seed.id) return; // user moved on meanwhile
      final have = _queue.map((t) => t.id).toSet();
      final more = (await db.decorate(page.tracks)).where((t) => have.add(t.id)).toList();
      _queue = [..._queue, ...more];
      _radioContinuation = page.continuation;
      _radioPlaylistId = page.playlistId;
      _radioParams = page.params;
      unawaited(db.setRelated(seed, more.take(25).toList()).catchError((_) {}));
      _emit();
      _persistSoon();
    } catch (_) {
      // Radio is best-effort; the seed keeps playing.
    }
  }

  /// Loads [track] as the whole queue without starting it (synced sessions
  /// start everyone together).
  @override
  Future<void> prepareTrack(Track track) async {
    await _commitListen();
    _queue = [track];
    _index = 0;
    _unshuffled = null;
    _radioContinuation = null;
    _radioPlaylistId = null;
    _radioParams = null;
    _consecutiveErrors = 0;
    await _load(play: false);
    if (_error != null) throw StreamUnavailable(_error!);
  }

  /// Plays an online queue (album / playlist id) from YouTube's watch endpoint.
  Future<void> setRadioContinuation({String? continuation, String? playlistId, String? params}) async {
    _radioContinuation = continuation;
    _radioPlaylistId = playlistId;
    _radioParams = params;
  }

  Future<void> _loadMoreIfNeeded() async {
    if (_loadingMore || !_bool('autoLoadMore', true)) return;
    if (_repeat == QueueRepeat.all && _bool('disableLoadMoreWhenRepeatAll')) return;
    if (_queue.length - _index > 5) return;
    final seed = _track;
    if (seed == null || seed.isLocal) return;
    _loadingMore = true;
    try {
      NextPage page;
      if (_radioContinuation != null) {
        page = await youtube.next(playlistId: _radioPlaylistId, params: _radioParams, continuation: _radioContinuation);
      } else if (_bool('similarContent', true)) {
        final last = _queue.last;
        if (last.isLocal) return;
        page = await youtube.next(videoId: last.id, playlistId: 'RDAMVM${last.id}');
      } else {
        return;
      }
      final have = _queue.map((t) => t.id).toSet();
      final more = (await db.decorate(page.tracks)).where((t) => have.add(t.id)).toList();
      _radioContinuation = page.continuation;
      _radioPlaylistId = page.playlistId ?? _radioPlaylistId;
      _radioParams = page.params ?? _radioParams;
      if (more.isNotEmpty) {
        _queue = [..._queue, ...more];
        _emit();
        _persistSoon();
      }
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Future<void> playNext(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    if (_queue.isEmpty) return playTracks(tracks, radio: false);
    final add = _withoutDuplicates(tracks);
    _queue = [..._queue.sublist(0, _index + 1), ...add, ..._queue.sublist(_index + 1)];
    _unshuffled?.addAll(add);
    _emit();
    _persistSoon();
  }

  @override
  Future<void> addToQueue(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    if (_queue.isEmpty) return playTracks(tracks, radio: false);
    final add = _withoutDuplicates(tracks);
    _queue = [..._queue, ...add];
    _unshuffled?.addAll(add);
    _emit();
    _persistSoon();
  }

  List<Track> _withoutDuplicates(List<Track> tracks) {
    if (!_bool('preventDuplicateTracksInQueue')) return tracks;
    final have = _queue.map((t) => t.id).toSet();
    return tracks.where((t) => have.add(t.id)).toList();
  }

  Future<void> moveQueueItem(int from, int to) async {
    if (from < 0 || from >= _queue.length || to < 0 || to >= _queue.length || from == to) return;
    final list = List.of(_queue);
    final item = list.removeAt(from);
    list.insert(to, item);
    if (from == _index) {
      _index = to;
    } else if (from < _index && to >= _index) {
      _index--;
    } else if (from > _index && to <= _index) {
      _index++;
    }
    _queue = list;
    _emit();
    _persistSoon();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final removed = _queue[index];
    final list = List.of(_queue)..removeAt(index);
    _unshuffled?.removeWhere((t) => t.id == removed.id);
    if (index == _index) {
      _queue = list;
      if (list.isEmpty) return stop();
      _index = _index.clamp(0, list.length - 1);
      await _commitListen();
      return _load(play: _player.playing);
    }
    if (index < _index) _index--;
    _queue = list;
    _emit();
    _persistSoon();
  }

  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _commitListen();
    _index = index;
    await _load(play: true);
  }

  bool get isShuffled => _shuffle;

  /// Random order, or AI Shuffle order when `smartShuffleEnabled` is on.
  List<Track> _shuffled(List<Track> tracks, {required Track after}) {
    if (_bool('smartShuffleEnabled')) return smartShuffle(tracks, first: after, random: _rand).skip(1).toList();
    return List.of(tracks)..shuffle(_rand);
  }

  Future<void> setShuffle(bool enabled) async {
    if (enabled == _shuffle) return;
    _shuffle = enabled;
    final cur = _track;
    if (cur != null) {
      if (enabled) {
        _unshuffled = List.of(_queue);
        final rest = List.of(_queue)..removeAt(_index);
        _queue = [cur, ..._shuffled(rest, after: cur)];
        _index = 0;
      } else if (_unshuffled != null) {
        final ids = _queue.map((t) => t.id).toSet();
        final restored = _unshuffled!.where((t) => ids.contains(t.id)).toList();
        final known = restored.map((t) => t.id).toSet();
        // Tracks added while shuffled (radio) keep their place at the end.
        _queue = [...restored, ..._queue.where((t) => !known.contains(t.id))];
        _index = max(0, _queue.indexWhere((t) => t.id == cur.id));
        _unshuffled = null;
      }
    }
    _emit();
    _persistSoon();
  }

  Future<void> setRepeat(QueueRepeat mode) async {
    _repeat = mode;
    _emit();
    _persistSoon();
  }

  Future<void> setUserVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_normalizedVolume());
    _emit();
  }

  Future<void> setPlaybackParameters({required double speed, required double pitch}) async {
    await _player.setSpeed(speed.clamp(0.25, 3.0));
    try {
      await _player.setPitch(pitch.clamp(0.25, 3.0));
    } catch (_) {}
    _emit();
  }

  ({double speed, double pitch}) get playbackParameters => (speed: _player.speed, pitch: _player.pitch);

  void setSleepTimer(Duration? duration, {bool endOfTrack = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAtEndOfTrack = endOfTrack;
    _sleepEnd = null;
    if (endOfTrack) {
      final left = (_player.duration ?? Duration.zero) - _player.position;
      _sleepEnd = DateTime.now().add(left.isNegative ? Duration.zero : left);
    } else if (duration != null) {
      _sleepEnd = DateTime.now().add(duration);
      _sleepTimer = Timer(duration, () {
        _sleepEnd = null;
        pause();
      });
    }
    _emit();
  }

  /// Updates the stored flags of a track everywhere it appears in the queue.
  void patchTrack(String id, Track Function(Track) patch) {
    if (!_queue.any((t) => t.id == id)) return;
    _queue = [for (final t in _queue) t.id == id ? patch(t) : t];
    _emit();
  }

  // ── Loading & transitions ────────────────────────────────────────────────

  Future<AudioSource> _sourceFor(Track t) async {
    final local = await db.localPath(t.id);
    if (local != null) {
      return local.startsWith('content://') ? AudioSource.uri(Uri.parse(local)) : AudioSource.file(local);
    }
    final downloaded = await db.downloadPath(t.id);
    if (downloaded != null && File(downloaded).existsSync()) return AudioSource.file(downloaded);
    return YoutubeAudioSource(t.id, resolver, _reader);
  }

  Future<void> _load({required bool play, Duration? position}) async {
    final t = _track;
    if (t == null) return;
    final token = ++_loadToken;
    _loading = true;
    _error = null;
    _format = null;
    _trackingUrl = null;
    _sponsorSegments = const [];
    _timedTrack = t;
    _listened
      ..reset()
      ..stop();
    _emit();
    _publishMediaItem(t);
    onTrackChanged?.call(t);
    unawaited(db.ensureTrack(t).catchError((_) {}));
    try {
      await _player.stop();
      final source = await _sourceFor(t);
      if (token != _loadToken) return;
      if (source is YoutubeAudioSource) {
        // Resolve up front so failures surface here (with YouTube's reason)
        // rather than as an opaque player error.
        final stream = await resolver.resolve(t.id);
        if (token != _loadToken) return;
        _format = stream.format;
        _trackingUrl = stream.playbackTrackingUrl;
        unawaited(
          db.setFormat(t.id, stream.format, contentLength: stream.contentLength ?? 0, itag: stream.itag).catchError((_) {}),
        );
      } else {
        _format = await db.format(t.id);
      }
      await _player.setVolume(_normalizedVolume());
      await _player.setAudioSource(source, initialPosition: position);
      if (token != _loadToken) return;
      _loading = false;
      _consecutiveErrors = 0;
      _emit();
      if (play) unawaited(_player.play());
      _persistSoon();
      unawaited(_loadSponsorSegments(t, token));
      unawaited(_prefetchNext());
      unawaited(_loadMoreIfNeeded());
    } catch (e) {
      if (token != _loadToken) return;
      _loading = false;
      _onPlaybackError(_friendly(e));
    }
  }

  static String _friendly(Object e) {
    if (e is StreamUnavailable) return e.reason;
    if (e is SocketException || e is TimeoutException) return 'No connection';
    if (e is PlayerException) return e.message ?? 'Playback error';
    return 'Couldn’t play this song';
  }

  void _onPlaybackError(String message) {
    _error = message;
    _consecutiveErrors++;
    final t = _track;
    if (t != null) resolver.invalidate(t.id);
    _emit();
    // Skip a broken track, but never spin through the whole queue offline.
    if (_bool('autoSkipNextOnError', true) && _consecutiveErrors < 3 && _index < _queue.length - 1) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (_error == message) skipToNext();
      });
    }
  }

  /// Warms the next track's stream URL so the transition is instant.
  Future<void> _prefetchNext() async {
    final next = _index + 1 < _queue.length ? _queue[_index + 1] : null;
    if (next == null || next.isLocal) return;
    if (await db.downloadPath(next.id) != null) return;
    try {
      await resolver.resolve(next.id);
    } catch (_) {}
  }

  Future<void> _onCompleted() async {
    await _commitListen();
    if (_sleepAtEndOfTrack) {
      _sleepAtEndOfTrack = false;
      _sleepEnd = null;
      await _player.pause();
      await _player.seek(Duration.zero);
      _emit();
      return;
    }
    if (_repeat == QueueRepeat.one) {
      await _player.seek(Duration.zero);
      _timedTrack = _track;
      unawaited(_player.play());
      return;
    }
    if (_index < _queue.length - 1) {
      _index++;
      return _load(play: true);
    }
    if (_repeat == QueueRepeat.all && _queue.isNotEmpty) {
      _index = 0;
      return _load(play: true);
    }
    // End of queue: try to extend it, otherwise stop at the end.
    await _loadMoreIfNeeded();
    if (_index < _queue.length - 1) {
      _index++;
      return _load(play: true);
    }
    await _player.pause();
    await _player.seek(Duration.zero);
    _emit();
  }

  /// Books the time listened to the current track into history / stats.
  Future<void> _commitListen() async {
    final t = _timedTrack;
    final listened = _listened.elapsed;
    _timedTrack = null;
    _listened
      ..stop()
      ..reset();
    if (t == null) return;
    final threshold = Duration(seconds: ((setting('historyDuration') as num?) ?? 30).round());
    if (listened < threshold) return;
    if (!_bool('pauseListenHistory')) {
      try {
        await db.recordPlay(t, listened);
      } catch (_) {}
      final url = _trackingUrl;
      if (url != null && youtube.tube.signedIn) unawaited(youtube.tube.registerPlayback(url));
    }
    onListened?.call(t, listened);
  }

  // ── audio_service transport (also used by the engine) ────────────────────

  @override
  Future<void> play() async {
    if (_track == null) return;
    if (_error != null || _player.audioSource == null) return _load(play: true, position: _player.position);
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  Future<void> playPause() => _player.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _emit();
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    await _commitListen();
    if (_index < _queue.length - 1) {
      _index++;
    } else if (_repeat == QueueRepeat.all) {
      _index = 0;
    } else {
      await _loadMoreIfNeeded();
      if (_index >= _queue.length - 1) return;
      _index++;
    }
    await _load(play: true);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    // Like every music app: restart the song unless we're in its first seconds.
    if (_player.position > const Duration(seconds: 3) || _index == 0) {
      await _player.seek(Duration.zero);
      return;
    }
    await _commitListen();
    _index--;
    await _load(play: true);
  }

  @override
  Future<void> skipToQueueItem(int index) => skipToIndex(index);

  @override
  Future<void> stop() async {
    await _commitListen();
    await _player.stop();
    _queue = [];
    _index = 0;
    _unshuffled = null;
    _error = null;
    _format = null;
    mediaItem.add(null);
    onTrackChanged?.call(null);
    _emit();
    _persistSoon();
    await super.stop();
  }

  @override
  Future<void> setShuffleMode(svc.AudioServiceShuffleMode shuffleMode) =>
      setShuffle(shuffleMode != svc.AudioServiceShuffleMode.none);

  @override
  Future<void> setRepeatMode(svc.AudioServiceRepeatMode repeatMode) => setRepeat(switch (repeatMode) {
    svc.AudioServiceRepeatMode.one => QueueRepeat.one,
    svc.AudioServiceRepeatMode.none => QueueRepeat.off,
    _ => QueueRepeat.all,
  });

  @override
  Future<void> onTaskRemoved() async {
    if (_bool('stopMusicOnTaskClear') || !_player.playing) {
      await _commitListen();
      await _persistNow();
      await _player.stop();
      await super.stop();
    }
  }

  /// Flushes history and the queue (app going to the background / closing).
  Future<void> flush() async {
    await _persistNow();
  }

  // ── State publishing ─────────────────────────────────────────────────────

  void _publishMediaItem(Track t) {
    mediaItem.add(
      svc.MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artistLine,
        album: t.albumName,
        duration: t.duration == Duration.zero ? null : t.duration,
        artUri: t.thumbnailUrl == null ? null : Uri.tryParse(t.thumbnailUrl!),
      ),
    );
  }

  void _emit({bool positionOnly = false}) {
    final t = _track;
    final state = _player.processingState;
    final buffering = _loading || state == ProcessingState.loading || state == ProcessingState.buffering;
    final duration = _player.duration ?? t?.duration ?? Duration.zero;
    if (_sleepEnd != null && !_sleepAtEndOfTrack && DateTime.now().isAfter(_sleepEnd!)) _sleepEnd = null;
    _current = PlaybackSnapshot(
      track: t,
      isPlaying: _player.playing && state != ProcessingState.completed && _error == null,
      isBuffering: buffering && _error == null,
      position: t == null ? Duration.zero : _player.position,
      buffered: _player.bufferedPosition,
      duration: duration,
      queue: _queue,
      queueIndex: _index,
      shuffle: _shuffle,
      repeat: _repeat,
      volume: _userVolume,
      format: _format,
      sleepTimerEnd: _sleepEnd,
      error: _error,
    );
    if (!_snapshots.isClosed) _snapshots.add(_current);
    if (positionOnly) return;

    final item = mediaItem.value;
    if (item != null && item.duration == null && duration > Duration.zero) {
      mediaItem.add(item.copyWith(duration: duration));
    }
    playbackState.add(
      svc.PlaybackState(
        controls: [
          svc.MediaControl.skipToPrevious,
          if (_current.isPlaying) svc.MediaControl.pause else svc.MediaControl.play,
          svc.MediaControl.skipToNext,
        ],
        systemActions: const {svc.MediaAction.seek, svc.MediaAction.seekForward, svc.MediaAction.seekBackward},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: t == null
            ? svc.AudioProcessingState.idle
            : _error != null
            ? svc.AudioProcessingState.error
            : buffering
            ? svc.AudioProcessingState.buffering
            : svc.AudioProcessingState.ready,
        playing: _current.isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _index,
        shuffleMode: _shuffle ? svc.AudioServiceShuffleMode.all : svc.AudioServiceShuffleMode.none,
        repeatMode: switch (_repeat) {
          QueueRepeat.off => svc.AudioServiceRepeatMode.none,
          QueueRepeat.all => svc.AudioServiceRepeatMode.all,
          QueueRepeat.one => svc.AudioServiceRepeatMode.one,
        },
        errorMessage: _error,
      ),
    );
  }

  // ── Queue persistence ────────────────────────────────────────────────────

  Timer? _persistTimer;
  void _persistSoon() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 2), _persistNow);
  }

  Future<void> _persistNow() async {
    _persistTimer?.cancel();
    if (!_bool('persistentQueue', true)) return;
    try {
      if (_queue.isEmpty) {
        if (queueFile.existsSync()) await queueFile.delete();
        return;
      }
      final remember = _bool('rememberShuffleAndRepeat', true);
      await queueFile.writeAsString(
        jsonEncode({
          'queue': [for (final t in _queue) Codec.track(t)],
          'index': _index,
          'positionMs': _player.position.inMilliseconds,
          'shuffle': remember && _shuffle,
          'repeat': remember ? _repeat.index : 0,
          'continuation': _radioContinuation,
          'playlistId': _radioPlaylistId,
          'params': _radioParams,
        }),
        flush: true,
      );
    } catch (_) {}
  }

  Future<void> _restoreQueue() async {
    try {
      if (!queueFile.existsSync()) return;
      final m = jsonDecode(await queueFile.readAsString()) as Map<String, Object?>;
      final queue = [for (final t in (m['queue'] as List? ?? const [])) Codec.trackFrom(t as Map)];
      if (queue.isEmpty) return;
      _queue = await db.decorate(queue);
      _index = ((m['index'] as num?)?.toInt() ?? 0).clamp(0, queue.length - 1);
      _shuffle = m['shuffle'] as bool? ?? false;
      _repeat = QueueRepeat.values[((m['repeat'] as num?)?.toInt() ?? 0).clamp(0, 2)];
      _radioContinuation = m['continuation'] as String?;
      _radioPlaylistId = m['playlistId'] as String?;
      _radioParams = m['params'] as String?;
      _restoredPosition = Duration(milliseconds: (m['positionMs'] as num?)?.toInt() ?? 0);
      _publishMediaItem(_queue[_index]);
      _emit();
    } catch (_) {}
  }

  /// Position to resume from on the first play after a restore; nothing is
  /// loaded (no network) until the user presses play.
  Duration? _restoredPosition;

  /// Start playback of a restored queue.
  Future<void> resumeRestored() async {
    final pos = _restoredPosition;
    _restoredPosition = null;
    await _load(play: true, position: pos);
  }

  bool get hasRestoredQueue => _restoredPosition != null && _player.audioSource == null;

  Future<void> dispose() async {
    _sleepTimer?.cancel();
    await _commitListen();
    await _persistNow();
    await _player.dispose();
    _reader.close();
    await _snapshots.close();
  }
}
