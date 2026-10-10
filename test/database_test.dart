import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/engine/dart/database.dart';
import 'package:hyde_music/engine/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Track track(String id, {String artist = 'Artist', String? artistId, String? album}) => Track(
  id: id,
  title: 'Song $id',
  artists: [ArtistRef(id: artistId, name: artist)],
  albumId: album == null ? null : 'MPREb_$album',
  albumName: album,
  thumbnailUrl: 'https://img/$id',
  duration: const Duration(seconds: 200),
);

void main() {
  sqfliteFfiInit();
  late HydeDatabase db;

  setUp(() async => db = await HydeDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi));
  tearDown(() => db.close());

  test('likes, library and flags', () async {
    final t = track('a', artistId: 'UC1');
    await db.setLiked(t, true);
    expect((await db.likedSongs()).single.id, 'a');
    expect((await db.librarySongs()).single.artists.single.name, 'Artist');
    final decorated = await db.decorate([t, track('b')]);
    expect(decorated[0].liked, isTrue);
    expect(decorated[0].inLibrary, isTrue);
    expect(decorated[1].liked, isFalse);
    await db.setLiked(t, false);
    expect(await db.likedSongs(), isEmpty);
    expect((await db.libraryArtists()).single.name, 'Artist');
  });

  test('playlists: create, add (no duplicates), move, remove', () async {
    final p = await db.createPlaylist('Mix');
    expect(await db.addToPlaylist(p.id, [track('a'), track('b'), track('c'), track('a')]), 3);
    expect(await db.addToPlaylist(p.id, [track('b')]), 0);
    await db.movePlaylistSong(p.id, 2, 0);
    expect((await db.playlistSongs(p.id)).map((t) => t.id), ['c', 'a', 'b']);
    await db.removeFromPlaylist(p.id, 'a');
    expect((await db.playlistSongs(p.id)).map((t) => t.id), ['c', 'b']);
    final listed = (await db.playlists()).single;
    expect(listed.songCount, 2);
    expect(listed.thumbnailUrl, 'https://img/c');
    await db.deletePlaylist(p.id);
    expect(await db.playlists(), isEmpty);
  });

  test('history, stats and quick picks', () async {
    final a = track('a', artistId: 'UC1', album: 'One');
    final b = track('b', artistId: 'UC2', artist: 'Other');
    await db.recordPlay(a, const Duration(minutes: 3));
    await db.recordPlay(a, const Duration(minutes: 2));
    await db.recordPlay(b, const Duration(minutes: 1));
    expect((await db.history()).length, 3);
    final songs = await db.mostPlayedSongs(0);
    expect(songs.first.track.id, 'a');
    expect(songs.first.plays, 2);
    expect((await db.mostPlayedArtists(0)).first.artist.id, 'UC1');
    expect((await db.mostPlayedAlbums(0)).single.album.title, 'One');
    expect((await db.totals(0)).ms, 6 * 60000);
    await db.setRelated(a, [track('r1'), track('r2')]);
    expect((await db.quickPicks()).map((t) => t.id).toSet(), {'r1', 'r2'});
    expect((await db.lastPlayed())!.id, 'b');
  });

  test('albums, searches, lyrics, downloads', () async {
    final album = Album(id: 'MPREb_x', title: 'LP', artists: const [ArtistRef(id: 'UC1', name: 'Artist')]);
    await db.saveAlbum(album, [track('a'), track('b')], bookmarked: true);
    expect((await db.libraryAlbums()).single.artistLine, 'Artist');
    expect((await db.albumSongs('MPREb_x')).length, 2);

    await db.addSearch('one');
    await db.addSearch('two');
    await db.addSearch('one');
    expect((await db.searches()).map((s) => s.query), ['one', 'two']);

    await db.setLyrics('a', '[00:01.00]hi');
    expect(await db.lyrics('a'), '[00:01.00]hi');

    await db.setDownloaded(track('a'), '/x/a.webm', 10);
    expect((await db.downloadedSongs()).single.isDownloaded, isTrue);
    await db.clearDownloaded('a');
    expect(await db.downloadedSongs(), isEmpty);
    expect((await db.searchSongs('song')).length, 0);
  });

  test('opens a native 4.x database and remembers its downloads', () async {
    // Schema as left by Room v25 (no localPath, no user_action), on a real file.
    final path = '${(await databaseFactoryFfi.getDatabasesPath())}/hyde_migration_test.db';
    await databaseFactoryFfi.deleteDatabase(path);
    final file = await databaseFactoryFfi.openDatabase(path);
    await file.execute(
      'CREATE TABLE `song` (`id` TEXT NOT NULL, `title` TEXT NOT NULL, `duration` INTEGER NOT NULL, `thumbnailUrl` TEXT, `albumId` TEXT, `albumName` TEXT, `explicit` INTEGER NOT NULL DEFAULT 0, `year` INTEGER, `date` INTEGER, `dateModified` INTEGER, `liked` INTEGER NOT NULL, `likedDate` INTEGER, `totalPlayTime` INTEGER NOT NULL, `inLibrary` INTEGER, `dateDownload` INTEGER, `isLocal` INTEGER NOT NULL DEFAULT false, `libraryAddToken` TEXT, `libraryRemoveToken` TEXT, `romanizeLyrics` INTEGER NOT NULL DEFAULT true, `isDownloaded` INTEGER NOT NULL DEFAULT 0, `isUploaded` INTEGER NOT NULL DEFAULT false, PRIMARY KEY(`id`))',
    );
    await file.insert('song', {'id': 'old', 'title': 'Old', 'duration': 100, 'liked': 1, 'totalPlayTime': 5, 'isDownloaded': 1, 'inLibrary': 1});
    await file.close();

    final migrated = await HydeDatabase.open(path: path, factory: databaseFactoryFfi);
    expect((await migrated.likedSongs()).single.title, 'Old');
    expect((await migrated.pendingDownloads()).single.id, 'old');
    expect(await migrated.downloadedSongs(), isEmpty);
    await migrated.close();
    // Second open must not re-queue anything.
    final again = await HydeDatabase.open(path: path, factory: databaseFactoryFfi);
    await again.clearPendingDownloads();
    await again.close();
    final third = await HydeDatabase.open(path: path, factory: databaseFactoryFfi);
    expect(await third.pendingDownloads(), isEmpty);
    await third.close();
    await databaseFactoryFfi.deleteDatabase(path);
  });
}
