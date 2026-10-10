import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';

import '../models.dart';
import 'listen_together_proto.dart';

/// What Listen Together needs from the player.
abstract interface class ListenTogetherPlayer {
  PlaybackSnapshot get current;
  Stream<PlaybackSnapshot> get snapshots;

  /// Loads [track] as the only queue item, paused, ready to start in sync.
  Future<void> prepareTrack(Track track);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> addToQueue(List<Track> tracks);
  Future<void> playNext(List<Track> tracks);
}

/// Listen Together (port of listentogether/*): a room on the sync server
/// where the host's playback — track, play / pause, seeks — is mirrored on
/// every guest. Protobuf `Envelope{type, payload}` frames over a WebSocket
/// (see [LtProto]).
class ListenTogether {
  ListenTogether({required this.player, required this.setting, required this.emit, required this.saveBlocked});

  final ListenTogetherPlayer player;
  final Object? Function(String key) setting;

  /// Publishes the UI state (`topic: listenTogether`).
  final void Function(Map<String, Object?> state) emit;
  final Future<void> Function(List<String> blocked) saveBlocked;

  static const defaultServer = 'wss://hydemusicandroidcode.onrender.com/ws';

  IOWebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSub;
  StreamSubscription<PlaybackSnapshot>? _playerSub;
  Timer? _ping;
  Timer? _reconnect;
  Timer? _heartbeat;
  int _attempts = 0;

  String _connection = 'DISCONNECTED';
  String _role = 'NONE';
  String? _userId;
  String? _username;
  String? _sessionToken;
  Map<String, Object?>? _room;
  final _pending = <Map<String, Object?>>[];
  final _suggestions = <Map<String, Object?>>[];
  final _chat = <Map<String, Object?>>[];
  final _logs = <String>[];
  late final Set<String> _blocked = {...?(setting('listenTogetherBlockedUsernames') as List?)?.cast<String>()};

  /// Server clock − local clock (ms), from ping / pong.
  int _clockOffset = 0;

  /// Queued until the socket is open ("create" / "join").
  void Function()? _onOpen;

  // Local playback, to detect what the host changed.
  String? _lastTrackId;
  bool _lastPlaying = false;
  int _lastPositionMs = 0;
  DateTime _lastSnapshotAt = DateTime.now();

  /// Remote changes being applied — don't echo them back to the room.
  DateTime _muteUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String? _bufferingTrackId;

  bool get inRoom => _room != null;
  bool get _isHost => _role == 'HOST';
  bool get _canControl => _isHost || (_room?['allow_participant_control'] == true);
  String get _serverUrl {
    final custom = (setting('listenTogetherServerUrl') as String?)?.trim() ?? '';
    return custom.isEmpty ? defaultServer : custom;
  }

  void _log(String message) {
    final t = DateTime.now();
    _logs.add('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')} $message');
    if (_logs.length > 300) _logs.removeRange(0, _logs.length - 300);
  }

  void publish() => _publish();

  void _publish() {
    final room = _room;
    emit({
      'topic': 'listenTogether',
      'connection': _connection,
      'role': _role,
      'me': _userId,
      'room': room == null
          ? null
          : {
              'code': room['room_code'],
              'hostId': room['host_id'],
              'allowControl': room['allow_participant_control'] == true,
              'track': switch (room['current_track']) {
                final Map t => {'title': t['title'], 'artist': t['artist'], 'thumbnailUrl': t['thumbnail']},
                _ => null,
              },
              'users': [
                for (final u in (room['users'] as List? ?? const []).cast<Map>())
                  {'id': u['user_id'], 'name': u['username'], 'host': u['is_host'] == true, 'online': u['is_connected'] != false},
              ],
            },
      'pending': [
        for (final p in _pending) {'id': p['user_id'], 'name': p['username']},
      ],
      'chat': [
        for (final c in _chat.length > 100 ? _chat.sublist(_chat.length - 100) : _chat)
          {'user': c['username'], 'text': c['message'], 'at': c['timestamp']},
      ],
      'blocked': _blocked.toList(),
      'logs': _logs.length > 200 ? _logs.sublist(_logs.length - 200) : List.of(_logs),
      'suggestions': [
        for (final s in _suggestions)
          {
            'id': s['suggestion_id'],
            'by': s['from_username'],
            'title': (s['track_info'] as Map?)?['title'],
            'artist': (s['track_info'] as Map?)?['artist'],
          },
      ],
    });
  }

  // ── Connection ───────────────────────────────────────────────────────────

  void _connect() {
    if (_socket != null) return;
    _reconnect?.cancel();
    _connection = _attempts == 0 ? 'CONNECTING' : 'RECONNECTING';
    _log('Connecting to $_serverUrl');
    _publish();
    try {
      final socket = IOWebSocketChannel.connect(Uri.parse(_serverUrl), connectTimeout: const Duration(seconds: 20));
      _socket = socket;
      socket.ready.then(
        (_) {
          if (_socket != socket) return;
          _connection = 'CONNECTED';
          _attempts = 0;
          _log('Connected');
          _publish();
          _ping?.cancel();
          _ping = Timer.periodic(const Duration(seconds: 25), (_) => _sendPing());
          _sendPing();
          if (_sessionToken != null && _onOpen == null) {
            _send('reconnect', {'session_token': _sessionToken});
          }
          final pending = _onOpen;
          _onOpen = null;
          pending?.call();
        },
        onError: (Object e) => _onSocketClosed('$e'),
      );
      _socketSub = socket.stream.listen(
        (data) {
          try {
            if (data is! List<int>) return; // the server only speaks binary protobuf
            final (type, payload) = LtProto.decode(data is Uint8List ? data : Uint8List.fromList(data));
            _onMessage(type, payload);
          } catch (e) {
            _log('Bad message: $e');
          }
        },
        onDone: () => _onSocketClosed('closed'),
        onError: (Object e) => _onSocketClosed('$e'),
        cancelOnError: true,
      );
    } catch (e) {
      _onSocketClosed('$e');
    }
  }

  void _onSocketClosed(String why) {
    if (_socket == null && _connection == 'DISCONNECTED') return;
    _ping?.cancel();
    _socketSub?.cancel();
    _socket = null;
    _log('Connection lost ($why)');
    // Stay in the room and retry while there is a session to resume or an action waiting.
    if (_sessionToken != null || _onOpen != null) {
      if (_attempts >= 12) {
        _connection = 'ERROR';
        _onOpen = null;
        _publish();
        return;
      }
      _connection = 'RECONNECTING';
      final delay = Duration(milliseconds: math.min(30000, 1000 * (1 << math.min(_attempts, 5))));
      _attempts++;
      _reconnect?.cancel();
      _reconnect = Timer(delay, _connect);
    } else {
      _connection = 'DISCONNECTED';
    }
    _publish();
  }

  void _send(String type, [Map<String, Object?>? payload]) {
    try {
      _socket?.sink.add(LtProto.encode(type, payload));
    } catch (e) {
      _log('Send failed: $e');
    }
  }

  void _sendPing() => _send('ping', {'client_time': DateTime.now().millisecondsSinceEpoch, 'sequence': 0});

  void _whenOpen(void Function() action) {
    if (_socket != null && _connection == 'CONNECTED') {
      action();
    } else {
      _onOpen = action;
      _connect();
    }
  }

  // ── Public actions (feature calls `lt.*`) ────────────────────────────────

  String _name(String? username) {
    final n = (username ?? '').trim();
    return n.isEmpty ? ((setting('listenTogetherUsername') as String?)?.trim().isNotEmpty ?? false ? setting('listenTogetherUsername') as String : 'Listener') : n;
  }

  void createRoom(String? username) {
    _username = _name(username);
    _whenOpen(() => _send('create_room', {'username': _username}));
  }

  void joinRoom(String code, String? username) {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) throw const FormatException('Enter a room code');
    _username = _name(username);
    _whenOpen(() => _send('join_room', {'room_code': c, 'username': _username}));
  }

  void leaveRoom() {
    _send('leave_room');
    _leaveLocally();
    _disconnect();
  }

  void _leaveLocally() {
    _sessionToken = null;
    _room = null;
    _role = 'NONE';
    _pending.clear();
    _suggestions.clear();
    _chat.clear();
    _bufferingTrackId = null;
    _heartbeat?.cancel();
    _playerSub?.cancel();
    _playerSub = null;
  }

  void _disconnect() {
    _reconnect?.cancel();
    _ping?.cancel();
    _onOpen = null;
    _socketSub?.cancel();
    _socket?.sink.close();
    _socket = null;
    _connection = 'DISCONNECTED';
    _publish();
  }

  void approveJoin(String userId) {
    _send('approve_join', {'user_id': userId});
    _pending.removeWhere((p) => p['user_id'] == userId);
    _publish();
  }

  void rejectJoin(String userId, [String? reason]) {
    _send('reject_join', {'user_id': userId, 'reason': ?reason});
    _pending.removeWhere((p) => p['user_id'] == userId);
    _publish();
  }

  void kick(String userId) => _send('kick_user', {'user_id': userId});
  void transferHost(String userId) => _send('transfer_host', {'new_host_id': userId});
  void setAllowControl(bool allow) => _send('update_room_settings', {'allow_participant_control': allow});

  /// The sync server has no chat message; say so instead of dropping text silently.
  void chat(String message) {
    if (message.trim().isNotEmpty) throw const FormatException('Chat isn’t supported by this server');
  }

  void block(String username) {
    _blocked.add(username);
    unawaited(saveBlocked(_blocked.toList()));
    final user = (_room?['users'] as List? ?? const []).cast<Map>().where((u) => u['username'] == username).firstOrNull;
    if (user != null && _isHost) kick(user['user_id'] as String);
    _publish();
  }

  void unblock(String username) {
    _blocked.remove(username);
    unawaited(saveBlocked(_blocked.toList()));
    _publish();
  }

  void suggest(Track track) => _send('suggest_track', {'track_info': _trackInfo(track)});

  void approveSuggestion(String id) {
    final s = _suggestions.where((s) => s['suggestion_id'] == id).firstOrNull;
    _send('approve_suggestion', {'suggestion_id': id});
    _suggestions.removeWhere((s) => s['suggestion_id'] == id);
    // The host queues the suggested song; the queue change reaches guests as queue_add.
    final info = s?['track_info'] as Map?;
    if (info != null) {
      final track = _trackFrom(info);
      unawaited(player.addToQueue([track]));
      _send('playback_action', {'action': 'queue_add', 'track_info': info});
    }
    _publish();
  }

  void rejectSuggestion(String id) {
    _send('reject_suggestion', {'suggestion_id': id});
    _suggestions.removeWhere((s) => s['suggestion_id'] == id);
    _publish();
  }

  void forceReconnect() {
    _socketSub?.cancel();
    _socket?.sink.close();
    _socket = null;
    _attempts = 0;
    _connect();
  }

  void clearLogs() {
    _logs.clear();
    _publish();
  }

  // ── Track ⇄ wire ─────────────────────────────────────────────────────────

  static Map<String, Object?> _trackInfo(Track t) => {
    'id': t.id,
    'title': t.title,
    'artist': t.artistLine,
    'album': t.albumName,
    'duration': t.duration.inMilliseconds,
    'thumbnail': t.thumbnailUrl,
  };

  static Track _trackFrom(Map m) => Track(
    id: m['id'] as String,
    title: m['title'] as String? ?? '',
    artists: [
      for (final name in (m['artist'] as String? ?? '').split(', '))
        if (name.isNotEmpty) ArtistRef(id: null, name: name),
    ],
    albumName: m['album'] as String?,
    thumbnailUrl: m['thumbnail'] as String?,
    duration: Duration(milliseconds: (m['duration'] as num?)?.toInt() ?? 0),
  );

  // ── Incoming ─────────────────────────────────────────────────────────────

  List<Map<String, Object?>> get _users =>
      [for (final u in (_room?['users'] as List? ?? const [])) (u as Map).cast<String, Object?>()];

  void _setUsers(List<Map<String, Object?>> users) => _room = {...?_room, 'users': users};

  void _onMessage(String type, Map<String, Object?> p) {
    if (type != 'pong') _log('← $type');
    switch (type) {
      case 'room_created':
        _userId = p['user_id'] as String?;
        _role = 'HOST';
        _sessionToken = p['session_token'] as String?;
        _room = {
          'room_code': p['room_code'],
          'host_id': _userId,
          'users': [
            {'user_id': _userId, 'username': _username ?? '', 'is_host': true, 'is_connected': true},
          ],
          'is_playing': false,
          'position': 0,
        };
        _startSync();
        // Share what is already playing.
        final t = player.current.track;
        if (t != null && !t.isLocal) _sendTrackChange(t);
      case 'join_request':
        if (_blocked.contains(p['username'])) {
          _send('reject_join', {'user_id': p['user_id'], 'reason': 'You are blocked'});
          return;
        }
        if (_isHost && setting('listenTogetherAutoApproval') == true) {
          _send('approve_join', {'user_id': p['user_id']});
        } else {
          _pending.add(p);
        }
      case 'join_approved':
        _userId = p['user_id'] as String?;
        _role = 'GUEST';
        _sessionToken = p['session_token'] as String?;
        _room = (p['state'] as Map?)?.cast<String, Object?>();
        _startSync();
        _applyState(_room);
      case 'join_rejected':
        _log('Join rejected: ${p['reason']}');
        _leaveLocally();
        _disconnect();
        return;
      case 'user_joined':
        _setUsers([..._users, {'user_id': p['user_id'], 'username': p['username'], 'is_host': false, 'is_connected': true}]);
        _pending.removeWhere((r) => r['user_id'] == p['user_id']);
      case 'user_left':
        _setUsers(_users.where((u) => u['user_id'] != p['user_id']).toList());
      case 'user_reconnected' || 'user_disconnected':
        _setUsers([
          for (final u in _users)
            u['user_id'] == p['user_id'] ? {...u, 'is_connected': type == 'user_reconnected'} : u,
        ]);
      case 'host_changed':
        final host = p['new_host_id'];
        _room = {...?_room, 'host_id': host};
        _setUsers([for (final u in _users) {...u, 'is_host': u['user_id'] == host}]);
        _role = host == _userId ? 'HOST' : 'GUEST';
        _startSync();
      case 'kicked':
        _log('Removed from the room: ${p['reason']}');
        _leaveLocally();
        _disconnect();
        return;
      case 'room_settings_changed':
        _room = {...?_room, 'allow_participant_control': p['allow_participant_control'] == true};
      case 'reconnected':
        _userId = p['user_id'] as String?;
        _role = p['is_host'] == true ? 'HOST' : 'GUEST';
        _room = (p['state'] as Map?)?.cast<String, Object?>();
        _startSync();
        if (!_isHost) _applyState(_room);
      case 'sync_playback':
        _onPlaybackAction(p);
      case 'sync_state':
        if (!_isHost) _applyState(p);
      case 'buffer_wait':
        _bufferingTrackId = p['track_id'] as String?;
      case 'buffer_complete':
        _bufferingTrackId = null;
        // Everyone has the track loaded: the host starts it for the room.
        if (_isHost && p['track_id'] == player.current.track?.id) {
          _mute();
          unawaited(player.play());
          _send('playback_action', {'action': 'play', 'position': player.current.position.inMilliseconds});
        }
      case 'suggestion_received':
        if (_isHost && !_blocked.contains(p['from_username'])) _suggestions.add(p);
      case 'chat':
        _chat.add(p);
      case 'pong':
        final now = DateTime.now().millisecondsSinceEpoch;
        final clientTime = (p['client_time'] as num?)?.toInt();
        final recv = (p['server_receive_time'] as num?)?.toInt();
        final sent = (p['server_send_time'] as num?)?.toInt();
        if (clientTime != null && recv != null && sent != null) {
          _clockOffset = ((recv - clientTime) + (sent - now)) ~/ 2;
        }
        return;
      case 'error':
        _log('Server: ${p['code']} ${p['message']}');
        if (p['code'] == 'session_not_found') {
          final code = _room?['room_code'] as String?;
          final wasGuest = !_isHost;
          _leaveLocally();
          // A guest can simply ask to join again; a host's room is gone.
          if (wasGuest && code != null && _username != null) {
            _send('join_room', {'room_code': code, 'username': _username});
          } else {
            _disconnect();
            return;
          }
        }
    }
    _publish();
  }

  void _mute([Duration d = const Duration(milliseconds: 1500)]) => _muteUntil = DateTime.now().add(d);

  /// Applies a host action on this guest (or a participant's action on the host).
  void _onPlaybackAction(Map<String, Object?> a) {
    final action = a['action'] as String?;
    final position = (a['position'] as num?)?.toInt();
    switch (action) {
      case 'play' || 'pause' || 'seek':
        _room = {
          ...?_room,
          if (action != 'seek') 'is_playing': action == 'play',
          'position': position ?? _room?['position'],
        };
      case 'change_track':
        _room = {...?_room, 'current_track': a['track_info'], 'is_playing': false, 'position': 0};
    }
    if (_isHost && !(_room?['allow_participant_control'] == true)) return;

    switch (action) {
      case 'play':
        final serverTime = (a['server_time'] as num?)?.toInt();
        var target = position ?? 0;
        if (serverTime != null) {
          // How long ago (on our clock) the host was at [position].
          final elapsed = DateTime.now().millisecondsSinceEpoch - (serverTime - _clockOffset);
          if (elapsed > 0 && elapsed < 15000) target += elapsed;
        }
        final diff = (player.current.position.inMilliseconds - target).abs();
        _mute();
        if (!player.current.isPlaying || diff > 1500) {
          if (diff > 250) unawaited(player.seek(Duration(milliseconds: target)));
          unawaited(player.play());
        }
      case 'pause':
        _mute();
        unawaited(player.pause());
        if (position != null && (player.current.position.inMilliseconds - position).abs() > 500) {
          unawaited(player.seek(Duration(milliseconds: position)));
        }
      case 'seek':
        if (position != null) {
          _mute();
          unawaited(player.seek(Duration(milliseconds: position)));
        }
      case 'change_track':
        final info = a['track_info'] as Map?;
        if (info != null) unawaited(_loadTrack(_trackFrom(info)));
      case 'queue_add':
        final info = a['track_info'] as Map?;
        if (info != null) {
          final t = _trackFrom(info);
          unawaited(a['insert_next'] == true ? player.playNext([t]) : player.addToQueue([t]));
        }
    }
  }

  Future<void> _loadTrack(Track track) async {
    _mute(const Duration(seconds: 6));
    _lastTrackId = track.id;
    try {
      await player.prepareTrack(track);
      _send('buffer_ready', {'track_id': track.id});
    } catch (e) {
      _log('Couldn’t load ${track.title}: $e');
    }
  }

  /// Full state after joining / reconnecting / `request_sync`.
  void _applyState(Map<String, Object?>? state) {
    final info = state?['current_track'] as Map?;
    if (info == null) return;
    final playing = state?['is_playing'] == true;
    var position = (state?['position'] as num?)?.toInt() ?? 0;
    final lastUpdate = (state?['last_update'] as num?)?.toInt();
    if (playing && lastUpdate != null) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - (lastUpdate - _clockOffset);
      if (elapsed > 0 && elapsed < 6 * 3600 * 1000) position += elapsed;
    }
    unawaited(() async {
      final track = _trackFrom(info);
      if (player.current.track?.id != track.id) await _loadTrack(track);
      _mute(const Duration(seconds: 3));
      await player.seek(Duration(milliseconds: position));
      if (playing) {
        await player.play();
      } else {
        await player.pause();
      }
    }());
  }

  // ── Outgoing: mirror local playback into the room ────────────────────────

  void _startSync() {
    final s = player.current;
    _lastTrackId = s.track?.id;
    _lastPlaying = s.isPlaying;
    _lastPositionMs = s.position.inMilliseconds;
    _lastSnapshotAt = DateTime.now();
    _playerSub ??= player.snapshots.listen(_onLocalPlayback);
    _heartbeat?.cancel();
    if (_isHost) {
      // Periodic position beacon keeps long-running guests from drifting.
      _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        final cur = player.current;
        if (_isHost && cur.isPlaying && _bufferingTrackId == null) {
          _send('playback_action', {'action': 'play', 'position': cur.position.inMilliseconds});
        }
      });
    }
  }

  void _sendTrackChange(Track t) {
    _bufferingTrackId = t.id;
    _send('playback_action', {'action': 'change_track', 'track_id': t.id, 'track_info': _trackInfo(t)});
    // The host itself is "ready" as soon as its player has the track.
    _send('buffer_ready', {'track_id': t.id});
  }

  void _onLocalPlayback(PlaybackSnapshot s) {
    if (_room == null) return;
    final now = DateTime.now();
    final id = s.track?.id;
    final positionMs = s.position.inMilliseconds;
    final expected = _lastPositionMs + (_lastPlaying ? now.difference(_lastSnapshotAt).inMilliseconds : 0);
    final jumped = id == _lastTrackId && (positionMs - expected).abs() > 2500;
    final trackChanged = id != _lastTrackId;
    final playChanged = s.isPlaying != _lastPlaying && !s.isBuffering;

    final muted = now.isBefore(_muteUntil);
    if (!muted && _canControl && s.track != null) {
      if (trackChanged) {
        if (!s.track!.isLocal) _sendTrackChange(s.track!);
      } else if (playChanged && _bufferingTrackId == null) {
        _send('playback_action', {'action': s.isPlaying ? 'play' : 'pause', 'position': positionMs});
      } else if (jumped) {
        _send('playback_action', {'action': 'seek', 'position': positionMs});
      }
    }
    _lastTrackId = id;
    if (!s.isBuffering) _lastPlaying = s.isPlaying;
    _lastPositionMs = positionMs;
    _lastSnapshotAt = now;
  }

  Future<void> dispose() async {
    _leaveLocally();
    _disconnect();
  }
}
