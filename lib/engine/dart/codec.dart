import '../models.dart';

/// JSON maps for models: persisted queue, recent searches, backups and the
/// `feature()` results the screens decode (same shapes as docs/04).
abstract final class Codec {
  static Map<String, Object?> track(Track t) => {
    'type': 'song',
    'id': t.id,
    'title': t.title,
    'artists': [
      for (final a in t.artists) {'id': a.id, 'name': a.name},
    ],
    'albumId': t.albumId,
    'albumName': t.albumName,
    'thumbnailUrl': t.thumbnailUrl,
    'duration': t.duration.inSeconds,
    'explicit': t.explicit,
    'liked': t.liked,
    'inLibrary': t.inLibrary,
    'isDownloaded': t.isDownloaded,
    'isLocal': t.isLocal,
    'isVideo': t.isVideo,
  };

  static List<ArtistRef> _artists(Object? raw) => [
    for (final a in (raw as List? ?? const []))
      ArtistRef(id: (a as Map)['id'] as String?, name: a['name'] as String? ?? ''),
  ];

  static Track trackFrom(Map m) => Track(
    id: m['id'] as String,
    title: m['title'] as String? ?? '',
    artists: _artists(m['artists']),
    albumId: m['albumId'] as String?,
    albumName: m['albumName'] as String?,
    thumbnailUrl: m['thumbnailUrl'] as String?,
    duration: Duration(seconds: (m['duration'] as num?)?.toInt() ?? 0),
    explicit: m['explicit'] as bool? ?? false,
    liked: m['liked'] as bool? ?? false,
    inLibrary: m['inLibrary'] as bool? ?? false,
    isDownloaded: m['isDownloaded'] as bool? ?? false,
    isLocal: m['isLocal'] as bool? ?? false,
    isVideo: m['isVideo'] as bool? ?? false,
  );

  static Map<String, Object?> album(Album a) => {
    'type': 'album',
    'id': a.id,
    'title': a.title,
    'artists': [
      for (final x in a.artists) {'id': x.id, 'name': x.name},
    ],
    'year': a.year,
    'thumbnailUrl': a.thumbnailUrl,
    'songCount': a.songCount,
    'playlistId': a.playlistId,
  };

  static Album albumFrom(Map m) => Album(
    id: m['id'] as String,
    title: m['title'] as String? ?? '',
    artists: _artists(m['artists']),
    year: (m['year'] as num?)?.toInt(),
    thumbnailUrl: m['thumbnailUrl'] as String?,
    songCount: (m['songCount'] as num?)?.toInt() ?? 0,
    playlistId: m['playlistId'] as String?,
  );

  static Map<String, Object?> artist(Artist a) => {
    'type': 'artist',
    'id': a.id,
    'name': a.name,
    'thumbnailUrl': a.thumbnailUrl,
    'subtitle': a.subtitle,
  };

  static Artist artistFrom(Map m) => Artist(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    thumbnailUrl: m['thumbnailUrl'] as String?,
    subtitle: m['subtitle'] as String?,
  );

  static Map<String, Object?> playlist(Playlist p) => {
    'type': 'playlist',
    'id': p.id,
    'name': p.name,
    'kind': p.kind.name,
    'thumbnailUrl': p.thumbnailUrl,
    'songCount': p.songCount,
    'author': p.author,
    'subtitle': p.subtitle,
  };

  static Playlist playlistFrom(Map m) => Playlist(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    kind: PlaylistKind.values.asNameMap()[m['kind']] ?? PlaylistKind.local,
    thumbnailUrl: m['thumbnailUrl'] as String?,
    songCount: (m['songCount'] as num?)?.toInt() ?? 0,
    author: m['author'] as String?,
    subtitle: m['subtitle'] as String?,
  );

  static Map<String, Object?> item(MediaItem i) => switch (i) {
    TrackItem(track: final t) => track(t),
    AlbumItem(album: final a) => album(a),
    ArtistItem(artist: final a) => artist(a),
    PlaylistItem(playlist: final p) => playlist(p),
    BrowseItem() => {
      'type': 'browse',
      'title': i.title,
      'browseId': i.browseId,
      'params': i.params,
      'color': i.color,
      'thumbnailUrl': i.thumbnailUrl,
    },
  };

  static MediaItem itemFrom(Map m) => switch (m['type']) {
    'album' => AlbumItem(albumFrom(m)),
    'artist' => ArtistItem(artistFrom(m)),
    'playlist' => PlaylistItem(playlistFrom(m)),
    'browse' => BrowseItem(
      title: m['title'] as String? ?? '',
      browseId: m['browseId'] as String,
      params: m['params'] as String?,
      color: (m['color'] as num?)?.toInt(),
      thumbnailUrl: m['thumbnailUrl'] as String?,
    ),
    _ => TrackItem(trackFrom(m)),
  };
}
