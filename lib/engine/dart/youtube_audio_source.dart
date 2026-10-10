// StreamAudioSource is the supported way to feed just_audio custom byte ranges.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import 'stream_resolver.dart';

/// Reads a YouTube audio stream in explicit byte ranges.
///
/// The CDN answers 403 (or throttles hard) for open-ended requests, so the
/// file is always fetched as a sequence of bounded `Range` requests. An
/// expired/blocked URL is re-resolved once and the read continues where it
/// stopped.
class RangedReader {
  RangedReader(this.resolver, {http.Client? client}) : _http = client ?? http.Client();

  final StreamResolver resolver;
  final http.Client _http;

  /// 512 KB ≈ 25 s of 160 kbps audio: small enough to start instantly,
  /// large enough to keep request overhead negligible.
  static const chunk = 512 * 1024;

  /// Bytes [start, end) of [videoId]'s audio.
  Stream<List<int>> read(String videoId, int start, int end) async* {
    var at = start;
    var retries = 0;
    while (at < end) {
      final stream = await resolver.resolve(videoId);
      final last = min(at + chunk, end) - 1;
      try {
        final req = http.Request('GET', stream.url)..headers.addAll({...stream.headers, 'Range': 'bytes=$at-$last'});
        final res = await _http.send(req).timeout(const Duration(seconds: 20));
        if (res.statusCode != 206 && res.statusCode != 200) {
          await res.stream.drain<void>().catchError((_) {});
          throw StreamUnavailable('HTTP ${res.statusCode}');
        }
        await for (final data in res.stream.timeout(const Duration(seconds: 30))) {
          at += data.length;
          yield data;
        }
        retries = 0;
      } catch (e) {
        if (++retries > 3) rethrow;
        // Expired or revoked URL → get a new one; transient network error → brief pause.
        if (e is StreamUnavailable) resolver.invalidate(videoId);
        await Future<void>.delayed(Duration(milliseconds: 400 * retries));
      }
    }
  }

  void close() => _http.close();
}

/// just_audio source for one YouTube track. The stream URL is resolved lazily
/// on the first byte request, so queue items cost nothing until they play.
class YoutubeAudioSource extends StreamAudioSource {
  YoutubeAudioSource(this.videoId, this.resolver, this.reader, {super.tag});

  final String videoId;
  final StreamResolver resolver;
  final RangedReader reader;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final stream = await resolver.resolve(videoId);
    final length = stream.contentLength;
    if (length == null) throw StreamUnavailable('Unknown stream length');
    final from = start ?? 0;
    final to = min(end ?? length, length);
    return StreamAudioResponse(
      sourceLength: length,
      contentLength: to - from,
      offset: from,
      stream: reader.read(videoId, from, to),
      contentType: stream.mimeType,
    );
  }
}
