import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

/// Protobuf wire codec for the Listen Together protocol
/// (app/src/main/proto/listentogether.proto), written by hand so the app
/// needs no generated code: messages are plain maps keyed by the proto field
/// names, described by the small schema table below.
abstract final class LtProto {
  // field number → (json name, type). Types: string, int (varint), bool,
  // float (fixed32), or a message name; a leading '*' marks `repeated`.
  static const _schemas = <String, Map<int, (String, String)>>{
    'TrackInfo': {
      1: ('id', 'string'),
      2: ('title', 'string'),
      3: ('artist', 'string'),
      4: ('album', 'string'),
      5: ('duration', 'int'),
      6: ('thumbnail', 'string'),
      7: ('suggested_by', 'string'),
    },
    'UserInfo': {1: ('user_id', 'string'), 2: ('username', 'string'), 3: ('is_host', 'bool'), 4: ('is_connected', 'bool')},
    'RoomState': {
      1: ('room_code', 'string'),
      2: ('host_id', 'string'),
      3: ('users', '*UserInfo'),
      4: ('current_track', 'TrackInfo'),
      5: ('is_playing', 'bool'),
      6: ('position', 'int'),
      7: ('last_update', 'int'),
      8: ('volume', 'float'),
      9: ('queue', '*TrackInfo'),
    },
    'UpdateRoomSettings': {1: ('allow_participant_control', 'bool')},
    'Username': {1: ('username', 'string')},
    'JoinRoom': {1: ('room_code', 'string'), 2: ('username', 'string')},
    'UserId': {1: ('user_id', 'string')},
    'UserIdReason': {1: ('user_id', 'string'), 2: ('reason', 'string')},
    'PlaybackAction': {
      1: ('action', 'string'),
      2: ('track_id', 'string'),
      3: ('position', 'int'),
      4: ('track_info', 'TrackInfo'),
      5: ('insert_next', 'bool'),
      6: ('queue', '*TrackInfo'),
      7: ('queue_title', 'string'),
      8: ('volume', 'float'),
      9: ('server_time', 'int'),
    },
    'TrackId': {1: ('track_id', 'string')},
    'TransferHost': {1: ('new_host_id', 'string')},
    'Ping': {1: ('client_time', 'int'), 2: ('sequence', 'int')},
    'Pong': {1: ('client_time', 'int'), 2: ('server_receive_time', 'int'), 3: ('server_send_time', 'int'), 4: ('sequence', 'int')},
    'SuggestTrack': {1: ('track_info', 'TrackInfo')},
    'SuggestionReceived': {
      1: ('suggestion_id', 'string'),
      2: ('from_user_id', 'string'),
      3: ('from_username', 'string'),
      4: ('track_info', 'TrackInfo'),
    },
    'SuggestionId': {1: ('suggestion_id', 'string')},
    'SuggestionIdReason': {1: ('suggestion_id', 'string'), 2: ('reason', 'string')},
    'SuggestionApproved': {1: ('suggestion_id', 'string'), 2: ('track_info', 'TrackInfo')},
    'RoomCreated': {1: ('room_code', 'string'), 2: ('user_id', 'string'), 3: ('session_token', 'string')},
    'UserIdName': {1: ('user_id', 'string'), 2: ('username', 'string')},
    'JoinApproved': {1: ('room_code', 'string'), 2: ('user_id', 'string'), 3: ('session_token', 'string'), 4: ('state', 'RoomState')},
    'Reason': {1: ('reason', 'string')},
    'BufferWait': {1: ('track_id', 'string'), 2: ('waiting_for', '*string')},
    'Error': {1: ('code', 'string'), 2: ('message', 'string')},
    'HostChanged': {1: ('new_host_id', 'string'), 2: ('new_host_name', 'string')},
    'SyncState': {
      1: ('current_track', 'TrackInfo'),
      2: ('is_playing', 'bool'),
      3: ('position', 'int'),
      4: ('last_update', 'int'),
      5: ('queue', '*TrackInfo'),
      6: ('volume', 'float'),
    },
    'SessionToken': {1: ('session_token', 'string')},
    'Reconnected': {1: ('room_code', 'string'), 2: ('user_id', 'string'), 3: ('state', 'RoomState'), 4: ('is_host', 'bool')},
  };

  /// Envelope `type` → payload message.
  static const _payloadOf = <String, String>{
    // client → server
    'create_room': 'Username',
    'join_room': 'JoinRoom',
    'approve_join': 'UserId',
    'reject_join': 'UserIdReason',
    'playback_action': 'PlaybackAction',
    'buffer_ready': 'TrackId',
    'kick_user': 'UserIdReason',
    'transfer_host': 'TransferHost',
    'ping': 'Ping',
    'reconnect': 'SessionToken',
    'suggest_track': 'SuggestTrack',
    'approve_suggestion': 'SuggestionId',
    'reject_suggestion': 'SuggestionIdReason',
    'update_room_settings': 'UpdateRoomSettings',
    // server → client
    'room_created': 'RoomCreated',
    'join_request': 'UserIdName',
    'join_approved': 'JoinApproved',
    'join_rejected': 'Reason',
    'user_joined': 'UserIdName',
    'user_left': 'UserIdName',
    'sync_playback': 'PlaybackAction',
    'buffer_wait': 'BufferWait',
    'buffer_complete': 'TrackId',
    'error': 'Error',
    'pong': 'Pong',
    'host_changed': 'HostChanged',
    'kicked': 'Reason',
    'sync_state': 'SyncState',
    'reconnected': 'Reconnected',
    'user_reconnected': 'UserIdName',
    'user_disconnected': 'UserIdName',
    'suggestion_received': 'SuggestionReceived',
    'suggestion_approved': 'SuggestionApproved',
    'suggestion_rejected': 'SuggestionIdReason',
    'room_settings_changed': 'UpdateRoomSettings',
  };

  static bool supports(String type) => _payloadOf.containsKey(type) || type == 'leave_room' || type == 'request_sync';

  // ── Encode ───────────────────────────────────────────────────────────────

  static void _varint(BytesBuilder b, int v) {
    var x = v;
    // Negative int64 → 10-byte two's complement.
    for (var i = 0; i < 10; i++) {
      final byte = x & 0x7f;
      x = x >>> 7;
      if (x == 0) {
        b.addByte(byte);
        return;
      }
      b.addByte(byte | 0x80);
    }
  }

  static void _bytes(BytesBuilder b, int field, List<int> data) {
    _varint(b, (field << 3) | 2);
    _varint(b, data.length);
    b.add(data);
  }

  static Uint8List _message(String name, Map<String, Object?> value) {
    final b = BytesBuilder();
    final schema = _schemas[name]!;
    for (final e in schema.entries) {
      final (key, type) = e.value;
      final v = value[key];
      if (v == null) continue;
      if (type.startsWith('*')) {
        final inner = type.substring(1);
        for (final item in v as List) {
          _bytes(b, e.key, inner == 'string' ? utf8.encode(item as String) : _message(inner, (item as Map).cast<String, Object?>()));
        }
        continue;
      }
      switch (type) {
        case 'string':
          if ((v as String).isNotEmpty) _bytes(b, e.key, utf8.encode(v));
        case 'int':
          final n = (v as num).toInt();
          if (n != 0) {
            _varint(b, e.key << 3);
            _varint(b, n);
          }
        case 'bool':
          if (v == true) {
            _varint(b, e.key << 3);
            b.addByte(1);
          }
        case 'float':
          _varint(b, (e.key << 3) | 5);
          b.add((ByteData(4)..setFloat32(0, (v as num).toDouble(), Endian.little)).buffer.asUint8List());
        default:
          _bytes(b, e.key, _message(type, (v as Map).cast<String, Object?>()));
      }
    }
    return b.takeBytes();
  }

  /// One wire frame: `Envelope{type, payload, compressed=false}`.
  static Uint8List encode(String type, [Map<String, Object?>? payload]) {
    final b = BytesBuilder();
    _bytes(b, 1, utf8.encode(type));
    final schema = _payloadOf[type];
    if (payload != null && schema != null) {
      final body = _message(schema, payload);
      if (body.isNotEmpty) _bytes(b, 2, body);
    }
    return b.takeBytes();
  }

  // ── Decode ───────────────────────────────────────────────────────────────

  static Map<String, Object?> _decode(String name, Uint8List data) {
    final schema = _schemas[name]!;
    final out = <String, Object?>{};
    final r = _Reader(data);
    while (!r.done) {
      final tag = r.varint();
      final field = tag >> 3, wire = tag & 7;
      final spec = schema[field];
      if (spec == null) {
        r.skip(wire);
        continue;
      }
      final (key, type) = spec;
      if (type.startsWith('*')) {
        final inner = type.substring(1);
        final bytes = r.bytes();
        (out[key] ??= <Object?>[]) as List;
        (out[key] as List).add(inner == 'string' ? utf8.decode(bytes, allowMalformed: true) : _decode(inner, bytes));
        continue;
      }
      switch (type) {
        case 'string':
          out[key] = utf8.decode(r.bytes(), allowMalformed: true);
        case 'int':
          out[key] = r.varint();
        case 'bool':
          out[key] = r.varint() != 0;
        case 'float':
          out[key] = r.float32();
        default:
          out[key] = _decode(type, r.bytes());
      }
    }
    return out;
  }

  /// `(type, payload)` of a received frame; unknown types give an empty payload.
  static (String type, Map<String, Object?> payload) decode(Uint8List frame) {
    final r = _Reader(frame);
    var type = '';
    var payload = Uint8List(0);
    var compressed = false;
    while (!r.done) {
      final tag = r.varint();
      switch (tag >> 3) {
        case 1:
          type = utf8.decode(r.bytes(), allowMalformed: true);
        case 2:
          payload = r.bytes();
        case 3:
          compressed = r.varint() != 0;
        default:
          r.skip(tag & 7);
      }
    }
    if (compressed && payload.isNotEmpty) payload = Uint8List.fromList(gzip.decode(payload));
    final schema = _payloadOf[type];
    return (type, schema == null || payload.isEmpty ? <String, Object?>{} : _decode(schema, payload));
  }
}

class _Reader {
  _Reader(this._b);
  final Uint8List _b;
  int _p = 0;
  bool get done => _p >= _b.length;

  int varint() {
    var result = 0, shift = 0;
    while (true) {
      if (_p >= _b.length) throw const FormatException('truncated varint');
      final byte = _b[_p++];
      if (shift < 64) result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
  }

  Uint8List bytes() {
    final n = varint();
    if (n < 0 || _p + n > _b.length) throw const FormatException('truncated field');
    final out = Uint8List.sublistView(_b, _p, _p + n);
    _p += n;
    return out;
  }

  double float32() {
    final v = ByteData.sublistView(_b, _p, _p + 4).getFloat32(0, Endian.little);
    _p += 4;
    return v;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _p += 8;
      case 2:
        bytes();
      case 5:
        _p += 4;
      default:
        throw FormatException('unsupported wire type $wire');
    }
  }
}
