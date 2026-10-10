import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'database.dart';
import 'youtube.dart';

/// Lyrics lookup: cache → LRCLIB (synced) → YouTube Music (plain).
///
/// The cache is the native `lyrics` table (LRC text, or plain text, or the
/// [notFound] marker), so lyrics fetched by the old app are reused.
class LyricsService {
  LyricsService(this.db, this.youtube, {http.Client? client}) : _http = client ?? http.Client();

  final HydeDatabase db;
  final YouTube youtube;
  final http.Client _http;

  static const notFound = 'LYRICS_NOT_FOUND';
  static const _ua = 'Hyde Music (https://github.com/Tirth1107/Hyde-Music)';

  Future<Lyrics> get(Track t, {bool lrclib = true, bool refresh = false}) async {
    if (!refresh) {
      final cached = await db.lyrics(t.id);
      if (cached == notFound) return Lyrics.empty;
      if (cached != null && cached.trim().isNotEmpty) return parse(cached, provider: _providerOf(cached));
    }
    if (t.isLocal && t.artists.isEmpty) return Lyrics.empty;

    String? text;
    String? provider;
    if (lrclib) {
      try {
        text = await _lrclib(t);
        if (text != null) provider = 'LRCLIB';
      } catch (_) {}
    }
    if (text == null && !t.isLocal) {
      try {
        final next = await youtube.next(videoId: t.id);
        if (next.lyricsBrowseId != null) {
          final l = await youtube.lyrics(next.lyricsBrowseId!, params: next.lyricsParams);
          if (l != null) {
            text = l.text;
            provider = 'YouTube Music';
          }
        }
      } catch (_) {}
    }
    try {
      await db.ensureTrack(t);
      await db.setLyrics(t.id, text ?? notFound);
    } catch (_) {}
    return text == null ? Lyrics.empty : parse(text, provider: provider);
  }

  /// Saves user-edited or manually picked lyrics.
  Future<void> save(Track t, String text) async {
    await db.ensureTrack(t);
    await db.setLyrics(t.id, text.trim().isEmpty ? notFound : text);
  }

  static String? _providerOf(String text) => _timeTag.hasMatch(text) ? 'LRCLIB' : null;

  /// Candidates for the manual "search lyrics" sheet.
  Future<List<({String title, String artist, String? album, Duration duration, bool synced, String text})>> search(
    String title,
    String artist,
  ) async {
    final res = await _http
        .get(
          Uri.https('lrclib.net', '/api/search', {'track_name': title, if (artist.isNotEmpty) 'artist_name': artist}),
          headers: {'User-Agent': _ua},
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return const [];
    return [
      for (final m in (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map>())
        if ((m['syncedLyrics'] ?? m['plainLyrics']) != null)
          (
            title: m['trackName'] as String? ?? '',
            artist: m['artistName'] as String? ?? '',
            album: m['albumName'] as String?,
            duration: Duration(seconds: (m['duration'] as num?)?.round() ?? 0),
            synced: m['syncedLyrics'] != null,
            text: (m['syncedLyrics'] ?? m['plainLyrics']) as String,
          ),
    ];
  }

  Future<String?> _lrclib(Track t) async {
    final title = cleanTitle(t.title);
    final artist = t.artists.isEmpty ? '' : t.artists.first.name;
    final secs = t.duration.inSeconds;

    if (artist.isNotEmpty && secs > 0) {
      final res = await _http
          .get(
            Uri.https('lrclib.net', '/api/get', {
              'track_name': title,
              'artist_name': artist,
              if (t.albumName != null) 'album_name': t.albumName!,
              'duration': '$secs',
            }),
            headers: {'User-Agent': _ua},
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        final synced = m['syncedLyrics'] as String?;
        if (synced != null && synced.trim().isNotEmpty) return synced;
      }
    }

    final hits = await search(title, artist);
    if (hits.isEmpty) return null;
    // Closest duration wins; synced beats plain; reject clearly different cuts.
    int diff(Duration d) => secs == 0 ? 0 : (d.inSeconds - secs).abs();
    final ranked = hits.where((h) => diff(h.duration) <= 8).toList()
      ..sort((a, b) {
        if (a.synced != b.synced) return a.synced ? -1 : 1;
        return diff(a.duration).compareTo(diff(b.duration));
      });
    return ranked.isEmpty ? null : ranked.first.text;
  }

  /// "Song (feat. X) [Official Video]" → "Song".
  static String cleanTitle(String title) {
    var s = title
        .replaceAll(RegExp(r'\s*[\(\[][^\)\]]*(official|video|audio|lyric|visuali[sz]er|remaster|feat\.?|ft\.?|from\s)[^\)\]]*[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+(feat\.?|ft\.?)\s.*$', caseSensitive: false), '')
        .trim();
    if (s.isEmpty) s = title;
    return s;
  }

  static final _timeTag = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final _wordTag = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');
  static final _metaTag = RegExp(r'^\[(ar|ti|al|by|offset|length|re|ve|la|au|id|tool|#)[^\]]*\]\s*$', caseSensitive: false);

  static Duration _time(Match m) {
    final frac = m.group(3);
    final ms = frac == null ? 0 : (int.parse(frac.padRight(3, '0').substring(0, 3)));
    return Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!), milliseconds: ms);
  }

  /// Parses LRC (incl. multiple timestamps per line and enhanced word tags);
  /// text without timestamps becomes unsynced lines.
  static Lyrics parse(String raw, {String? provider}) {
    final text = raw.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty || text == notFound) return Lyrics.empty;
    if (!_timeTag.hasMatch(text)) {
      return Lyrics(
        synced: false,
        provider: provider,
        lines: [for (final l in text.split('\n')) LyricLine(start: Duration.zero, text: l.trim())],
      );
    }
    final lines = <LyricLine>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || _metaTag.hasMatch(line)) continue;
      final stamps = <Duration>[];
      var rest = line;
      while (true) {
        final m = _timeTag.matchAsPrefix(rest);
        if (m == null) break;
        stamps.add(_time(m));
        rest = rest.substring(m.end).trimLeft();
      }
      if (stamps.isEmpty) continue;

      // Enhanced LRC: <00:12.34>word <00:12.80>word
      final words = <LyricWord>[];
      final wordMatches = _wordTag.allMatches(rest).toList();
      var plain = rest;
      if (wordMatches.isNotEmpty) {
        for (var i = 0; i < wordMatches.length; i++) {
          final start = _time(wordMatches[i]);
          final end = i + 1 < wordMatches.length ? _time(wordMatches[i + 1]) : start + const Duration(milliseconds: 400);
          final piece = rest.substring(wordMatches[i].end, i + 1 < wordMatches.length ? wordMatches[i + 1].start : rest.length);
          if (piece.trim().isNotEmpty) words.add(LyricWord(piece, start, end));
        }
        plain = rest.replaceAll(_wordTag, '').replaceAll(RegExp(r'\s+'), ' ').trim();
      }
      for (final s in stamps) {
        lines.add(LyricLine(start: s, text: plain, words: words));
      }
    }
    lines.sort((a, b) => a.start.compareTo(b.start));
    return Lyrics(lines: lines, synced: true, provider: provider);
  }

  void close() => _http.close();
}
