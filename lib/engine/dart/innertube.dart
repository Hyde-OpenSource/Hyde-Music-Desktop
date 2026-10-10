import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// An InnerTube client identity (port of innertube/models/YouTubeClient.kt).
class YtClient {
  const YtClient({
    required this.name,
    required this.version,
    required this.id,
    required this.userAgent,
    this.osName,
    this.osVersion,
    this.deviceMake,
    this.deviceModel,
    this.androidSdkVersion,
    this.loginSupported = false,
    this.embedded = false,
  });

  final String name;
  final String version;

  /// Numeric client id sent as X-YouTube-Client-Name.
  final String id;
  final String userAgent;
  final String? osName;
  final String? osVersion;
  final String? deviceMake;
  final String? deviceModel;
  final String? androidSdkVersion;
  final bool loginSupported;
  final bool embedded;

  static const _webUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';

  static const webRemix = YtClient(
    name: 'WEB_REMIX',
    version: '1.20260213.01.00',
    id: '67',
    userAgent: _webUa,
    loginSupported: true,
  );

  static const web = YtClient(name: 'WEB', version: '2.20260213.00.00', id: '1', userAgent: _webUa);

  /// Non-adaptive bitrate, no PoToken, direct (unciphered) URLs.
  static const androidVr143 = YtClient(
    name: 'ANDROID_VR',
    version: '1.43.32',
    id: '28',
    userAgent:
        'com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)',
    osName: 'Android',
    osVersion: '12',
    deviceMake: 'Oculus',
    deviceModel: 'Quest 3',
    androidSdkVersion: '32',
  );

  static const androidVr161 = YtClient(
    name: 'ANDROID_VR',
    version: '1.61.48',
    id: '28',
    userAgent:
        'com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)',
    osName: 'Android',
    osVersion: '12',
    deviceMake: 'Oculus',
    deviceModel: 'Quest 3',
    androidSdkVersion: '32',
  );

  static const ipados = YtClient(
    name: 'IOS',
    version: '21.03.3',
    id: '5',
    userAgent: 'com.google.ios.youtube/21.03.3 (iPad7,6; U; CPU iPadOS 17_7_10 like Mac OS X; en-US)',
    osName: 'iPadOS',
    osVersion: '17.7.10.21H450',
    deviceMake: 'Apple',
    deviceModel: 'iPad7,6',
  );

  static const ios = YtClient(
    name: 'IOS',
    version: '21.03.1',
    id: '5',
    userAgent: 'com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)',
    osVersion: '18.2.22C152',
    deviceMake: 'Apple',
    deviceModel: 'iPhone16,2',
  );

  /// ANDROID without androidSdkVersion: no PoToken needed, plain URLs that
  /// accept ranged requests (yt-dlp's android_sdkless).
  static const androidSdkless = YtClient(
    name: 'ANDROID',
    version: '20.10.38',
    id: '3',
    userAgent: 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
    osName: 'Android',
    osVersion: '11',
  );

  /// Serves complete files without a PoToken (needs a www.youtube.com visitor id).
  static const visionOs = YtClient(
    name: 'VISIONOS',
    version: '0.1',
    id: '101',
    userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
    osName: 'visionOS',
    osVersion: '1.3.21O771',
    deviceMake: 'Apple',
    deviceModel: 'RealityDevice14,1',
  );

  static const tvEmbedded = YtClient(
    name: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
    version: '2.0',
    id: '85',
    userAgent:
        'Mozilla/5.0 (PlayStation; PlayStation 4/12.02) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15',
    loginSupported: true,
    embedded: true,
  );

  Map<String, Object?> context({required String hl, required String gl, String? visitorData}) => {
    'client': {
      'clientName': name,
      'clientVersion': version,
      'osName': ?osName,
      'osVersion': ?osVersion,
      'deviceMake': ?deviceMake,
      'deviceModel': ?deviceModel,
      'androidSdkVersion': ?androidSdkVersion,
      'hl': hl,
      'gl': gl,
      'visitorData': ?visitorData,
    },
  };
}

class InnerTubeException implements Exception {
  InnerTubeException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => 'InnerTube: $message${status == null ? '' : ' ($status)'}';
}

/// Raw InnerTube transport: posts JSON bodies to music.youtube.com/youtubei/v1
/// with the right client headers and (optionally) the signed-in cookie.
class InnerTube {
  InnerTube({http.Client? client}) : _http = client ?? http.Client() {
    final parts = Platform.localeName.split(RegExp('[_-]'));
    hl = parts.first.isEmpty ? 'en' : parts.first;
    gl = parts.length > 1 && parts[1].length == 2 ? parts[1].toUpperCase() : 'US';
  }

  final http.Client _http;
  static const origin = 'https://music.youtube.com';
  static const _api = '$origin/youtubei/v1/';

  late String hl;
  late String gl;
  String? visitorData;
  String? dataSyncId;
  String? _cookie;
  Map<String, String> _cookieMap = const {};

  /// When true, browse/search requests are personalised with the account.
  bool useLoginForBrowse = true;

  String? get cookie => _cookie;
  set cookie(String? value) {
    _cookie = (value == null || value.trim().isEmpty) ? null : value;
    _cookieMap = {
      for (final part in (_cookie ?? '').split(';'))
        if (part.contains('=')) part.split('=').first.trim(): part.substring(part.indexOf('=') + 1).trim(),
    };
  }

  bool get signedIn => _cookieMap.containsKey('SAPISID');

  Map<String, String> headers(YtClient client, {bool login = false}) {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'X-Goog-Api-Format-Version': '1',
      'X-YouTube-Client-Name': client.id,
      'X-YouTube-Client-Version': client.version,
      'X-Origin': origin,
      'Origin': origin,
      'Referer': '$origin/',
      'User-Agent': client.userAgent,
      'X-Goog-Visitor-Id': ?visitorData,
    };
    if (login && client.loginSupported && _cookie != null) {
      h['Cookie'] = _cookie!;
      final sapisid = _cookieMap['SAPISID'];
      if (sapisid != null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final hash = sha1.convert(utf8.encode('$now $sapisid $origin')).toString();
        h['Authorization'] = 'SAPISIDHASH ${now}_$hash';
      }
    }
    return h;
  }

  Future<Map<String, Object?>> post(
    String endpoint,
    Map<String, Object?> body, {
    YtClient client = YtClient.webRemix,
    bool login = false,
    Map<String, String> query = const {},
  }) async {
    final useLogin = login && signedIn;
    final payload = {
      'context': {
        ...client.context(hl: hl, gl: gl, visitorData: visitorData),
        if (useLogin && dataSyncId != null) 'user': {'onBehalfOfUser': dataSyncId},
        if (client.embedded && body['videoId'] != null)
          'thirdParty': {'embedUrl': 'https://www.youtube.com/watch?v=${body['videoId']}'},
      },
      ...body,
    };
    final uri = Uri.parse(
      endpoint.startsWith('http') ? endpoint : '$_api$endpoint',
    ).replace(queryParameters: {'prettyPrint': 'false', ...query});
    final res = await _http
        .post(uri, headers: headers(client, login: useLogin), body: jsonEncode(payload))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode >= 400) {
      throw InnerTubeException('$endpoint failed', res.statusCode);
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
    final vd = (json['responseContext'] as Map?)?['visitorData'] as String?;
    if (visitorData == null && vd != null && vd.isNotEmpty) visitorData = vd;
    return json;
  }

  Future<Map<String, Object?>> browse({
    String? browseId,
    String? params,
    String? continuation,
    bool login = false,
  }) => post(
    'browse',
    {'browseId': ?browseId, 'params': ?params},
    login: login || useLoginForBrowse,
    query: continuation == null ? const {} : {'continuation': continuation, 'ctoken': continuation, 'type': 'next'},
  );

  Future<Map<String, Object?>> search({String? query, String? params, String? continuation}) => post(
    'search',
    {'query': ?query, 'params': ?params},
    login: useLoginForBrowse,
    query: continuation == null ? const {} : {'continuation': continuation, 'ctoken': continuation, 'type': 'next'},
  );

  Future<Map<String, Object?>> next({
    String? videoId,
    String? playlistId,
    String? playlistSetVideoId,
    int? index,
    String? params,
    String? continuation,
  }) => post('next', {
    'videoId': ?videoId,
    'playlistId': ?playlistId,
    'playlistSetVideoId': ?playlistSetVideoId,
    'index': ?index,
    'params': ?params,
    'continuation': ?continuation,
    'enablePersistentPlaylistPanel': true,
    'isAudioOnly': true,
    'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
  }, login: true);

  /// Player response. App clients (Android / iOS / VR) are asked the way the
  /// real apps ask — www.youtube.com, no web Origin/Referer — otherwise
  /// YouTube answers with a bot check.
  Future<Map<String, Object?>> player(String videoId, YtClient client, {String? playlistId}) async {
    final visitorData = client.loginSupported ? this.visitorData : await playerVisitorData();
    final body = {
      'videoId': videoId,
      'playlistId': ?playlistId,
      'contentCheckOk': true,
      'racyCheckOk': true,
    };
    if (client.loginSupported) return post('player', body, client: client, login: true);
    final res = await _http
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': client.userAgent,
            'X-YouTube-Client-Name': client.id,
            'X-YouTube-Client-Version': client.version,
            'X-Goog-Visitor-Id': ?visitorData,
          },
          body: jsonEncode({
            'context': client.context(hl: hl, gl: gl, visitorData: visitorData),
            ...body,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode >= 400) throw InnerTubeException('player failed', res.statusCode);
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
  }

  String? _playerVisitor;
  DateTime _playerVisitorAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Visitor id issued by www.youtube.com. App clients answer "Sign in to
  /// confirm you're not a bot" without one (the music.youtube.com id doesn't count).
  Future<String?> playerVisitorData({bool refresh = false}) async {
    if (!refresh && _playerVisitor != null && DateTime.now().difference(_playerVisitorAt) < const Duration(hours: 6)) {
      return _playerVisitor;
    }
    try {
      final res = await _http
          .get(Uri.parse('https://www.youtube.com/sw.js_data'), headers: {'User-Agent': YtClient.web.userAgent})
          .timeout(const Duration(seconds: 10));
      final m = RegExp(r'"(Cg[ts][A-Za-z0-9_%-]{20,})"').firstMatch(res.body);
      if (m != null) {
        _playerVisitor = m.group(1);
        _playerVisitorAt = DateTime.now();
      }
    } catch (_) {}
    return _playerVisitor;
  }

  Future<Map<String, Object?>> suggestions(String input) =>
      post('music/get_search_suggestions', {'input': input});

  Future<Map<String, Object?>> queue(List<String> videoIds) =>
      post('music/get_queue', {'videoIds': videoIds});

  Future<Map<String, Object?>> accountMenu() => post('account/account_menu', {}, login: true);

  Future<void> like(String videoId, bool like) =>
      post(like ? 'like/like' : 'like/removelike', {
        'target': {'videoId': videoId},
      }, login: true);

  Future<void> likePlaylist(String playlistId, bool like) =>
      post(like ? 'like/like' : 'like/removelike', {
        'target': {'playlistId': playlistId},
      }, login: true);

  Future<void> subscribe(String channelId, bool subscribe) => post(
    subscribe ? 'subscription/subscribe' : 'subscription/unsubscribe',
    {
      'channelIds': [channelId],
    },
    login: true,
  );

  Future<Map<String, Object?>> editPlaylist(String playlistId, List<Map<String, Object?>> actions) => post(
    'browse/edit_playlist',
    {'playlistId': playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId, 'actions': actions},
    login: true,
  );

  Future<Map<String, Object?>> createPlaylist(String title, {List<String>? videoIds}) => post(
    'playlist/create',
    {'title': title, 'privacyStatus': 'PRIVATE', 'videoIds': ?videoIds},
    login: true,
  );

  Future<void> deletePlaylist(String playlistId) => post('playlist/delete', {'playlistId': playlistId}, login: true);

  Future<void> feedback(List<String> tokens) => post('feedback', {'feedbackTokens': tokens}, login: true);

  /// Registers a play in the user's YouTube history (playbackTracking URL).
  Future<void> registerPlayback(String url) async {
    try {
      final cpn = _cpn();
      final uri = Uri.parse(url);
      await _http.get(
        uri.replace(queryParameters: {...uri.queryParameters, 'ver': '2', 'c': 'WEB_REMIX', 'cpn': cpn}),
        headers: headers(YtClient.webRemix, login: true),
      );
    } catch (_) {}
  }

  static String _cpn() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final r = DateTime.now().microsecondsSinceEpoch;
    return List.generate(16, (i) => chars[(r >> (i * 3) ^ (i * 7919)) % 64]).join();
  }

  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) => _http.get(uri, headers: headers);

  void close() => _http.close();
}
