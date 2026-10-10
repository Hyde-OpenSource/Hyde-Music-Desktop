import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

/// Last.fm scrobbling (port of the `lastfm` module).
///
/// The API key and secret are build-time values, exactly as in the native
/// app (`LASTFM_API_KEY` / `LASTFM_SECRET` in local.properties):
/// `flutter build apk --dart-define-from-file=secrets.json`.
class LastFm {
  LastFm({http.Client? client}) : _http = client ?? http.Client();

  static const apiKey = String.fromEnvironment('LASTFM_API_KEY');
  static const secret = String.fromEnvironment('LASTFM_SECRET');
  static bool get configured => apiKey.isNotEmpty && secret.isNotEmpty;

  final http.Client _http;
  String? sessionKey;

  static String signature(Map<String, String> params, String secret) {
    final keys = params.keys.toList()..sort();
    final base = '${keys.map((k) => '$k${params[k]}').join()}$secret';
    return md5.convert(utf8.encode(base)).toString();
  }

  Future<Map<String, Object?>> _call(String method, Map<String, String> extra, {bool session = true}) async {
    if (!configured) throw StateError('Last.fm isn’t set up in this build');
    final params = {
      'method': method,
      'api_key': apiKey,
      if (session && sessionKey != null) 'sk': sessionKey!,
      ...extra,
    };
    final res = await _http
        .post(
          Uri.parse('https://ws.audioscrobbler.com/2.0/'),
          headers: {'User-Agent': 'Hyde Music'},
          body: {...params, 'api_sig': signature(params, secret), 'format': 'json'},
        )
        .timeout(const Duration(seconds: 15));
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
    if (json['error'] != null) throw StateError(json['message'] as String? ?? 'Last.fm error ${json['error']}');
    return json;
  }

  /// Signs in and returns the account name; [sessionKey] is set.
  Future<String> login(String username, String password) async {
    final json = await _call('auth.getMobileSession', {'username': username, 'password': password}, session: false);
    final s = json['session'] as Map;
    sessionKey = s['key'] as String;
    return s['name'] as String? ?? username;
  }

  Map<String, String> _trackParams(Track t) => {
    'artist': t.artists.isEmpty ? 'Unknown' : t.artists.first.name,
    'track': t.title,
    if (t.albumName != null) 'album': t.albumName!,
    if (t.duration > Duration.zero) 'duration': '${t.duration.inSeconds}',
  };

  Future<void> nowPlaying(Track t) => _call('track.updateNowPlaying', _trackParams(t));

  Future<void> scrobble(Track t, DateTime startedAt) =>
      _call('track.scrobble', {..._trackParams(t), 'timestamp': '${startedAt.millisecondsSinceEpoch ~/ 1000}'});

  Future<void> love(Track t, bool love) => _call(love ? 'track.love' : 'track.unlove', {
    'artist': t.artists.isEmpty ? 'Unknown' : t.artists.first.name,
    'track': t.title,
  });

  void close() => _http.close();
}
