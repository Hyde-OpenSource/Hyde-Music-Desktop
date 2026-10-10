import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nsd/nsd.dart' as nsd;

import '../models.dart';
import 'listen_together.dart' show ListenTogetherPlayer;

/// Nearby Sync (port of sync/*): one phone hosts, phones on the same Wi-Fi
/// play in step with it. The host runs a WebSocket server on port 8085
/// (`/sync`), advertised over mDNS as `_hydesync._tcp`; messages are JSON
/// with a `type` field — the same wire format as the native app, so old and
/// new versions can join each other.
class NearbySync {
  NearbySync({required this.player, required this.emit, required this.deviceName});

  final ListenTogetherPlayer player;
  final void Function(Map<String, Object?> state) emit;
  final String deviceName;

  static const port = 8085;
  static const _serviceType = '_hydesync._tcp';
  static const _serviceName = 'HydeSync';

  /// Guests re-seek only when they drift further than this.
  static const _driftTolerance = Duration(milliseconds: 350);

  String _state = 'idle'; // idle | hosting | discovering | connected
  String? _hostName;
  Map<String, Object?>? _song;

  // Host side.
  HttpServer? _server;
  final _clients = <WebSocket>{};
  nsd.Registration? _registration;
  StreamSubscription<PlaybackSnapshot>? _playerSub;
  Timer? _beacon;
  String? _lastTrackId;
  bool _lastPlaying = false;
  int _lastPositionMs = 0;
  DateTime _lastAt = DateTime.now();

  // Guest side.
  nsd.Discovery? _discovery;
  final _found = <String, nsd.Service>{};
  WebSocket? _socket;
  String? _loadingId;

  void publish() => _publish();

  void _publish() => emit({
    'topic': 'nearby',
    'state': _state,
    'clients': _clients.length,
    'host': _hostName,
    'devices': _found.keys.toList(),
    'song': _song,
  });

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> _trackFields(Track t) => {
    'song_id': t.id,
    'title': t.title,
    'artist': t.artistLine,
    'thumbnail_url': t.thumbnailUrl,
    'duration': t.duration.inSeconds,
  };

  // ── Host ─────────────────────────────────────────────────────────────────

  Future<void> host() async {
    await stop();
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    } on SocketException {
      throw const FormatException('Couldn’t start hosting — is another session running?');
    }
    _server = server;
    server.listen((request) async {
      if (request.uri.path != '/sync' || !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = const Duration(seconds: 15);
      _clients.add(socket);
      _publish();
      socket.add(jsonEncode({'type': 'HOST_INFO', 'host_name': deviceName}));
      // Late joiners get the full state at once.
      final s = player.current;
      if (s.track != null && !s.track!.isLocal) {
        socket.add(
          jsonEncode({
            'type': 'STATE',
            ..._trackFields(s.track!),
            'position_ms': s.position.inMilliseconds,
            'is_playing': s.isPlaying,
            'timestamp': _now,
          }),
        );
      }
      socket.listen(
        (_) {},
        onDone: () {
          _clients.remove(socket);
          _publish();
        },
        onError: (_) {
          _clients.remove(socket);
          _publish();
        },
        cancelOnError: true,
      );
    });
    try {
      _registration = await nsd.register(const nsd.Service(name: _serviceName, type: _serviceType, port: port));
    } catch (_) {
      await server.close(force: true);
      _server = null;
      throw const FormatException('Couldn’t advertise on this network');
    }

    final cur = player.current;
    _lastTrackId = cur.track?.id;
    _lastPlaying = cur.isPlaying;
    _lastPositionMs = cur.position.inMilliseconds;
    _lastAt = DateTime.now();
    _playerSub = player.snapshots.listen(_onHostPlayback);
    // Position beacon so guests can correct drift.
    _beacon = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      final s = player.current;
      if (s.track == null || s.track!.isLocal) return;
      _broadcast({
        'type': 'SYNC',
        ..._trackFields(s.track!),
        'position_ms': s.position.inMilliseconds,
        'is_playing': s.isPlaying,
        'timestamp': _now,
      });
    });
    _state = 'hosting';
    _hostName = deviceName;
    _publish();
  }

  void _broadcast(Map<String, Object?> message) {
    final text = jsonEncode(message);
    for (final c in _clients.toList()) {
      try {
        c.add(text);
      } catch (_) {
        _clients.remove(c);
      }
    }
  }

  void _onHostPlayback(PlaybackSnapshot s) {
    final t = s.track;
    final now = DateTime.now();
    final positionMs = s.position.inMilliseconds;
    if (t != null && !t.isLocal && !s.isBuffering) {
      final expected = _lastPositionMs + (_lastPlaying ? now.difference(_lastAt).inMilliseconds : 0);
      if (t.id != _lastTrackId || (s.isPlaying && !_lastPlaying)) {
        _broadcast({'type': 'PLAY', ..._trackFields(t), 'position_ms': positionMs, 'timestamp': _now});
      } else if (!s.isPlaying && _lastPlaying) {
        _broadcast({'type': 'PAUSE', 'position_ms': positionMs});
      } else if ((positionMs - expected).abs() > 2000) {
        _broadcast({'type': 'SEEK', 'position_ms': positionMs});
      }
      _lastPlaying = s.isPlaying;
    }
    _lastTrackId = t?.id;
    _lastPositionMs = positionMs;
    _lastAt = now;
  }

  // ── Guest ────────────────────────────────────────────────────────────────

  Future<void> discover() async {
    await stop();
    _found.clear();
    try {
      final discovery = await nsd.startDiscovery(_serviceType, ipLookupType: nsd.IpLookupType.v4);
      _discovery = discovery;
      discovery.addServiceListener((service, status) {
        final name = service.name ?? '';
        if (name.isEmpty) return;
        if (status == nsd.ServiceStatus.found) {
          _found[name] = service;
        } else {
          _found.remove(name);
        }
        _publish();
      });
    } catch (_) {
      throw const FormatException('Couldn’t search this network — is Wi-Fi on?');
    }
    _state = 'discovering';
    _publish();
  }

  Future<void> stopDiscovery() async {
    final d = _discovery;
    _discovery = null;
    if (d != null) {
      try {
        await nsd.stopDiscovery(d);
      } catch (_) {}
    }
    if (_state == 'discovering') _state = 'idle';
    _publish();
  }

  Future<void> connect(String name) async {
    var service = _found[name];
    if (service == null) throw const FormatException('That device is no longer available');
    if (service.host == null && (service.addresses == null || service.addresses!.isEmpty)) {
      service = await nsd.resolve(service);
    }
    final host = service.addresses?.firstOrNull?.address ?? service.host;
    if (host == null) throw const FormatException('Couldn’t reach that device');
    final WebSocket socket;
    try {
      socket = await WebSocket.connect('ws://$host:${service.port ?? port}/sync').timeout(const Duration(seconds: 8));
    } catch (_) {
      throw const FormatException('Couldn’t connect — make sure both phones are on the same Wi-Fi');
    }
    await stopDiscovery();
    _socket = socket;
    _state = 'connected';
    _hostName = name;
    socket.add(jsonEncode({'type': 'HELLO', 'device_name': deviceName}));
    socket.listen(
      (data) {
        if (data is! String) return;
        try {
          _onHostMessage(jsonDecode(data) as Map<String, Object?>);
        } catch (_) {}
      },
      onDone: _onHostGone,
      onError: (_) => _onHostGone(),
      cancelOnError: true,
    );
    _publish();
  }

  void _onHostGone() {
    if (_socket == null) return;
    _socket = null;
    _state = 'idle';
    _song = null;
    _hostName = null;
    _publish();
  }

  Track _trackFrom(Map<String, Object?> m) => Track(
    id: m['song_id'] as String,
    title: m['title'] as String? ?? '',
    artists: [
      if ((m['artist'] as String?)?.isNotEmpty ?? false) ArtistRef(id: null, name: m['artist'] as String),
    ],
    thumbnailUrl: m['thumbnail_url'] as String?,
    duration: Duration(seconds: (m['duration'] as num?)?.toInt() ?? 0),
  );

  /// Where the host is now, compensating for the time the message travelled.
  static Duration _hostPosition(Map<String, Object?> m, {required bool playing}) {
    var ms = (m['position_ms'] as num?)?.toInt() ?? 0;
    final sent = (m['timestamp'] as num?)?.toInt();
    if (playing && sent != null) {
      final lag = _now - sent;
      if (lag > 0 && lag < 5000) ms += lag;
    }
    return Duration(milliseconds: ms);
  }

  Future<void> _follow(Map<String, Object?> m, {required bool playing}) async {
    final id = m['song_id'] as String?;
    if (id != null && player.current.track?.id != id) {
      if (_loadingId == id) return;
      _loadingId = id;
      try {
        final track = _trackFrom(m);
        _song = {'title': track.title, 'artist': track.artistLine, 'thumbnailUrl': track.thumbnailUrl};
        _publish();
        await player.prepareTrack(track);
      } catch (_) {
        return;
      } finally {
        _loadingId = null;
      }
    }
    final target = _hostPosition(m, playing: playing);
    if ((player.current.position - target).abs() > _driftTolerance) await player.seek(target);
    if (playing && !player.current.isPlaying) await player.play();
    if (!playing && player.current.isPlaying) await player.pause();
  }

  void _onHostMessage(Map<String, Object?> m) {
    switch (m['type']) {
      case 'HOST_INFO':
        _hostName = m['host_name'] as String? ?? _hostName;
        _publish();
      case 'PLAY':
        unawaited(_follow(m, playing: true));
      case 'STATE' || 'SYNC':
        unawaited(_follow(m, playing: m['is_playing'] == true));
      case 'PAUSE':
        unawaited(() async {
          await player.pause();
          final ms = (m['position_ms'] as num?)?.toInt();
          if (ms != null) await player.seek(Duration(milliseconds: ms));
        }());
      case 'SEEK':
        final ms = (m['position_ms'] as num?)?.toInt();
        if (ms != null) unawaited(player.seek(Duration(milliseconds: ms)));
    }
  }

  // ── Stop ─────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    _beacon?.cancel();
    _beacon = null;
    await _playerSub?.cancel();
    _playerSub = null;
    final registration = _registration;
    _registration = null;
    if (registration != null) {
      try {
        await nsd.unregister(registration);
      } catch (_) {}
    }
    for (final c in _clients.toList()) {
      unawaited(c.close().catchError((_) {}));
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
    final d = _discovery;
    _discovery = null;
    if (d != null) {
      try {
        await nsd.stopDiscovery(d);
      } catch (_) {}
    }
    _found.clear();
    _state = 'idle';
    _hostName = null;
    _song = null;
    _publish();
  }
}
