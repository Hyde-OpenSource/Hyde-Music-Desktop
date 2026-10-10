// Live checks against YouTube Music. Not part of the normal test run:
//   flutter test test/live --tags live
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/engine/dart/innertube.dart';
import 'package:hyde_music/engine/dart/youtube.dart';
import 'package:hyde_music/engine/models.dart';

void main() {
  final yt = YouTube(InnerTube());
  String desc(MediaItem i) => '${i.runtimeType}: ${i.title} | ${i.subtitle} | ${i.thumbnailUrl != null}';

  test('home', () async {
    final h = await yt.home();
    print('chips: ${h.chips.map((c) => c.title).join(', ')}  cont=${h.continuation != null}');
    for (final s in h.sections) {
      print('## ${s.title} [${s.style.name}] (${s.items.length}) more=${s.moreBrowseId}');
      for (final i in s.items.take(2)) {
        print('   ${desc(i)}');
      }
    }
    expect(h.sections, isNotEmpty);
    if (h.continuation != null) {
      final more = await yt.home(continuation: h.continuation);
      print('continuation sections: ${more.sections.map((s) => s.title)}');
    }
  });

  test('search', () async {
    for (final f in [
      SearchFilter.songs,
      SearchFilter.albums,
      SearchFilter.artists,
      SearchFilter.playlists,
      SearchFilter.videos,
    ]) {
      final r = await yt.search('arijit singh', f);
      print('-- ${f.name}: ${r.items.length} cont=${r.continuation != null}');
      for (final i in r.items.take(3)) {
        print(
          '   ${desc(i)}${i is TrackItem ? ' ${i.track.duration} album=${i.track.albumName} vid=${i.track.isVideo}' : ''}',
        );
      }
      expect(r.items, isNotEmpty);
    }
    final s = await yt.suggestions('tum hi');
    print('suggest: ${s.queries.take(5)} items=${s.items.map(desc).take(4)}');
  });

  test('album/artist/playlist/next', () async {
    final r = await yt.search('Prateek Kuhad cold mess', SearchFilter.albums);
    final album = (r.items.first as AlbumItem).album;
    final page = await yt.album(album.id);
    print(
      'album ${page.title} ${page.subtitle} | ${page.secondSubtitle} pl=${page.album?.playlistId} tracks=${page.tracks.length}',
    );
    for (final t in page.tracks.take(3)) {
      print('   ${t.title} - ${t.artistLine} ${t.duration}');
    }
    expect(page.tracks, isNotEmpty);

    final artistId = page.album!.artists.first.id!;
    final ap = await yt.artist(artistId);
    print('artist ${ap.artist.name} subs=${ap.subscriberText} shuffle=${ap.shufflePlaylistId} radio=${ap.radioPlaylistId}');
    for (final s in ap.sections) {
      print('   ## ${s.title} (${s.items.length}) ${s.style.name} more=${s.moreBrowseId}');
    }

    final pl = await yt.playlist('RDCLAK5uy_kmPRjHDECIcuVwnKsx2Ng7fyNgFKWNJFs');
    print('playlist ${pl.title} by ${pl.subtitle} | ${pl.secondSubtitle} tracks=${pl.tracks.length}');

    final n = await yt.next(videoId: page.tracks.first.id);
    print(
      'next: ${n.tracks.length} current=${n.currentIndex} lyrics=${n.lyricsBrowseId} related=${n.relatedBrowseId} cont=${n.continuation != null}',
    );
    if (n.lyricsBrowseId != null) {
      final l = await yt.lyrics(n.lyricsBrowseId!, params: n.lyricsParams);
      print('lyrics: ${l?.text.split('\n').take(2)} src=${l?.source}');
    }
    if (n.relatedBrowseId != null) {
      final rel = await yt.related(n.relatedBrowseId!);
      print('related: ${rel.map((s) => '${s.title}(${s.items.length})')}');
    }
    final ex = await yt.explore();
    print('explore: ${ex.sections.map((s) => '${s.title}[${s.style.name}](${s.items.length})')}');
  });
}
