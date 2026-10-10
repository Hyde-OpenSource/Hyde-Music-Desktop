import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

import '../models.dart';

/// Discord rich presence over the gateway WebSocket (port of the `kizzy`
/// module + utils/DiscordRPC.kt): "Listening to <song>" with artwork,
/// progress and buttons.
class DiscordPresence {
  DiscordPresence(this.token, {http.Client? client}) : _http = client ?? http.Client();

  final String token;
  final http.Client _http;

  static const applicationId = '1411019391843172514';
  static const _gateway = 'wss://gateway.discord.gg/?v=9&encoding=json';
  static const _userAgent = 'Discord-Android/314013;RNA';

  IOWebSocketChannel? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  int _sequence = 0;
  String? _sessionId;
  String? _resumeUrl;
  bool _ready = false;
  bool _closed = false;
  Duration _backoff = const Duration(seconds: 2);

  /// Presence to (re)send once the gateway is ready.
  Map<String, Object?>? _presence;
  final _assetCache = <String, String?>{};

  /// Account name for Settings ("Signed in as …").
  static Future<({String username, String name})?> profile(String token, {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(
            Uri.parse('https://discord.com/api/v9/users/@me'),
            headers: {'Authorization': token, 'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      final username = m['username'] as String? ?? '';
      return (username: username, name: m['global_name'] as String? ?? username);
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  void _connect() {
    if (_closed || _socket != null) return;
    _reconnect?.cancel();
    try {
      final socket = IOWebSocketChannel.connect(
        Uri.parse(_resumeUrl ?? _gateway),
        headers: {'User-Agent': _userAgent, 'Accept-Language': 'en-US'},
        pingInterval: const Duration(seconds: 30),
      );
      _socket = socket;
      _sub = socket.stream.listen(
        (data) {
          if (data is String) _onMessage(jsonDecode(data) as Map<String, Object?>);
        },
        onDone: () => _onClosed(resumable: socket.closeCode == 4000),
        onError: (_) => _onClosed(resumable: false),
        cancelOnError: true,
      );
    } catch (_) {
      _onClosed(resumable: false);
    }
  }

  void _onClosed({required bool resumable}) {
    _heartbeat?.cancel();
    _sub?.cancel();
    _socket = null;
    _ready = false;
    if (_closed) return;
    _reconnect?.cancel();
    _reconnect = Timer(resumable ? const Duration(milliseconds: 200) : _backoff, _connect);
    if (!resumable) {
      final next = _backoff * 2;
      _backoff = next > const Duration(minutes: 1) ? const Duration(minutes: 1) : next;
    }
  }

  void _send(int op, Object? d) {
    try {
      _socket?.sink.add(jsonEncode({'op': op, 'd': d}));
    } catch (_) {}
  }

  void _onMessage(Map<String, Object?> p) {
    final s = p['s'];
    if (s is int) _sequence = s;
    switch (p['op']) {
      case 10: // HELLO
        final interval = ((p['d'] as Map)['heartbeat_interval'] as num).toInt();
        _heartbeat?.cancel();
        _heartbeat = Timer.periodic(Duration(milliseconds: interval), (_) => _send(1, _sequence == 0 ? null : _sequence));
        if (_sequence > 0 && _sessionId != null) {
          _send(6, {'seq': _sequence, 'session_id': _sessionId, 'token': token});
        } else {
          _identify();
        }
      case 1: // HEARTBEAT request
        _send(1, _sequence == 0 ? null : _sequence);
      case 7: // RECONNECT
        _socket?.sink.close(4000);
      case 9: // INVALID_SESSION
        _sessionId = null;
        _sequence = 0;
        Timer(const Duration(milliseconds: 150), _identify);
      case 0: // DISPATCH
        final d = p['d'];
        if (p['t'] == 'READY' && d is Map) {
          _sessionId = d['session_id'] as String?;
          final resume = d['resume_gateway_url'] as String?;
          if (resume != null) _resumeUrl = '$resume/?v=9&encoding=json';
          _markReady();
        } else if (p['t'] == 'RESUMED') {
          _markReady();
        }
    }
  }

  void _markReady() {
    _ready = true;
    _backoff = const Duration(seconds: 2);
    final pending = _presence;
    if (pending != null) _send(3, pending);
  }

  void _identify() => _send(2, {
    'capabilities': 16381,
    'compress': false,
    'largeThreshold': 100,
    'properties': {'os': 'Android', 'browser': 'Discord Android', 'device': 'Android'},
    'client_state': {
      'guild_versions': <String, String>{},
      'highest_last_message_id': '0',
      'read_state_version': 0,
      'user_guild_settings_version': -1,
      'user_settings_version': -1,
      'private_channels_version': '0',
      'api_code_version': 0,
    },
    'presence': {'status': 'online', 'since': 0, 'activities': <Object>[], 'afk': false},
    'shard': [0, 1],
    'token': token,
  });

  /// Discord only shows images it has proxied: URL → `mp:external/…`.
  Future<String?> _asset(String? url) async {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('mp:')) return url;
    if (_assetCache.containsKey(url)) return _assetCache[url];
    String? out;
    try {
      final res = await _http
          .post(
            Uri.parse('https://discord.com/api/v9/applications/$applicationId/external-assets'),
            headers: {'Authorization': token, 'User-Agent': _userAgent, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'urls': [url],
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final path = ((jsonDecode(res.body) as List).firstOrNull as Map?)?['external_asset_path'] as String?;
        if (path != null) out = 'mp:$path';
      }
    } catch (_) {}
    if (_assetCache.length > 200) _assetCache.clear();
    return _assetCache[url] = out;
  }

  static String resolve(String text, Track t) => text
      .replaceAll('{song_name}', t.title)
      .replaceAll('{artist_name}', t.artistLine)
      .replaceAll('{album_name}', t.albumName ?? '');

  /// Shows [track] as the current activity. [position] is where playback is now.
  Future<void> update(
    Track track, {
    required Duration position,
    required Duration duration,
    double speed = 1,
    bool useDetails = false,
    String status = 'online',
    String activityType = 'listening',
    String activityName = '',
    String button1Text = '',
    bool button1Visible = true,
    String button2Text = '',
    bool button2Visible = true,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - (position.inMilliseconds / speed).round();
    final remaining = ((duration - position).inMilliseconds / speed).round();
    final url = 'https://music.youtube.com/watch?v=${track.id}';
    final buttons = <(String, String)>[
      if (button1Visible && !track.isLocal) (resolve(button1Text.isEmpty ? 'Listen on YouTube Music' : button1Text, track), url),
      if (button2Visible) (resolve(button2Text.isEmpty ? 'Get Hyde Music' : button2Text, track), 'https://github.com/Tirth1107/Hyde-Music-Andorid'),
    ];
    final large = await _asset(track.thumbnailUrl);
    final title = speed == 1 ? track.title : '${track.title} [${speed.toStringAsFixed(2)}x]';
    _presence = {
      'status': status,
      'since': now,
      'afk': false,
      'activities': [
        {
          'name': activityName.isEmpty ? 'Hyde Music' : activityName,
          'type': switch (activityType) {
            'playing' => 0,
            'watching' => 3,
            'competing' => 5,
            _ => 2,
          },
          'details': title,
          'state': track.artistLine.isEmpty ? null : track.artistLine,
          if (!track.isLocal) 'details_url': url,
          'status_display_type': useDetails ? 2 : 1,
          'application_id': applicationId,
          'timestamps': {'start': start, if (duration > Duration.zero) 'end': now + remaining},
          'assets': {
            'large_image': large,
            'large_text': track.albumName,
            'small_image': null,
            'small_text': track.artists.firstOrNull?.name,
          },
          if (buttons.isNotEmpty) ...{
            'buttons': [for (final b in buttons) b.$1],
            'metadata': {
              'button_urls': [for (final b in buttons) b.$2],
            },
          },
        },
      ],
    };
    if (_ready) {
      _send(3, _presence);
    } else {
      _connect();
    }
  }

  /// Removes the activity (paused / stopped) but stays connected.
  void clear() {
    _presence = {'status': 'online', 'since': 0, 'afk': false, 'activities': <Object>[]};
    if (_ready) _send(3, _presence);
  }

  Future<void> close() async {
    _closed = true;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    await _sub?.cancel();
    await _socket?.sink.close();
    _socket = null;
    _http.close();
  }
}
