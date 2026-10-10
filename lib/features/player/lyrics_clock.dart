import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Playback position for lyrics between the engine's 250 ms reports.
///
/// Nothing here runs on its own: the lyrics view asks for a one-shot timer
/// at the next line's start (exact line changes, no polling), and only the
/// parts that move every frame — the active line's word fill and the
/// interlude dots — listen to [frames], a vsync ticker that runs only while
/// they are on screen and music plays. Notifies listeners on jumps (seek,
/// play / pause), so the view can re-sync.
class LyricsClock extends ChangeNotifier {
  LyricsClock() {
    frames = LyricsFrames._(this);
  }

  final _watch = Stopwatch()..start();
  Duration _base = Duration.zero;
  Duration _baseAt = Duration.zero;
  bool _playing = false;

  /// Per-frame position for the animated parts (see class docs).
  late final LyricsFrames frames;

  bool get playing => _playing;

  /// Extrapolated position. Never runs more than a second past the last
  /// report, so a stalled stream doesn't race ahead.
  Duration get now {
    if (!_playing) return _base;
    var ahead = _watch.elapsed - _baseAt;
    if (ahead > const Duration(seconds: 1)) ahead = const Duration(seconds: 1);
    return _base + ahead;
  }

  /// Applies an engine report.
  void report(Duration position, bool playing) {
    final shown = now;
    final error = position - shown;
    final jump = playing != _playing || error.abs() > const Duration(milliseconds: 350);
    if (!jump && error.isNegative && error > const Duration(milliseconds: -120)) {
      // A hair behind (report latency): keep moving forward, don't twitch back.
      _base = shown;
    } else if (!jump && error.isNegative) {
      // Clearly behind: close half the gap, so fills don't snap visibly.
      _base = shown + error ~/ 2;
    } else {
      _base = position;
    }
    _baseAt = _watch.elapsed;
    _playing = playing;
    frames._update();
    if (jump) notifyListeners();
  }

  @override
  void dispose() {
    frames._dispose();
    super.dispose();
  }
}

/// Vsync-aligned position stream; ticks only while someone listens and
/// music plays.
class LyricsFrames extends ChangeNotifier implements ValueListenable<Duration> {
  LyricsFrames._(this._clock);

  final LyricsClock _clock;
  Ticker? _ticker;

  @override
  Duration get value => _clock.now;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _update();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _update();
  }

  void _update() {
    final want = hasListeners && _clock.playing;
    final ticker = _ticker ??= Ticker((_) => notifyListeners(), debugLabel: 'lyrics');
    if (want && !ticker.isActive) ticker.start();
    if (!want && ticker.isActive) ticker.stop();
    // Paused: one update so the animated parts show the paused position.
    if (!_clock.playing && hasListeners) notifyListeners();
  }

  void _dispose() {
    _ticker?.dispose();
    super.dispose();
  }
}
