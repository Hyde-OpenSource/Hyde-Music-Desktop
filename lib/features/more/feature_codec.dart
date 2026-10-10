import '../../engine/models.dart';

/// Decoders for maps returned by `HydeEngine.feature` (same shapes as the
/// engine bridge's track/album/artist maps).
Track trackFromMap(Map m) => Track(
  id: m['id'] as String,
  title: m['title'] as String? ?? '',
  artists: [
    for (final a in ((m['artists'] as List?) ?? const []).cast<Map>())
      ArtistRef(id: a['id'] as String?, name: a['name'] as String? ?? ''),
  ],
  albumId: m['albumId'] as String?,
  albumName: m['albumName'] as String?,
  thumbnailUrl: m['thumbnailUrl'] as String?,
  duration: Duration(seconds: (m['duration'] as num?)?.toInt() ?? 0),
  liked: m['liked'] as bool? ?? false,
  inLibrary: m['inLibrary'] as bool? ?? false,
  isDownloaded: m['isDownloaded'] as bool? ?? false,
  isLocal: m['isLocal'] as bool? ?? false,
);

String formatListening(int ms) {
  final minutes = ms ~/ 60000;
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  return '$h h ${minutes % 60} min';
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
