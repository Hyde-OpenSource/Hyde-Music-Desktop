import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'database.dart';
import 'stream_resolver.dart';
import 'youtube_audio_source.dart';

/// Offline downloads: audio files in `<app documents>/downloads/<videoId>.<ext>`,
/// indexed by the `hyde_download` table. Two downloads run at a time.
class Downloader {
  Downloader({required this.db, required this.resolver, required this.directory}) : _reader = RangedReader(resolver);

  final HydeDatabase db;
  final StreamResolver resolver;
  final Directory directory;
  final RangedReader _reader;

  static const _parallel = 2;
  final _pending = Queue<Track>();
  final _active = <String, double>{};
  final _cancelled = <String>{};
  final _failed = <String, String>{};
  final _events = StreamController<Map<String, Object?>>.broadcast();

  /// `{topic: downloads, active, queued, progress: {id: 0..1}, failed: {id: reason}}`
  Stream<Map<String, Object?>> get events => _events.stream;

  /// Called after each finished / removed download.
  void Function(String songId, bool downloaded)? onChanged;

  Map<String, Object?> get state => {
    'topic': 'downloads',
    'active': _active.length,
    'queued': _pending.length,
    'progress': Map.of(_active),
    'failed': Map.of(_failed),
  };

  void _notify() {
    if (!_events.isClosed) _events.add(state);
  }

  bool isBusy(String id) => _active.containsKey(id) || _pending.any((t) => t.id == id);

  void enqueue(List<Track> tracks) {
    for (final t in tracks) {
      if (t.isLocal || t.isDownloaded || isBusy(t.id)) continue;
      _failed.remove(t.id);
      _cancelled.remove(t.id);
      _pending.add(t);
    }
    _notify();
    _pump();
  }

  void _pump() {
    while (_active.length < _parallel && _pending.isNotEmpty) {
      final t = _pending.removeFirst();
      _active[t.id] = 0;
      _run(t).whenComplete(() {
        _active.remove(t.id);
        _notify();
        _pump();
      });
    }
  }

  Future<void> _run(Track t) async {
    File? part;
    try {
      final existing = await db.downloadPath(t.id);
      if (existing != null && File(existing).existsSync()) return;
      final stream = await resolver.resolve(t.id);
      final length = stream.contentLength;
      if (length == null || length <= 0) throw StreamUnavailable('Unknown size');
      await directory.create(recursive: true);
      final ext = stream.mimeType.contains('mp4') ? 'm4a' : 'webm';
      final file = File(p.join(directory.path, '${t.id}.$ext'));
      part = File('${file.path}.part');
      final sink = part.openWrite();
      var got = 0;
      var lastTick = DateTime.now();
      try {
        await for (final data in _reader.read(t.id, 0, length)) {
          if (_cancelled.contains(t.id)) throw const _Cancelled();
          sink.add(data);
          got += data.length;
          _active[t.id] = got / length;
          if (DateTime.now().difference(lastTick) > const Duration(milliseconds: 300)) {
            lastTick = DateTime.now();
            _notify();
          }
        }
      } finally {
        await sink.close();
      }
      if (got != length) throw StreamUnavailable('Incomplete download');
      await part.rename(file.path);
      await db.setDownloaded(t, file.path, length);
      await db.setFormat(t.id, stream.format, contentLength: length, itag: stream.itag);
      onChanged?.call(t.id, true);
    } on _Cancelled {
      // removed by the user while running
    } catch (e) {
      _failed[t.id] = '$e';
    } finally {
      _cancelled.remove(t.id);
      if (part != null && part.existsSync()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> remove(List<Track> tracks) async {
    for (final t in tracks) {
      _pending.removeWhere((q) => q.id == t.id);
      if (_active.containsKey(t.id)) _cancelled.add(t.id);
      final path = await db.downloadPath(t.id);
      if (path != null) {
        try {
          final f = File(path);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
      await db.clearDownloaded(t.id);
      onChanged?.call(t.id, false);
    }
    _notify();
  }

  Future<void> removeAll() async {
    _pending.clear();
    _cancelled.addAll(_active.keys);
    await remove(await db.downloadedSongs());
  }

  void dispose() {
    _reader.close();
    _events.close();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
