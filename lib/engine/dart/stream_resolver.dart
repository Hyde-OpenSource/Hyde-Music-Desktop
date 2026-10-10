import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yte;

import '../models.dart';
import 'innertube.dart';
import 'yt_parser.dart';

/// A playable audio stream for one video.
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    required this.headers,
    required this.format,
    required this.expiresAt,
    this.mimeType = 'audio/webm',
    this.itag = 0,
    this.contentLength,
    this.durationMs,
    this.playbackTrackingUrl,
  });

  final Uri url;

  /// Headers the CDN expects (User-Agent of the client that produced the URL).
  final Map<String, String> headers;
  final AudioFormat format;
  final DateTime expiresAt;

  /// Container type for the player ("audio/webm" or "audio/mp4").
  final String mimeType;
  final int itag;
  final int? contentLength;
  final int? durationMs;

  /// videostatsPlaybackUrl — registers the play in YouTube history when signed in.
  final String? playbackTrackingUrl;

  bool get expired => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));
}

class StreamUnavailable implements Exception {
  StreamUnavailable(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

enum AudioQuality { auto, high, low }

/// Finds a working audio stream URL (port of utils/YTPlayerUtils.kt).
///
/// Clients that return plain (non-ciphered) URLs are tried in order and each
/// URL is validated against the tail of the file; youtube_explode_dart is the
/// last resort. See test/live/player_probe_test.dart for how each behaves.
class StreamResolver {
  StreamResolver(this.tube, {http.Client? client}) : _http = client ?? http.Client();

  final InnerTube tube;
  final http.Client _http;
  final _cache = <String, ResolvedStream>{};
  final _inflight = <String, Future<ResolvedStream>>{};
  AudioQuality quality = AudioQuality.auto;

  /// Diagnostics sink (which client answered what); null in production.
  void Function(String message)? log;

  static const _clients = [
    YtClient.visionOs,
    YtClient.androidVr161,
    YtClient.androidVr143,
    YtClient.androidSdkless,
    YtClient.ipados,
    YtClient.ios,
  ];

  /// Cached (non-expired) stream, or a fresh resolve. Concurrent calls for the
  /// same id share one request.
  Future<ResolvedStream> resolve(String videoId) {
    final cached = _cache[videoId];
    if (cached != null && !cached.expired) return Future.value(cached);
    // Block body on purpose: returning the removed future from whenComplete
    // would make it wait on itself.
    return _inflight[videoId] ??= _resolve(videoId).whenComplete(() {
      _inflight.remove(videoId);
    });
  }

  void invalidate(String videoId) => _cache.remove(videoId);

  Future<ResolvedStream> _resolve(String videoId) async {
    String? lastReason;
    log?.call('$videoId visitor=${(await tube.playerVisitorData())?.length}');
    for (final client in _clients) {
      try {
        var res = await _player(videoId, client);
        if (Yt.dig(res, ['playabilityStatus', 'status']) == 'LOGIN_REQUIRED') {
          // Bot check: the visitor id went stale — get a new one and ask once more.
          await tube.playerVisitorData(refresh: true);
          res = await _player(videoId, client);
        }
        final status = Yt.dig(res, ['playabilityStatus', 'status']) as String?;
        log?.call('$videoId ${client.name} ${client.version}: $status');
        if (status != 'OK') {
          lastReason = Yt.dig(res, ['playabilityStatus', 'reason']) as String? ?? status;
          continue;
        }
        final stream = _pick(res, client);
        if (stream == null) continue;
        final ok = await _validate(stream);
        log?.call('$videoId ${client.name}: ${stream.format.label} valid=$ok');
        if (ok) {
          _cache[videoId] = stream;
          return stream;
        }
      } catch (e) {
        log?.call('$videoId ${client.name}: $e');
        lastReason = '$e';
      }
    }
    try {
      final stream = await _explode(videoId);
      if (await _validate(stream)) {
        _cache[videoId] = stream;
        return stream;
      }
      lastReason ??= 'Stream blocked by YouTube';
    } catch (e) {
      lastReason ??= '$e';
    }
    throw StreamUnavailable(lastReason);
  }

  Future<Map<String, Object?>> _player(String videoId, YtClient client) async {
    try {
      return await tube.player(videoId, client);
    } on InnerTubeException catch (e) {
      if (e.status != 400) rethrow;
      // 400 = missing/invalid visitor id for this client.
      await tube.playerVisitorData(refresh: true);
      return tube.player(videoId, client);
    }
  }

  ResolvedStream? _pick(Map<String, Object?> res, YtClient client) {
    final formats = [
      for (final f in Yt.list(res, ['streamingData', 'adaptiveFormats']))
        if (f is Map && (f['mimeType'] as String? ?? '').startsWith('audio/') && f['url'] is String)
          f.cast<String, Object?>(),
    ];
    // Dolby (ec-3 / ac-3) and DRC / dubbed variants: not decodable everywhere, or not the original mix.
    bool plain(Map<String, Object?> f) {
      final mime = f['mimeType'] as String;
      if (mime.contains('ec-3') || mime.contains('ac-3')) return false;
      if (f['isDrc'] == true) return false;
      final track = f['audioTrack'];
      return track is! Map || track['audioIsDefault'] != false;
    }

    if (formats.any(plain)) formats.retainWhere(plain);
    if (formats.isEmpty) return null;
    int br(Map<String, Object?> f) => (f['bitrate'] as num?)?.toInt() ?? 0;
    int itag(Map<String, Object?> f) => (f['itag'] as num?)?.toInt() ?? 0;
    Map<String, Object?> best;
    switch (quality) {
      case AudioQuality.low:
        formats.sort((a, b) => br(a).compareTo(br(b)));
        best = formats.first;
      case AudioQuality.high:
      case AudioQuality.auto:
        // Prefer Opus 160 (251), then AAC 256 (141), AAC 128 (140), else highest bitrate.
        best =
            formats.where((f) => itag(f) == 251).firstOrNull ??
            formats.where((f) => itag(f) == 141).firstOrNull ??
            formats.where((f) => itag(f) == 140).firstOrNull ??
            (formats..sort((a, b) => br(b).compareTo(br(a)))).first;
    }
    final mime = best['mimeType'] as String;
    final codec = RegExp(r'codecs="([^".]+)').firstMatch(mime)?.group(1) ?? mime.split(';').first.split('/').last;
    final expires = int.tryParse('${Yt.dig(res, ['streamingData', 'expiresInSeconds']) ?? ''}') ?? 6 * 3600;
    return ResolvedStream(
      url: Uri.parse(best['url'] as String),
      headers: {'User-Agent': client.userAgent},
      format: AudioFormat(
        codec: codec == 'mp4a' ? 'AAC' : codec.toUpperCase(),
        bitrateKbps: br(best) ~/ 1000,
        sampleRateHz: int.tryParse('${best['audioSampleRate'] ?? ''}'),
        loudnessDb: (Yt.dig(res, ['playerConfig', 'audioConfig', 'loudnessDb']) as num?)?.toDouble(),
      ),
      expiresAt: DateTime.now().add(Duration(seconds: expires)),
      mimeType: mime.split(';').first.trim(),
      itag: itag(best),
      contentLength: int.tryParse('${best['contentLength'] ?? ''}'),
      durationMs: int.tryParse('${best['approxDurationMs'] ?? ''}'),
      playbackTrackingUrl: Yt.dig(res, ['playbackTracking', 'videostatsPlaybackUrl', 'baseUrl']) as String?,
    );
  }

  /// PoToken-gated URLs serve the first ~30–60 s and then answer 403, so the
  /// probe reads the END of the file, never byte 0.
  Future<bool> _validate(ResolvedStream s) async {
    try {
      final len = s.contentLength ?? 0;
      if (len < 4) return false;
      final at = len - 2;
      final req = http.Request('GET', s.url)
        ..headers.addAll({...s.headers, 'Range': 'bytes=$at-${at + 1}'});
      final res = await _http.send(req).timeout(const Duration(seconds: 8));
      await res.stream.drain<void>().timeout(const Duration(seconds: 8));
      return res.statusCode == 200 || res.statusCode == 206;
    } catch (_) {
      return false;
    }
  }

  Future<ResolvedStream> _explode(String videoId) async {
    final yt = yte.YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 30));
      final audio = manifest.audioOnly.where((a) => !a.audioCodec.contains('ec-3') && !a.audioCodec.contains('ac-3')).toList()..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      if (audio.isEmpty) throw StreamUnavailable('No audio stream');
      final pick = quality == AudioQuality.low ? audio.last : audio.first;
      return ResolvedStream(
        url: pick.url,
        headers: const {},
        format: AudioFormat(
          codec: pick.audioCodec.split('.').first == 'mp4a' ? 'AAC' : pick.audioCodec.split('.').first.toUpperCase(),
          bitrateKbps: pick.bitrate.kiloBitsPerSecond.round(),
        ),
        expiresAt: DateTime.now().add(const Duration(hours: 5)),
        mimeType: pick.codec.mimeType,
        itag: pick.tag,
        contentLength: pick.size.totalBytes,
      );
    } finally {
      yt.close();
    }
  }
}
