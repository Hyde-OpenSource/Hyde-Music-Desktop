import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';

/// The library database: the SAME file and schema as the native app's Room
/// database (`song.db`, version 27), so an existing user's library, playlists,
/// likes, history and stats are simply there after the update.
///
/// Timestamps are epoch milliseconds (Room `Converters`).
class HydeDatabase {
  HydeDatabase._(this.db);
  final Database db;

  static const schemaVersion = 27;

  static Future<HydeDatabase> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final file = path ?? p.join(await f.getDatabasesPath(), 'song.db');
    final db = await f.openDatabase(
      file,
      options: OpenDatabaseOptions(
        // No sqflite-managed version: Room owns `user_version`; we only make
        // sure every table/column we use exists (works for fresh installs and
        // for databases left at any 4.x schema).
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    final self = HydeDatabase._(db);
    await self._ensureSchema();
    return self;
  }

  Future<void> close() => db.close();

  // ── Schema ───────────────────────────────────────────────────────────────

  static const _tables = [
    'CREATE TABLE IF NOT EXISTS `song` (`id` TEXT NOT NULL, `title` TEXT NOT NULL, `duration` INTEGER NOT NULL, `thumbnailUrl` TEXT, `albumId` TEXT, `albumName` TEXT, `explicit` INTEGER NOT NULL DEFAULT 0, `year` INTEGER, `date` INTEGER, `dateModified` INTEGER, `liked` INTEGER NOT NULL, `likedDate` INTEGER, `totalPlayTime` INTEGER NOT NULL, `inLibrary` INTEGER, `dateDownload` INTEGER, `isLocal` INTEGER NOT NULL DEFAULT false, `libraryAddToken` TEXT, `libraryRemoveToken` TEXT, `romanizeLyrics` INTEGER NOT NULL DEFAULT true, `isDownloaded` INTEGER NOT NULL DEFAULT 0, `isUploaded` INTEGER NOT NULL DEFAULT false, `localPath` TEXT DEFAULT NULL, PRIMARY KEY(`id`))',
    'CREATE INDEX IF NOT EXISTS `index_song_albumId` ON `song` (`albumId`)',
    'CREATE TABLE IF NOT EXISTS `artist` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, `thumbnailUrl` TEXT, `channelId` TEXT, `lastUpdateTime` INTEGER NOT NULL, `bookmarkedAt` INTEGER, `isLocal` INTEGER NOT NULL DEFAULT false, PRIMARY KEY(`id`))',
    'CREATE TABLE IF NOT EXISTS `album` (`id` TEXT NOT NULL, `playlistId` TEXT, `title` TEXT NOT NULL, `year` INTEGER, `thumbnailUrl` TEXT, `themeColor` INTEGER, `songCount` INTEGER NOT NULL, `duration` INTEGER NOT NULL, `explicit` INTEGER NOT NULL DEFAULT 0, `lastUpdateTime` INTEGER NOT NULL, `bookmarkedAt` INTEGER, `likedDate` INTEGER, `inLibrary` INTEGER, `isLocal` INTEGER NOT NULL DEFAULT false, `isUploaded` INTEGER NOT NULL DEFAULT false, PRIMARY KEY(`id`))',
    'CREATE TABLE IF NOT EXISTS `playlist` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, `browseId` TEXT, `createdAt` INTEGER, `lastUpdateTime` INTEGER, `isEditable` INTEGER NOT NULL DEFAULT true, `bookmarkedAt` INTEGER, `remoteSongCount` INTEGER, `playEndpointParams` TEXT, `thumbnailUrl` TEXT, `shuffleEndpointParams` TEXT, `radioEndpointParams` TEXT, `isLocal` INTEGER NOT NULL DEFAULT false, PRIMARY KEY(`id`))',
    'CREATE TABLE IF NOT EXISTS `song_artist_map` (`songId` TEXT NOT NULL, `artistId` TEXT NOT NULL, `position` INTEGER NOT NULL, PRIMARY KEY(`songId`, `artistId`), FOREIGN KEY(`songId`) REFERENCES `song`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE , FOREIGN KEY(`artistId`) REFERENCES `artist`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )',
    'CREATE INDEX IF NOT EXISTS `index_song_artist_map_songId` ON `song_artist_map` (`songId`)',
    'CREATE INDEX IF NOT EXISTS `index_song_artist_map_artistId` ON `song_artist_map` (`artistId`)',
    'CREATE TABLE IF NOT EXISTS `song_album_map` (`songId` TEXT NOT NULL, `albumId` TEXT NOT NULL, `index` INTEGER NOT NULL, PRIMARY KEY(`songId`, `albumId`), FOREIGN KEY(`songId`) REFERENCES `song`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE , FOREIGN KEY(`albumId`) REFERENCES `album`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )',
    'CREATE INDEX IF NOT EXISTS `index_song_album_map_songId` ON `song_album_map` (`songId`)',
    'CREATE INDEX IF NOT EXISTS `index_song_album_map_albumId` ON `song_album_map` (`albumId`)',
    'CREATE TABLE IF NOT EXISTS `album_artist_map` (`albumId` TEXT NOT NULL, `artistId` TEXT NOT NULL, `order` INTEGER NOT NULL, PRIMARY KEY(`albumId`, `artistId`), FOREIGN KEY(`albumId`) REFERENCES `album`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE , FOREIGN KEY(`artistId`) REFERENCES `artist`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )',
    'CREATE INDEX IF NOT EXISTS `index_album_artist_map_albumId` ON `album_artist_map` (`albumId`)',
    'CREATE INDEX IF NOT EXISTS `index_album_artist_map_artistId` ON `album_artist_map` (`artistId`)',
    'CREATE TABLE IF NOT EXISTS `playlist_song_map` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `playlistId` TEXT NOT NULL, `songId` TEXT NOT NULL, `position` INTEGER NOT NULL, `setVideoId` TEXT, FOREIGN KEY(`playlistId`) REFERENCES `playlist`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE , FOREIGN KEY(`songId`) REFERENCES `song`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )',
    'CREATE INDEX IF NOT EXISTS `index_playlist_song_map_playlistId` ON `playlist_song_map` (`playlistId`)',
    'CREATE INDEX IF NOT EXISTS `index_playlist_song_map_songId` ON `playlist_song_map` (`songId`)',
    'CREATE TABLE IF NOT EXISTS `search_history` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `query` TEXT NOT NULL)',
    'CREATE UNIQUE INDEX IF NOT EXISTS `index_search_history_query` ON `search_history` (`query`)',
    'CREATE TABLE IF NOT EXISTS `format` (`id` TEXT NOT NULL, `itag` INTEGER NOT NULL, `mimeType` TEXT NOT NULL, `codecs` TEXT NOT NULL, `bitrate` INTEGER NOT NULL, `sampleRate` INTEGER, `contentLength` INTEGER NOT NULL, `loudnessDb` REAL, `playbackUrl` TEXT, PRIMARY KEY(`id`))',
    'CREATE TABLE IF NOT EXISTS `lyrics` (`id` TEXT NOT NULL, `lyrics` TEXT NOT NULL, PRIMARY KEY(`id`))',
    'CREATE TABLE IF NOT EXISTS `event` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `songId` TEXT NOT NULL, `timestamp` INTEGER NOT NULL, `playTime` INTEGER NOT NULL, FOREIGN KEY(`songId`) REFERENCES `song`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )',
    'CREATE INDEX IF NOT EXISTS `index_event_songId` ON `event` (`songId`)',
    'CREATE TABLE IF NOT EXISTS `related_song_map` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `songId` TEXT NOT NULL, `relatedSongId` TEXT NOT NULL, FOREIGN KEY(`songId`) REFERENCES `song`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE , FOREIGN KEY(`relatedSongId`) REFERENCES `song`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )',
    'CREATE INDEX IF NOT EXISTS `index_related_song_map_songId` ON `related_song_map` (`songId`)',
    'CREATE INDEX IF NOT EXISTS `index_related_song_map_relatedSongId` ON `related_song_map` (`relatedSongId`)',
    'CREATE TABLE IF NOT EXISTS `set_video_id` (`videoId` TEXT NOT NULL, `setVideoId` TEXT, PRIMARY KEY(`videoId`))',
    'CREATE TABLE IF NOT EXISTS `playCount` (`song` TEXT NOT NULL, `year` INTEGER NOT NULL, `month` INTEGER NOT NULL, `count` INTEGER NOT NULL, PRIMARY KEY(`song`, `year`, `month`))',
    'CREATE TABLE IF NOT EXISTS `account` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, `email` TEXT NOT NULL, `channelHandle` TEXT NOT NULL, `thumbnailUrl` TEXT, `innerTubeCookie` TEXT NOT NULL, `visitorData` TEXT NOT NULL, `dataSyncId` TEXT NOT NULL, `isActive` INTEGER NOT NULL, `createdAt` INTEGER NOT NULL, `lastUsedAt` INTEGER NOT NULL, PRIMARY KEY(`id`))',
    'CREATE TABLE IF NOT EXISTS `user_action` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, `songId` TEXT NOT NULL, `actionType` TEXT NOT NULL, `timestamp` INTEGER NOT NULL, `context` TEXT, FOREIGN KEY(`songId`) REFERENCES `song`(`id`) ON UPDATE NO ACTION ON DELETE CASCADE )',
    'CREATE INDEX IF NOT EXISTS `index_user_action_songId` ON `user_action` (`songId`)',
    'CREATE VIEW IF NOT EXISTS `sorted_song_artist_map` AS SELECT * FROM song_artist_map ORDER BY position',
    'CREATE VIEW IF NOT EXISTS `sorted_song_album_map` AS SELECT * FROM song_album_map ORDER BY `index`',
    'CREATE VIEW IF NOT EXISTS `playlist_song_map_preview` AS SELECT * FROM playlist_song_map WHERE position <= 3 ORDER BY position',
    // Flutter-only: downloaded files (the native app kept downloads inside
    // ExoPlayer's cache, which can't be read from Dart).
    'CREATE TABLE IF NOT EXISTS `hyde_download` (`songId` TEXT NOT NULL, `path` TEXT NOT NULL, `bytes` INTEGER NOT NULL, `date` INTEGER NOT NULL, PRIMARY KEY(`songId`))',
    'CREATE TABLE IF NOT EXISTS `hyde_pending_download` (`songId` TEXT NOT NULL, PRIMARY KEY(`songId`))',
    'CREATE TABLE IF NOT EXISTS `hyde_recent_item` (`query` TEXT NOT NULL, `json` TEXT NOT NULL, PRIMARY KEY(`query`))',
  ];

  Future<void> _ensureSchema() async {
    final fresh = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='song'")).isEmpty;
    final migrated = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='hyde_download'")).isNotEmpty;
    for (final sql in _tables) {
      await db.execute(sql);
    }
    final cols = (await db.rawQuery('PRAGMA table_info(song)')).map((r) => r['name']).toSet();
    if (!cols.contains('localPath')) await db.execute('ALTER TABLE song ADD COLUMN localPath TEXT DEFAULT NULL');
    if (fresh) {
      await db.execute('PRAGMA user_version = $schemaVersion');
    } else if (!migrated) {
      // First start after the native app: its downloads lived in ExoPlayer's
      // cache. Remember them so the user can re-download in one tap.
      await db.execute(
        'INSERT OR IGNORE INTO hyde_pending_download(songId) '
        'SELECT id FROM song WHERE isLocal = 0 AND (isDownloaded = 1 OR dateDownload IS NOT NULL)',
      );
      await db.execute('UPDATE song SET isDownloaded = 0, dateDownload = NULL WHERE isLocal = 0');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static int now() => DateTime.now().millisecondsSinceEpoch;

  static final _rand = Random();
  static String _localId(String prefix) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    return prefix + List.generate(8, (_) => letters[_rand.nextInt(letters.length)]).join();
  }

  static String _in(int n) => List.filled(n, '?').join(',');

  /// Song rows → [Track]s with their artists (one extra query per 500 rows).
  Future<List<Track>> _tracks(List<Map<String, Object?>> rows, [DatabaseExecutor? ex]) async {
    if (rows.isEmpty) return const [];
    final e = ex ?? db;
    final artists = <String, List<ArtistRef>>{};
    final ids = rows.map((r) => r['id'] as String).toSet().toList();
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, min(i + 500, ids.length));
      final maps = await e.rawQuery(
        'SELECT m.songId, a.id, a.name FROM song_artist_map m JOIN artist a ON a.id = m.artistId '
        'WHERE m.songId IN (${_in(chunk.length)}) ORDER BY m.songId, m.position',
        chunk,
      );
      for (final m in maps) {
        final id = m['id'] as String;
        (artists[m['songId'] as String] ??= []).add(
          // Local ("LA…") artists have no YouTube page.
          ArtistRef(id: id.startsWith('LA') ? null : id, name: m['name'] as String),
        );
      }
    }
    return [for (final r in rows) _track(r, artists[r['id']] ?? const [])];
  }

  static Track _track(Map<String, Object?> r, List<ArtistRef> artists) {
    final d = (r['duration'] as int?) ?? 0;
    return Track(
      id: r['id'] as String,
      title: r['title'] as String,
      artists: artists,
      albumId: r['albumId'] as String?,
      albumName: r['albumName'] as String?,
      thumbnailUrl: r['thumbnailUrl'] as String?,
      duration: Duration(seconds: d < 0 ? 0 : d),
      explicit: r['explicit'] == 1,
      liked: r['liked'] == 1,
      inLibrary: r['inLibrary'] != null,
      isDownloaded: r['isDownloaded'] == 1,
      isLocal: r['isLocal'] == 1,
    );
  }

  // ── Songs ────────────────────────────────────────────────────────────────

  /// Inserts the song (and its artists) if it isn't known yet — every action
  /// on a YouTube-only track goes through this first, like the native
  /// `database.insert(mediaMetadata)`.
  Future<void> ensureTrack(Track t, [DatabaseExecutor? ex]) async {
    Future<void> run(DatabaseExecutor e) async {
      final existing = await e.query('song', columns: ['thumbnailUrl', 'duration'], where: 'id = ?', whereArgs: [t.id]);
      if (existing.isNotEmpty) {
        final row = existing.first;
        final patch = <String, Object?>{
          if (row['thumbnailUrl'] == null && t.thumbnailUrl != null) 'thumbnailUrl': t.thumbnailUrl,
          if (((row['duration'] as int?) ?? 0) <= 0 && t.duration > Duration.zero) 'duration': t.duration.inSeconds,
        };
        if (patch.isNotEmpty) await e.update('song', patch, where: 'id = ?', whereArgs: [t.id]);
        return;
      }
      await e.insert('song', {
        'id': t.id,
        'title': t.title,
        'duration': t.duration.inSeconds == 0 ? -1 : t.duration.inSeconds,
        'thumbnailUrl': t.thumbnailUrl,
        'albumId': t.albumId,
        'albumName': t.albumName,
        'explicit': t.explicit ? 1 : 0,
        'liked': 0,
        'totalPlayTime': 0,
        'isLocal': t.isLocal ? 1 : 0,
        'romanizeLyrics': 1,
        'isDownloaded': 0,
        'isUploaded': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      for (var i = 0; i < t.artists.length; i++) {
        final a = t.artists[i];
        var id = a.id;
        if (id == null) {
          final byName = await e.query('artist', columns: ['id'], where: 'name = ?', whereArgs: [a.name], limit: 1);
          id = byName.isEmpty ? _localId('LA') : byName.first['id'] as String;
        }
        await e.insert('artist', {
          'id': id,
          'name': a.name,
          'lastUpdateTime': now(),
          'isLocal': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await e.insert('song_artist_map', {
          'songId': t.id,
          'artistId': id,
          'position': i,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    if (ex != null) return run(ex);
    return db.transaction(run);
  }

  Future<void> ensureTracks(List<Track> tracks) => db.transaction((txn) async {
    for (final t in tracks) {
      await ensureTrack(t, txn);
    }
  });

  Future<Track?> track(String id) async {
    final rows = await db.query('song', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : (await _tracks(rows)).first;
  }

  /// Library/like/download flags for a batch of ids: {id: (liked, inLibrary, downloaded)}.
  Future<Map<String, ({bool liked, bool inLibrary, bool downloaded})>> flags(Iterable<String> ids) async {
    final out = <String, ({bool liked, bool inLibrary, bool downloaded})>{};
    final list = ids.toSet().toList();
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(i, min(i + 500, list.length));
      final rows = await db.rawQuery(
        'SELECT id, liked, inLibrary, isDownloaded FROM song WHERE id IN (${_in(chunk.length)})',
        chunk,
      );
      for (final r in rows) {
        out[r['id'] as String] = (
          liked: r['liked'] == 1,
          inLibrary: r['inLibrary'] != null,
          downloaded: r['isDownloaded'] == 1,
        );
      }
    }
    return out;
  }

  /// Applies the stored liked / library / downloaded flags to online tracks.
  Future<List<Track>> decorate(List<Track> tracks) async {
    if (tracks.isEmpty) return tracks;
    final f = await flags(tracks.map((t) => t.id));
    if (f.isEmpty) return tracks;
    return [
      for (final t in tracks)
        if (f[t.id] case final x?)
          t.copyWith(liked: x.liked, inLibrary: x.inLibrary, isDownloaded: x.downloaded)
        else
          t,
    ];
  }

  Future<void> setLiked(Track t, bool liked) async {
    await ensureTrack(t);
    await db.update(
      'song',
      {
        'liked': liked ? 1 : 0,
        'likedDate': liked ? now() : null,
        // Liking adds to the library, like the native toggleLike().
        if (liked) 'inLibrary': now(),
      },
      where: 'id = ?',
      whereArgs: [t.id],
    );
  }

  Future<void> setInLibrary(Track t, bool inLibrary) async {
    await ensureTrack(t);
    await db.update('song', {'inLibrary': inLibrary ? now() : null}, where: 'id = ?', whereArgs: [t.id]);
  }

  static String _songOrder(String? sort, bool descending) {
    final dir = descending ? 'DESC' : 'ASC';
    return switch (sort) {
      'NAME' => 'title COLLATE NOCASE $dir',
      'PLAY_TIME' => 'totalPlayTime $dir',
      'ARTIST' => '(SELECT a.name FROM song_artist_map m JOIN artist a ON a.id = m.artistId '
          'WHERE m.songId = song.id ORDER BY m.position LIMIT 1) COLLATE NOCASE $dir, title COLLATE NOCASE',
      _ => 'COALESCE(inLibrary, likedDate, dateDownload, 0) $dir, rowid $dir',
    };
  }

  Future<List<Track>> librarySongs({String? sort, bool descending = true}) async =>
      _tracks(await db.rawQuery('SELECT * FROM song WHERE inLibrary IS NOT NULL OR isLocal = 1 OR isDownloaded = 1 '
          'ORDER BY ${_songOrder(sort, descending)}'));

  Future<List<Track>> likedSongs() async =>
      _tracks(await db.rawQuery('SELECT * FROM song WHERE liked = 1 ORDER BY likedDate DESC, rowid DESC'));

  Future<List<Track>> downloadedSongs() async => _tracks(
    await db.rawQuery('SELECT * FROM song WHERE isDownloaded = 1 AND isLocal = 0 ORDER BY dateDownload DESC'),
  );

  Future<List<Track>> localSongs() async =>
      _tracks(await db.rawQuery('SELECT * FROM song WHERE isLocal = 1 ORDER BY title COLLATE NOCASE'));

  Future<List<Track>> topSongs({int limit = 50}) async => _tracks(
    await db.rawQuery('SELECT * FROM song WHERE totalPlayTime > 0 ORDER BY totalPlayTime DESC LIMIT ?', [limit]),
  );

  Future<List<Track>> searchSongs(String q, {int limit = 60}) async {
    final like = '%${q.replaceAll('%', r'\%')}%';
    return _tracks(
      await db.rawQuery(
        'SELECT DISTINCT song.* FROM song '
        'LEFT JOIN song_artist_map m ON m.songId = song.id LEFT JOIN artist a ON a.id = m.artistId '
        "WHERE (song.title LIKE ? ESCAPE '\\' OR a.name LIKE ? ESCAPE '\\' OR song.albumName LIKE ? ESCAPE '\\') "
        'AND (song.inLibrary IS NOT NULL OR song.liked = 1 OR song.isDownloaded = 1 OR song.isLocal = 1 OR song.totalPlayTime > 0) '
        'ORDER BY song.totalPlayTime DESC LIMIT ?',
        [like, like, like, limit],
      ),
    );
  }

  // ── Artists / albums ─────────────────────────────────────────────────────

  Future<List<Artist>> libraryArtists() async {
    final rows = await db.rawQuery(
      'SELECT a.*, (SELECT COUNT(*) FROM song_artist_map m JOIN song s ON s.id = m.songId '
      'WHERE m.artistId = a.id AND (s.inLibrary IS NOT NULL OR s.liked = 1 OR s.isDownloaded = 1 OR s.isLocal = 1)) AS songCount '
      'FROM artist a WHERE a.bookmarkedAt IS NOT NULL OR songCount > 0 '
      'ORDER BY a.name COLLATE NOCASE',
    );
    return [
      for (final r in rows)
        Artist(
          id: r['id'] as String,
          name: r['name'] as String,
          thumbnailUrl: r['thumbnailUrl'] as String?,
          subscribed: r['bookmarkedAt'] != null,
          channelId: r['channelId'] as String?,
          subtitle: (r['songCount'] as int) == 1 ? '1 song' : '${r['songCount']} songs',
        ),
    ];
  }

  Future<bool> isArtistBookmarked(String id) async =>
      (await db.query('artist', where: 'id = ? AND bookmarkedAt IS NOT NULL', whereArgs: [id])).isNotEmpty;

  Future<void> setArtistBookmarked(Artist a, bool bookmarked) async {
    await db.insert('artist', {
      'id': a.id,
      'name': a.name,
      'thumbnailUrl': a.thumbnailUrl,
      'channelId': a.channelId,
      'lastUpdateTime': now(),
      'isLocal': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.update(
      'artist',
      {'bookmarkedAt': bookmarked ? now() : null, if (a.thumbnailUrl != null) 'thumbnailUrl': a.thumbnailUrl},
      where: 'id = ?',
      whereArgs: [a.id],
    );
  }

  /// Keeps artist artwork fresh (rows created from song metadata have none).
  Future<void> updateArtistArtwork(String id, String? thumbnailUrl) async {
    if (thumbnailUrl == null) return;
    await db.update('artist', {'thumbnailUrl': thumbnailUrl, 'lastUpdateTime': now()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Track>> artistSongs(String artistId) async => _tracks(
    await db.rawQuery(
      'SELECT song.* FROM song JOIN song_artist_map m ON m.songId = song.id WHERE m.artistId = ? '
      'AND (song.inLibrary IS NOT NULL OR song.liked = 1 OR song.isDownloaded = 1 OR song.isLocal = 1) '
      'ORDER BY song.title COLLATE NOCASE',
      [artistId],
    ),
  );

  Future<List<Album>> _albums(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r['id'] as String).toList();
    final artists = <String, List<ArtistRef>>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, min(i + 500, ids.length));
      final maps = await db.rawQuery(
        'SELECT m.albumId, a.id, a.name FROM album_artist_map m JOIN artist a ON a.id = m.artistId '
        'WHERE m.albumId IN (${_in(chunk.length)}) ORDER BY m.albumId, m.`order`',
        chunk,
      );
      for (final m in maps) {
        final id = m['id'] as String;
        (artists[m['albumId'] as String] ??= []).add(
          ArtistRef(id: id.startsWith('LA') ? null : id, name: m['name'] as String),
        );
      }
    }
    return [
      for (final r in rows)
        Album(
          id: r['id'] as String,
          title: r['title'] as String,
          artists: artists[r['id']] ?? const [],
          year: r['year'] as int?,
          thumbnailUrl: r['thumbnailUrl'] as String?,
          songCount: (r['songCount'] as int?) ?? 0,
          playlistId: r['playlistId'] as String?,
          explicit: r['explicit'] == 1,
          inLibrary: r['bookmarkedAt'] != null,
        ),
    ];
  }

  Future<List<Album>> libraryAlbums() async => _albums(
    await db.rawQuery(
      'SELECT * FROM album WHERE bookmarkedAt IS NOT NULL OR inLibrary IS NOT NULL OR isLocal = 1 '
      'ORDER BY COALESCE(bookmarkedAt, inLibrary, lastUpdateTime) DESC',
    ),
  );

  Future<bool> isAlbumBookmarked(String id) async =>
      (await db.query('album', where: 'id = ? AND bookmarkedAt IS NOT NULL', whereArgs: [id])).isNotEmpty;

  /// Saves an album with its songs (native `AlbumMenu` bookmark / download).
  Future<void> saveAlbum(Album album, List<Track> tracks, {bool? bookmarked}) => db.transaction((txn) async {
    await txn.insert('album', {
      'id': album.id,
      'playlistId': album.playlistId,
      'title': album.title,
      'year': album.year,
      'thumbnailUrl': album.thumbnailUrl,
      'songCount': tracks.length,
      'duration': tracks.fold<int>(0, (a, t) => a + t.duration.inSeconds),
      'explicit': album.explicit ? 1 : 0,
      'lastUpdateTime': now(),
      'isLocal': 0,
      'isUploaded': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (bookmarked != null) {
      await txn.update('album', {'bookmarkedAt': bookmarked ? now() : null}, where: 'id = ?', whereArgs: [album.id]);
    }
    for (var i = 0; i < album.artists.length; i++) {
      final a = album.artists[i];
      final id = a.id ?? _localId('LA');
      await txn.insert('artist', {
        'id': id,
        'name': a.name,
        'lastUpdateTime': now(),
        'isLocal': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('album_artist_map', {
        'albumId': album.id,
        'artistId': id,
        'order': i,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (var i = 0; i < tracks.length; i++) {
      await ensureTrack(tracks[i], txn);
      await txn.update(
        'song',
        {'albumId': album.id, 'albumName': album.title},
        where: 'id = ? AND albumId IS NULL',
        whereArgs: [tracks[i].id],
      );
      await txn.insert('song_album_map', {
        'songId': tracks[i].id,
        'albumId': album.id,
        'index': i,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  });

  Future<List<Track>> albumSongs(String albumId) async => _tracks(
    await db.rawQuery(
      'SELECT song.* FROM song JOIN song_album_map m ON m.songId = song.id WHERE m.albumId = ? ORDER BY m.`index`',
      [albumId],
    ),
  );

  // ── Playlists ────────────────────────────────────────────────────────────

  Future<List<Playlist>> playlists({String? sort, bool descending = true}) async {
    final dir = descending ? 'DESC' : 'ASC';
    final order = switch (sort) {
      'NAME' => 'p.name COLLATE NOCASE $dir',
      'SONG_COUNT' => 'songCount $dir',
      'LAST_UPDATED' => 'COALESCE(p.lastUpdateTime, p.createdAt, 0) $dir',
      _ => 'COALESCE(p.createdAt, p.bookmarkedAt, 0) $dir, p.rowid $dir',
    };
    final rows = await db.rawQuery(
      'SELECT p.*, (SELECT COUNT(*) FROM playlist_song_map WHERE playlistId = p.id) AS songCount, '
      '(SELECT s.thumbnailUrl FROM playlist_song_map m JOIN song s ON s.id = m.songId '
      'WHERE m.playlistId = p.id AND s.thumbnailUrl IS NOT NULL ORDER BY m.position LIMIT 1) AS firstThumb '
      'FROM playlist p ORDER BY $order',
    );
    return [for (final r in rows) _playlist(r)];
  }

  static Playlist _playlist(Map<String, Object?> r) {
    final local = (r['songCount'] as int?) ?? 0;
    return Playlist(
      id: r['id'] as String,
      name: r['name'] as String,
      kind: PlaylistKind.local,
      thumbnailUrl: (r['thumbnailUrl'] as String?) ?? (r['firstThumb'] as String?),
      songCount: local > 0 ? local : ((r['remoteSongCount'] as int?) ?? 0),
      isEditable: r['isEditable'] != 0,
    );
  }

  Future<Map<String, Object?>?> playlistRow(String id) async {
    final rows = await db.query('playlist', where: 'id = ? OR browseId = ?', whereArgs: [id, id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Playlist> createPlaylist(String name, {String? browseId, String? thumbnailUrl, bool editable = true}) async {
    final id = _localId('LP');
    await db.insert('playlist', {
      'id': id,
      'name': name,
      'browseId': browseId,
      'createdAt': now(),
      'lastUpdateTime': now(),
      'isEditable': editable ? 1 : 0,
      'bookmarkedAt': now(),
      'thumbnailUrl': thumbnailUrl,
      'isLocal': 0,
    });
    return Playlist(id: id, name: name, thumbnailUrl: thumbnailUrl, isEditable: editable);
  }

  Future<void> renamePlaylist(String id, String name) =>
      db.update('playlist', {'name': name, 'lastUpdateTime': now()}, where: 'id = ?', whereArgs: [id]);

  Future<void> deletePlaylist(String id) => db.delete('playlist', where: 'id = ?', whereArgs: [id]);

  Future<List<Track>> playlistSongs(String playlistId) async => _tracks(
    await db.rawQuery(
      'SELECT song.*, m.id AS mapId FROM playlist_song_map m JOIN song ON song.id = m.songId '
      'WHERE m.playlistId = ? ORDER BY m.position',
      [playlistId],
    ),
  );

  /// Appends tracks, skipping ones already in the playlist. Returns how many were added.
  Future<int> addToPlaylist(String playlistId, List<Track> tracks) => db.transaction((txn) async {
    final have = (await txn.query('playlist_song_map', columns: ['songId'], where: 'playlistId = ?', whereArgs: [playlistId]))
        .map((r) => r['songId'])
        .toSet();
    var pos = Sqflite.firstIntValue(
          await txn.rawQuery('SELECT MAX(position) FROM playlist_song_map WHERE playlistId = ?', [playlistId]),
        ) ??
        -1;
    var added = 0;
    for (final t in tracks) {
      if (!have.add(t.id)) continue;
      await ensureTrack(t, txn);
      await txn.insert('playlist_song_map', {'playlistId': playlistId, 'songId': t.id, 'position': ++pos});
      added++;
    }
    await txn.update('playlist', {'lastUpdateTime': now()}, where: 'id = ?', whereArgs: [playlistId]);
    return added;
  });

  Future<void> removeFromPlaylist(String playlistId, String songId) => db.transaction((txn) async {
    await txn.delete('playlist_song_map', where: 'playlistId = ? AND songId = ?', whereArgs: [playlistId, songId]);
    await _renumber(txn, playlistId);
  });

  Future<void> movePlaylistSong(String playlistId, int from, int to) => db.transaction((txn) async {
    final rows = await txn.query('playlist_song_map', columns: ['id'], where: 'playlistId = ?', whereArgs: [playlistId], orderBy: 'position');
    final ids = rows.map((r) => r['id'] as int).toList();
    if (from < 0 || from >= ids.length || to < 0 || to >= ids.length) return;
    ids.insert(to, ids.removeAt(from));
    for (var i = 0; i < ids.length; i++) {
      await txn.update('playlist_song_map', {'position': i}, where: 'id = ?', whereArgs: [ids[i]]);
    }
  });

  static Future<void> _renumber(Transaction txn, String playlistId) async {
    final rows = await txn.query('playlist_song_map', columns: ['id'], where: 'playlistId = ?', whereArgs: [playlistId], orderBy: 'position');
    for (var i = 0; i < rows.length; i++) {
      await txn.update('playlist_song_map', {'position': i}, where: 'id = ?', whereArgs: [rows[i]['id']]);
    }
  }

  /// Replaces a playlist's contents (sync from YouTube / import).
  Future<void> setPlaylistSongs(String playlistId, List<Track> tracks) => db.transaction((txn) async {
    await txn.delete('playlist_song_map', where: 'playlistId = ?', whereArgs: [playlistId]);
    final seen = <String>{};
    var pos = 0;
    for (final t in tracks) {
      if (!seen.add(t.id)) continue;
      await ensureTrack(t, txn);
      await txn.insert('playlist_song_map', {'playlistId': playlistId, 'songId': t.id, 'position': pos++});
    }
    await txn.update('playlist', {'lastUpdateTime': now(), 'remoteSongCount': pos}, where: 'id = ?', whereArgs: [playlistId]);
  });

  // ── History / stats ──────────────────────────────────────────────────────

  /// Records a listen (native MusicService: only plays ≥ the history threshold).
  Future<void> recordPlay(Track t, Duration played) async {
    await ensureTrack(t);
    final d = DateTime.now();
    await db.transaction((txn) async {
      await txn.insert('event', {'songId': t.id, 'timestamp': now(), 'playTime': played.inMilliseconds});
      await txn.rawUpdate('UPDATE song SET totalPlayTime = totalPlayTime + ? WHERE id = ?', [played.inMilliseconds, t.id]);
      await txn.rawInsert(
        'INSERT INTO playCount(song, year, month, count) VALUES(?, ?, ?, 1) '
        'ON CONFLICT(song, year, month) DO UPDATE SET count = count + 1',
        [t.id, d.year, d.month],
      );
    });
  }

  Future<List<({int id, DateTime at, Track track})>> history({int limit = 500}) async {
    final rows = await db.rawQuery(
      'SELECT e.id AS eventId, e.timestamp AS eventTime, song.* FROM event e JOIN song ON song.id = e.songId '
      'ORDER BY e.timestamp DESC, e.id DESC LIMIT ?',
      [limit],
    );
    final tracks = await _tracks(rows);
    return [
      for (var i = 0; i < rows.length; i++)
        (
          id: rows[i]['eventId'] as int,
          at: DateTime.fromMillisecondsSinceEpoch(rows[i]['eventTime'] as int),
          track: tracks[i],
        ),
    ];
  }

  Future<void> removeEvent(int id) => db.delete('event', where: 'id = ?', whereArgs: [id]);
  Future<void> clearHistory() => db.delete('event');

  Future<Track?> lastPlayed() async {
    final rows = await db.rawQuery(
      'SELECT song.* FROM event e JOIN song ON song.id = e.songId ORDER BY e.timestamp DESC, e.id DESC LIMIT 1',
    );
    return rows.isEmpty ? null : (await _tracks(rows)).first;
  }

  Future<List<({Track track, int plays, int ms})>> mostPlayedSongs(int from, {int? to, int limit = 20, int offset = 0}) async {
    final rows = await db.rawQuery(
      'SELECT song.*, COUNT(e.id) AS plays, SUM(e.playTime) AS ms FROM event e JOIN song ON song.id = e.songId '
      'WHERE e.timestamp > ? AND e.timestamp <= ? GROUP BY song.id ORDER BY ms DESC LIMIT ? OFFSET ?',
      [from, to ?? now(), limit, offset],
    );
    final tracks = await _tracks(rows);
    return [
      for (var i = 0; i < rows.length; i++)
        (track: tracks[i], plays: rows[i]['plays'] as int, ms: (rows[i]['ms'] as int?) ?? 0),
    ];
  }

  Future<List<({Artist artist, int plays, int ms})>> mostPlayedArtists(int from, {int? to, int limit = 20}) async {
    final rows = await db.rawQuery(
      'SELECT a.*, COUNT(e.id) AS plays, SUM(e.playTime) AS ms FROM event e '
      'JOIN song_artist_map m ON m.songId = e.songId JOIN artist a ON a.id = m.artistId '
      'WHERE e.timestamp > ? AND e.timestamp <= ? GROUP BY a.id ORDER BY ms DESC LIMIT ?',
      [from, to ?? now(), limit],
    );
    return [
      for (final r in rows)
        (
          artist: Artist(id: r['id'] as String, name: r['name'] as String, thumbnailUrl: r['thumbnailUrl'] as String?),
          plays: r['plays'] as int,
          ms: (r['ms'] as int?) ?? 0,
        ),
    ];
  }

  /// Albums by listening time. Uses `song.albumId` so it also covers songs
  /// whose album was never saved; artwork falls back to the song's.
  Future<List<({Album album, int plays, int ms})>> mostPlayedAlbums(int from, {int? to, int limit = 20}) async {
    final rows = await db.rawQuery(
      'SELECT song.albumId AS id, COALESCE(album.title, song.albumName) AS title, '
      'COALESCE(album.thumbnailUrl, song.thumbnailUrl) AS thumbnailUrl, album.year AS year, album.playlistId AS playlistId, '
      'COUNT(e.id) AS plays, SUM(e.playTime) AS ms, MIN(song.id) AS anySong '
      'FROM event e JOIN song ON song.id = e.songId LEFT JOIN album ON album.id = song.albumId '
      'WHERE e.timestamp > ? AND e.timestamp <= ? AND song.albumId IS NOT NULL AND song.albumName IS NOT NULL '
      'GROUP BY song.albumId ORDER BY ms DESC LIMIT ?',
      [from, to ?? now(), limit],
    );
    final out = <({Album album, int plays, int ms})>[];
    for (final r in rows) {
      final artists = await db.rawQuery(
        'SELECT a.id, a.name FROM song_artist_map m JOIN artist a ON a.id = m.artistId WHERE m.songId = ? ORDER BY m.position',
        [r['anySong']],
      );
      out.add((
        album: Album(
          id: r['id'] as String,
          title: r['title'] as String,
          artists: [
            for (final a in artists)
              ArtistRef(id: (a['id'] as String).startsWith('LA') ? null : a['id'] as String, name: a['name'] as String),
          ],
          year: r['year'] as int?,
          thumbnailUrl: r['thumbnailUrl'] as String?,
          playlistId: r['playlistId'] as String?,
        ),
        plays: r['plays'] as int,
        ms: (r['ms'] as int?) ?? 0,
      ));
    }
    return out;
  }

  Future<({int plays, int ms})> totals(int from, {int? to}) async {
    final r = (await db.rawQuery(
      'SELECT COUNT(*) AS plays, COALESCE(SUM(playTime), 0) AS ms FROM event WHERE timestamp > ? AND timestamp <= ?',
      [from, to ?? now()],
    )).first;
    return (plays: r['plays'] as int, ms: r['ms'] as int);
  }

  /// Songs loved a while ago but not played in the last month.
  Future<List<Track>> forgottenFavorites({int limit = 30}) async {
    final month = now() - 30 * 86400000;
    return _tracks(
      await db.rawQuery(
        'SELECT song.* FROM song JOIN ('
        '  SELECT songId, SUM(CASE WHEN timestamp < ? THEN playTime ELSE 0 END) AS oldTime, '
        '         SUM(CASE WHEN timestamp >= ? THEN playTime ELSE 0 END) AS newTime FROM event GROUP BY songId'
        ') t ON t.songId = song.id WHERE t.oldTime > 0 AND t.newTime * 5 < t.oldTime ORDER BY t.oldTime DESC LIMIT ?',
        [month, month, limit],
      ),
    );
  }

  // ── Related songs (quick picks) ─────────────────────────────────────────

  Future<bool> hasRelated(String songId) async =>
      (await db.query('related_song_map', where: 'songId = ?', whereArgs: [songId], limit: 1)).isNotEmpty;

  Future<void> setRelated(Track seed, List<Track> related) => db.transaction((txn) async {
    await ensureTrack(seed, txn);
    await txn.delete('related_song_map', where: 'songId = ?', whereArgs: [seed.id]);
    for (final t in related) {
      if (t.id == seed.id) continue;
      await ensureTrack(t, txn);
      await txn.insert('related_song_map', {'songId': seed.id, 'relatedSongId': t.id});
    }
  });

  /// Songs related to what was played recently / most (native `quickPicks`).
  Future<List<Track>> quickPicks({int limit = 100}) async {
    final t = now();
    return _tracks(
      await db.rawQuery(
        'SELECT song.* FROM song JOIN ('
        '  SELECT relatedSongId, COUNT(1) AS referredCount FROM related_song_map WHERE songId IN ('
        '    SELECT songId FROM (SELECT songId FROM event ORDER BY ROWID DESC LIMIT 5) '
        '    UNION SELECT songId FROM (SELECT songId FROM event WHERE timestamp > ? - 86400000 * 7 '
        '                              GROUP BY songId ORDER BY SUM(playTime) DESC LIMIT 5) '
        '    UNION SELECT id FROM (SELECT id FROM song ORDER BY totalPlayTime DESC LIMIT 10)'
        '  ) GROUP BY relatedSongId'
        ') r ON song.id = r.relatedSongId ORDER BY r.referredCount DESC LIMIT ?',
        [t, limit],
      ),
    );
  }

  // ── Search history ───────────────────────────────────────────────────────

  Future<void> addSearch(String query, {String? itemJson}) async {
    // Re-insert so the newest search sorts first.
    await db.delete('search_history', where: 'query = ?', whereArgs: [query]);
    await db.insert('search_history', {'query': query});
    if (itemJson != null) {
      await db.insert('hyde_recent_item', {'query': query, 'json': itemJson}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<({String query, String? json})>> searches({int limit = 30}) async {
    final rows = await db.rawQuery(
      'SELECT h.query, r.json FROM search_history h LEFT JOIN hyde_recent_item r ON r.query = h.query '
      'ORDER BY h.id DESC LIMIT ?',
      [limit],
    );
    return [for (final r in rows) (query: r['query'] as String, json: r['json'] as String?)];
  }

  Future<void> removeSearch(String query) async {
    await db.delete('search_history', where: 'query = ?', whereArgs: [query]);
    await db.delete('hyde_recent_item', where: 'query = ?', whereArgs: [query]);
  }

  Future<void> clearSearches() async {
    await db.delete('search_history');
    await db.delete('hyde_recent_item');
  }

  // ── Lyrics / format cache ────────────────────────────────────────────────

  Future<String?> lyrics(String songId) async {
    final rows = await db.query('lyrics', where: 'id = ?', whereArgs: [songId]);
    return rows.isEmpty ? null : rows.first['lyrics'] as String;
  }

  Future<void> setLyrics(String songId, String? lyrics) async {
    if (lyrics == null) {
      await db.delete('lyrics', where: 'id = ?', whereArgs: [songId]);
    } else {
      await db.insert('lyrics', {'id': songId, 'lyrics': lyrics}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> setFormat(String songId, AudioFormat f, {int contentLength = 0, int itag = 0}) => db.insert('format', {
    'id': songId,
    'itag': itag,
    'mimeType': f.codec == 'AAC' ? 'audio/mp4' : 'audio/webm',
    'codecs': f.codec.toLowerCase(),
    'bitrate': (f.bitrateKbps ?? 0) * 1000,
    'sampleRate': f.sampleRateHz,
    'contentLength': contentLength,
    'loudnessDb': f.loudnessDb,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<AudioFormat?> format(String songId) async {
    final rows = await db.query('format', where: 'id = ?', whereArgs: [songId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final codec = (r['codecs'] as String).split('.').first;
    return AudioFormat(
      codec: codec == 'mp4a' ? 'AAC' : codec.toUpperCase(),
      bitrateKbps: ((r['bitrate'] as int?) ?? 0) ~/ 1000,
      sampleRateHz: r['sampleRate'] as int?,
      loudnessDb: (r['loudnessDb'] as num?)?.toDouble(),
    );
  }

  // ── Downloads ────────────────────────────────────────────────────────────

  Future<String?> downloadPath(String songId) async {
    final rows = await db.query('hyde_download', columns: ['path'], where: 'songId = ?', whereArgs: [songId]);
    return rows.isEmpty ? null : rows.first['path'] as String;
  }

  Future<void> setDownloaded(Track t, String path, int bytes) async {
    await ensureTrack(t);
    await db.transaction((txn) async {
      await txn.insert('hyde_download', {
        'songId': t.id,
        'path': path,
        'bytes': bytes,
        'date': now(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.update('song', {'isDownloaded': 1, 'dateDownload': now()}, where: 'id = ?', whereArgs: [t.id]);
      await txn.delete('hyde_pending_download', where: 'songId = ?', whereArgs: [t.id]);
    });
  }

  Future<void> clearDownloaded(String songId) => db.transaction((txn) async {
    await txn.delete('hyde_download', where: 'songId = ?', whereArgs: [songId]);
    await txn.update('song', {'isDownloaded': 0, 'dateDownload': null}, where: 'id = ?', whereArgs: [songId]);
  });

  Future<int> downloadedBytes() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(SUM(bytes), 0) FROM hyde_download')) ?? 0;

  /// Songs the native app had downloaded (to offer a one-tap re-download).
  Future<List<Track>> pendingDownloads() async => _tracks(
    await db.rawQuery('SELECT song.* FROM hyde_pending_download d JOIN song ON song.id = d.songId'),
  );

  Future<void> clearPendingDownloads() => db.delete('hyde_pending_download');

  // ── Local media ──────────────────────────────────────────────────────────

  Future<void> upsertLocalSong({
    required String id,
    required String title,
    required String path,
    required int durationSec,
    String? artist,
    String? album,
    String? artworkUri,
  }) => db.transaction((txn) async {
    await txn.insert('song', {
      'id': id,
      'title': title,
      'duration': durationSec,
      'thumbnailUrl': artworkUri,
      'albumName': album,
      'explicit': 0,
      'liked': 0,
      'totalPlayTime': 0,
      'inLibrary': now(),
      'isLocal': 1,
      'romanizeLyrics': 1,
      'isDownloaded': 0,
      'isUploaded': 0,
      'localPath': path,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await txn.update('song', {'localPath': path, 'title': title}, where: 'id = ?', whereArgs: [id]);
    if (artist != null && artist.isNotEmpty && artist != '<unknown>') {
      final byName = await txn.query('artist', columns: ['id'], where: 'name = ?', whereArgs: [artist], limit: 1);
      final aid = byName.isEmpty ? _localId('LA') : byName.first['id'] as String;
      await txn.insert('artist', {
        'id': aid,
        'name': artist,
        'lastUpdateTime': now(),
        'isLocal': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('song_artist_map', {
        'songId': id,
        'artistId': aid,
        'position': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  });

  Future<String?> localPath(String songId) async {
    final rows = await db.query('song', columns: ['localPath'], where: 'id = ? AND isLocal = 1', whereArgs: [songId]);
    return rows.isEmpty ? null : rows.first['localPath'] as String?;
  }

  Future<void> removeLocalSongsExcept(Set<String> keepIds) async {
    final rows = await db.query('song', columns: ['id'], where: 'isLocal = 1');
    for (final r in rows) {
      if (!keepIds.contains(r['id'])) await db.delete('song', where: 'id = ?', whereArgs: [r['id']]);
    }
  }

  // ── Accounts (native table; read for migration, written on sign-in) ─────

  Future<Map<String, Object?>?> activeAccount() async {
    final rows = await db.query('account', where: 'isActive = 1', orderBy: 'lastUsedAt DESC', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> accounts() => db.query('account', orderBy: 'lastUsedAt DESC');

  Future<void> saveAccount({
    required String email,
    required String name,
    required String cookie,
    String? handle,
    String? thumbnailUrl,
    String? visitorData,
    String? dataSyncId,
  }) => db.transaction((txn) async {
    await txn.update('account', {'isActive': 0});
    final existing = await txn.query('account', columns: ['id'], where: 'email = ?', whereArgs: [email], limit: 1);
    final values = {
      'name': name,
      'email': email,
      'channelHandle': handle ?? '',
      'thumbnailUrl': thumbnailUrl,
      'innerTubeCookie': cookie,
      'visitorData': visitorData ?? '',
      'dataSyncId': dataSyncId ?? '',
      'isActive': 1,
      'lastUsedAt': now(),
    };
    if (existing.isEmpty) {
      await txn.insert('account', {'id': 'ACC${now()}', 'createdAt': now(), ...values});
    } else {
      await txn.update('account', values, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
  });

  Future<void> setActiveAccount(String? id) => db.transaction((txn) async {
    await txn.update('account', {'isActive': 0});
    if (id != null) await txn.update('account', {'isActive': 1, 'lastUsedAt': now()}, where: 'id = ?', whereArgs: [id]);
  });

  Future<void> removeAccount(String id) => db.delete('account', where: 'id = ?', whereArgs: [id]);
}
