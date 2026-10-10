import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// App settings, keyed by the native DataStore key names
/// (constants/PreferenceKeys.kt) so screens and docs keep one vocabulary.
///
/// On the first launch after updating from the native app, the old
/// `datastore/settings.preferences_pb` file is imported once.
class SettingsStore {
  SettingsStore._(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'hyde.';
  static const _migratedKey = 'hyde._migratedFromDataStore';

  final _cache = <String, Object?>{};

  static Future<SettingsStore> open({File? legacyDataStore}) async {
    final store = SettingsStore._(await SharedPreferences.getInstance());
    for (final k in store._prefs.getKeys()) {
      if (k.startsWith(_prefix) && k != _migratedKey) store._cache[k.substring(_prefix.length)] = store._prefs.get(k);
    }
    if (store._prefs.getBool(_migratedKey) != true) {
      if (legacyDataStore != null && legacyDataStore.existsSync()) {
        try {
          final old = decodeDataStore(await legacyDataStore.readAsBytes());
          for (final e in old.entries) {
            if (!store._cache.containsKey(e.key)) await store.write(e.key, e.value);
          }
        } catch (_) {
          // A corrupt legacy file must never block startup; defaults apply.
        }
      }
      await store._prefs.setBool(_migratedKey, true);
    }
    return store;
  }

  Map<String, Object?> get all => Map.of(_cache);
  Object? operator [](String key) => _cache[key];

  String? string(String key) => _cache[key] as String?;
  bool boolean(String key, [bool fallback = false]) => _cache[key] as bool? ?? fallback;

  Future<void> write(String key, Object? value) async {
    final k = '$_prefix$key';
    switch (value) {
      case null:
        _cache.remove(key);
        await _prefs.remove(k);
      case bool v:
        _cache[key] = v;
        await _prefs.setBool(k, v);
      case int v:
        _cache[key] = v;
        await _prefs.setInt(k, v);
      case double v:
        _cache[key] = v;
        await _prefs.setDouble(k, v);
      case String v:
        _cache[key] = v;
        await _prefs.setString(k, v);
      case List v:
        final list = v.map((e) => '$e').toList();
        _cache[key] = list;
        await _prefs.setStringList(k, list);
      default:
        final s = jsonEncode(value);
        _cache[key] = s;
        await _prefs.setString(k, s);
    }
  }

  Future<void> replaceAll(Map<String, Object?> values) async {
    for (final k in _cache.keys.toList()) {
      await write(k, null);
    }
    for (final e in values.entries) {
      await write(e.key, e.value);
    }
  }

  /// Decodes an AndroidX DataStore `preferences_pb` file:
  /// `PreferenceMap { map<string, Value> preferences = 1; }` where Value is a
  /// oneof of bool(1) float(2) int32(3) int64(4) string(5) string_set(6)
  /// double(7) bytes(8).
  static Map<String, Object?> decodeDataStore(Uint8List bytes) {
    final out = <String, Object?>{};
    final r = _ProtoReader(bytes);
    while (!r.done) {
      final (field, wire) = r.tag();
      if (field == 1 && wire == 2) {
        final entry = _ProtoReader(r.bytes());
        String? key;
        Object? value;
        while (!entry.done) {
          final (f, w) = entry.tag();
          if (f == 1 && w == 2) {
            key = utf8.decode(entry.bytes(), allowMalformed: true);
          } else if (f == 2 && w == 2) {
            value = _value(_ProtoReader(entry.bytes()));
          } else {
            entry.skip(w);
          }
        }
        if (key != null && value != null) out[key] = value;
      } else {
        r.skip(wire);
      }
    }
    return out;
  }

  static Object? _value(_ProtoReader r) {
    Object? value;
    while (!r.done) {
      final (f, w) = r.tag();
      switch (f) {
        case 1 when w == 0:
          value = r.varint() != 0;
        case 2 when w == 5:
          value = r.fixed32Float();
        case 3 when w == 0:
          value = r.varint().toSigned(32);
        case 4 when w == 0:
          value = r.varint();
        case 5 when w == 2:
          value = utf8.decode(r.bytes(), allowMalformed: true);
        case 6 when w == 2:
          final set = _ProtoReader(r.bytes());
          final list = <String>[];
          while (!set.done) {
            final (sf, sw) = set.tag();
            if (sf == 1 && sw == 2) {
              list.add(utf8.decode(set.bytes(), allowMalformed: true));
            } else {
              set.skip(sw);
            }
          }
          value = list;
        case 7 when w == 1:
          value = r.fixed64Double();
        default:
          r.skip(w);
      }
    }
    return value;
  }
}

class _ProtoReader {
  _ProtoReader(this._b);
  final Uint8List _b;
  int _p = 0;

  bool get done => _p >= _b.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_p >= _b.length) throw const FormatException('truncated varint');
      final byte = _b[_p++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('varint too long');
    }
  }

  (int field, int wire) tag() {
    final t = varint();
    return (t >> 3, t & 7);
  }

  Uint8List bytes() {
    final n = varint();
    if (n < 0 || _p + n > _b.length) throw const FormatException('truncated field');
    final out = Uint8List.sublistView(_b, _p, _p + n);
    _p += n;
    return out;
  }

  double fixed32Float() {
    final v = ByteData.sublistView(_b, _p, _p + 4).getFloat32(0, Endian.little);
    _p += 4;
    return v;
  }

  double fixed64Double() {
    final v = ByteData.sublistView(_b, _p, _p + 8).getFloat64(0, Endian.little);
    _p += 8;
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
