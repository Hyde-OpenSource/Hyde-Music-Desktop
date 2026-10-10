import '../models.dart';
import 'innertube.dart';
import 'yt_parser.dart';

/// Search filter params (innertube/YouTube.kt SearchFilter).
const searchFilterParams = {
  SearchFilter.songs: 'EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D',
  SearchFilter.videos: 'EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D',
  SearchFilter.albums: 'EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D',
  SearchFilter.artists: 'EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D',
  SearchFilter.featuredPlaylists: 'EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D',
  SearchFilter.communityPlaylists: 'EgeKAQQoAEABagoQAxAEEAoQCRAF',
  SearchFilter.playlists: 'EgeKAQQoAEABagoQAxAEEAoQCRAF',
  SearchFilter.podcasts: 'EgWKAQJQAWoQEBAQCRAEEAMQBRAKEBUQEQ%3D%3D',
};

class SearchPage {
  const SearchPage(this.items, this.continuation);
  final List<MediaItem> items;
  final String? continuation;
}

class NextPage {
  const NextPage({
    required this.tracks,
    this.currentIndex,
    this.continuation,
    this.lyricsBrowseId,
    this.lyricsParams,
    this.relatedBrowseId,
    this.playlistId,
    this.params,
  });
  final List<Track> tracks;
  final int? currentIndex;
  final String? continuation;
  final String? lyricsBrowseId;
  final String? lyricsParams;
  final String? relatedBrowseId;

  /// Endpoint to request more with [continuation] (radio / automix).
  final String? playlistId;
  final String? params;
}

class BrowsePage {
  const BrowsePage({required this.title, required this.sections});
  final String? title;
  final List<HomeSection> sections;
}

class AccountInfo {
  const AccountInfo({required this.name, this.email, this.handle, this.thumbnailUrl});
  final String name;
  final String? email;
  final String? handle;
  final String? thumbnailUrl;
}

/// High-level YouTube Music API (port of innertube/YouTube.kt).
class YouTube {
  YouTube(this.tube);
  final InnerTube tube;

  static Map<String, Object?>? _sectionList(Map<String, Object?> res) =>
      Yt.map(res, ['contents', 'singleColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer']) ??
      Yt.map(res, ['contents', 'twoColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer']) ??
      Yt.map(res, ['contents', 'sectionListRenderer']);

  // ── Home / explore ───────────────────────────────────────────────────────

  Future<HomeFeed> home({String? params, String? continuation}) async {
    if (continuation != null) {
      final res = await tube.browse(continuation: continuation);
      final c = Yt.map(res, ['continuationContents', 'sectionListContinuation']);
      return HomeFeed(
        sections: [for (final s in Yt.list(c?['contents'])) ?Yt.section(s)],
        continuation: Yt.continuation(c),
      );
    }
    final res = await tube.browse(browseId: 'FEmusic_home', params: params);
    final list = _sectionList(res);
    return HomeFeed(
      sections: [for (final s in Yt.list(list?['contents'])) ?Yt.section(s)],
      chips: [
        for (final chip in Yt.list(list, ['header', 'chipCloudRenderer', 'chips']))
          if (Yt.text(Yt.dig(chip, ['chipCloudChipRenderer', 'text'])) case final title?)
            HomeChip(
              title: title,
              params: Yt.dig(chip, ['chipCloudChipRenderer', 'navigationEndpoint', 'browseEndpoint', 'params']) as String?,
            ),
      ],
      continuation: Yt.continuation(list),
    );
  }

  /// Any browse page made of shelves (explore, charts, moods, "see all").
  Future<BrowsePage> browse(String browseId, {String? params}) async {
    final res = await tube.browse(browseId: browseId, params: params);
    final list = _sectionList(res);
    final sections = <HomeSection>[for (final s in Yt.list(list?['contents'])) ?Yt.section(s)];
    var cont = Yt.continuation(list);
    var guard = 0;
    while (cont != null && guard++ < 4) {
      final more = await tube.browse(continuation: cont);
      final c = Yt.map(more, ['continuationContents', 'sectionListContinuation']);
      sections.addAll([for (final s in Yt.list(c?['contents'])) ?Yt.section(s)]);
      cont = Yt.continuation(c);
    }
    return BrowsePage(
      title:
          Yt.text(Yt.dig(res, ['header', 'musicHeaderRenderer', 'title'])) ??
          Yt.text(Yt.dig(res, ['header', 'musicImmersiveHeaderRenderer', 'title'])) ??
          Yt.text(Yt.dig(res, ['header', 'musicDetailHeaderRenderer', 'title'])),
      sections: sections,
    );
  }

  Future<BrowsePage> explore() => browse('FEmusic_explore');
  Future<BrowsePage> moodsAndGenres() => browse('FEmusic_moods_and_genres');
  Future<BrowsePage> charts() => browse('FEmusic_charts');

  // ── Search ───────────────────────────────────────────────────────────────

  Future<SearchPage> search(String query, SearchFilter filter, {String? continuation}) async {
    if (continuation != null) {
      final res = await tube.search(continuation: continuation);
      final shelf = Yt.map(res, ['continuationContents', 'musicShelfContinuation']);
      return SearchPage(Yt.items(shelf?['contents']), Yt.continuation(shelf));
    }
    final res = await tube.search(query: query, params: searchFilterParams[filter]);
    final contents = Yt.list(res, [
      'contents',
      'tabbedSearchResultsRenderer',
      'tabs',
      0,
      'tabRenderer',
      'content',
      'sectionListRenderer',
      'contents',
    ]);
    if (filter == SearchFilter.all) {
      final items = <MediaItem>[];
      for (final c in contents) {
        final card = Yt.map(c, ['musicCardShelfRenderer']);
        if (card != null) {
          final top = _cardItem(card);
          if (top != null) items.add(top);
          items.addAll(Yt.items(card['contents']));
        }
        items.addAll(Yt.items(Yt.dig(c, ['musicShelfRenderer', 'contents'])));
      }
      return SearchPage(_dedupe(items), null);
    }
    final shelf = contents.reversed.map((c) => Yt.map(c, ['musicShelfRenderer'])).whereType<Map<String, Object?>>().firstOrNull;
    return SearchPage(Yt.items(shelf?['contents']), Yt.continuation(shelf));
  }

  MediaItem? _cardItem(Map<String, Object?> card) {
    final title = Yt.text(card['title']);
    final nav = Yt.map(card, ['title', 'runs', 0, 'navigationEndpoint']);
    if (title == null || nav == null) return null;
    final fake = <String, Object?>{
      'title': card['title'],
      'subtitle': card['subtitle'],
      'navigationEndpoint': nav,
      'thumbnailRenderer': card['thumbnail'],
    };
    return Yt.twoRow(fake);
  }

  List<MediaItem> _dedupe(List<MediaItem> items) {
    final seen = <String>{};
    return [
      for (final i in items)
        if (seen.add('${i.runtimeType}:${_idOf(i)}')) i,
    ];
  }

  static String _idOf(MediaItem i) => switch (i) {
    TrackItem(:final track) => track.id,
    AlbumItem(:final album) => album.id,
    ArtistItem(:final artist) => artist.id,
    PlaylistItem(:final playlist) => playlist.id,
    BrowseItem(:final browseId) => browseId,
  };

  /// Typed query suggestions and recommended items while typing.
  Future<({List<String> queries, List<MediaItem> items})> suggestions(String input) async {
    final res = await tube.suggestions(input);
    final sections = Yt.list(res['contents']);
    final queries = <String>[];
    final items = <MediaItem>[];
    for (final s in sections) {
      for (final c in Yt.list(s, ['searchSuggestionsSectionRenderer', 'contents'])) {
        final q = Yt.text(Yt.dig(c, ['searchSuggestionRenderer', 'suggestion']));
        if (q != null) queries.add(q);
        final item = Yt.item(c);
        if (item != null) items.add(item);
      }
    }
    return (queries: queries, items: items);
  }

  // ── Album / playlist / artist ───────────────────────────────────────────

  Future<CollectionPage> album(String browseId) async {
    final res = await tube.browse(browseId: browseId);
    final header =
        Yt.map(res, ['contents', 'twoColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents', 0, 'musicResponsiveHeaderRenderer']) ??
        Yt.map(res, ['header', 'musicDetailHeaderRenderer']);
    final title = Yt.text(header?['title']) ?? 'Album';
    final artists = [
      for (final r in Yt.odd(Yt.runs(header?['straplineTextOne'])))
        ArtistRef(id: Yt.browseId(r), name: r['text'] as String),
    ];
    final subtitleRuns = Yt.runs(header?['subtitle']);
    final yearText = subtitleRuns.map((e) => (e['text'] as String).trim()).where(RegExp(r'^\d{4}$').hasMatch).lastOrNull;
    final thumb = Yt.thumbnail(header?['thumbnail']);
    final canonical = Yt.dig(res, ['microformat', 'microformatDataRenderer', 'urlCanonical']) as String?;
    final playlistId = canonical?.contains('list=') ?? false ? canonical!.substring(canonical.lastIndexOf('=') + 1) : null;
    final album = Album(
      id: browseId,
      title: title,
      artists: artists,
      year: yearText == null ? null : int.parse(yearText),
      thumbnailUrl: thumb,
      playlistId: playlistId,
    );
    final secondary = Yt.list(res, ['contents', 'twoColumnBrowseResultsRenderer', 'secondaryContents', 'sectionListRenderer', 'contents']);
    final rows = secondary.isNotEmpty
        ? (Yt.list(secondary.first, ['musicShelfRenderer', 'contents']).isNotEmpty
              ? Yt.list(secondary.first, ['musicShelfRenderer', 'contents'])
              : Yt.list(secondary.first, ['musicPlaylistShelfRenderer', 'contents']))
        : Yt.list(_sectionList(res), ['contents', 0, 'musicShelfRenderer', 'contents']);
    final tracks = <Track>[
      for (final i in Yt.items(rows))
        if (i is TrackItem)
          Track(
            id: i.track.id,
            title: i.track.title,
            artists: i.track.artists.isEmpty ? artists : i.track.artists,
            albumId: browseId,
            albumName: title,
            thumbnailUrl: i.track.thumbnailUrl ?? thumb,
            duration: i.track.duration,
            explicit: i.track.explicit,
            isVideo: i.track.isVideo,
          ),
    ];
    return CollectionPage(
      id: browseId,
      title: title,
      tracks: tracks,
      subtitle: Yt.text(header?['subtitle']),
      secondSubtitle: Yt.text(header?['secondSubtitle']),
      description: Yt.text(Yt.dig(header, ['description', 'musicDescriptionShelfRenderer', 'description'])),
      thumbnailUrl: thumb,
      album: Album(
        id: album.id,
        title: album.title,
        artists: album.artists,
        year: album.year,
        thumbnailUrl: album.thumbnailUrl,
        playlistId: album.playlistId,
        songCount: tracks.length,
      ),
      related: [for (final s in secondary.skip(1)) ?Yt.section(s)],
    );
  }

  Future<CollectionPage> playlist(String playlistId, {int maxPages = 40}) async {
    final browseId = playlistId.startsWith('VL') || playlistId.startsWith('MPSP') ? playlistId : 'VL$playlistId';
    final res = await tube.browse(browseId: browseId, login: true);
    final first = Yt.map(res, ['contents', 'twoColumnBrowseResultsRenderer', 'tabs', 0, 'tabRenderer', 'content', 'sectionListRenderer', 'contents', 0]);
    final header =
        Yt.map(first, ['musicResponsiveHeaderRenderer']) ??
        Yt.map(first, ['musicEditablePlaylistDetailHeaderRenderer', 'header', 'musicResponsiveHeaderRenderer']) ??
        Yt.map(res, ['header', 'musicDetailHeaderRenderer']);
    final editable = Yt.map(first, ['musicEditablePlaylistDetailHeaderRenderer']) != null;
    final title = Yt.text(header?['title']) ?? 'Playlist';
    final thumb = Yt.thumbnail(header?['thumbnail']);
    final secondary = Yt.list(res, ['contents', 'twoColumnBrowseResultsRenderer', 'secondaryContents', 'sectionListRenderer', 'contents']);
    final shelf = secondary.isEmpty
        ? Yt.map(_sectionList(res), ['contents', 1, 'musicPlaylistShelfRenderer'])
        : (Yt.map(secondary.first, ['musicPlaylistShelfRenderer']) ?? Yt.map(secondary.first, ['musicShelfRenderer']));
    final tracks = <Track>[for (final i in Yt.items(shelf?['contents'])) if (i is TrackItem) i.track];
    var cont = Yt.continuation(shelf);
    var pages = 0;
    while (cont != null && pages++ < maxPages) {
      final more = await tube.browse(continuation: cont, login: true);
      final appended = Yt.list(more, ['onResponseReceivedActions', 0, 'appendContinuationItemsAction', 'continuationItems']);
      final shelfCont = Yt.map(more, ['continuationContents', 'musicPlaylistShelfContinuation']);
      final itemsRaw = appended.isNotEmpty ? appended : Yt.list(shelfCont?['contents']);
      final before = tracks.length;
      tracks.addAll([for (final i in Yt.items(itemsRaw)) if (i is TrackItem) i.track]);
      if (tracks.length == before) break;
      cont = appended.isNotEmpty
          ? Yt.continuation({'contents': appended})
          : Yt.continuation(shelfCont);
    }
    final owner = Yt.runs(header?['straplineTextOne']).firstOrNull?['text'] as String?;
    final id = playlistId.startsWith('VL') ? playlistId.substring(2) : playlistId;
    return CollectionPage(
      id: id,
      title: title,
      tracks: tracks,
      subtitle: owner ?? Yt.text(header?['subtitle']),
      secondSubtitle: Yt.text(header?['secondSubtitle']),
      description: Yt.text(Yt.dig(header, ['description', 'musicDescriptionShelfRenderer', 'description'])),
      thumbnailUrl: thumb,
      playlist: Playlist(
        id: id,
        name: title,
        kind: PlaylistKind.online,
        thumbnailUrl: thumb,
        author: owner,
        songCount: tracks.length,
        isEditable: editable,
      ),
      related: [for (final s in secondary.skip(1)) ?Yt.section(s)],
    );
  }

  Future<ArtistPage> artist(String browseId) async {
    final res = await tube.browse(browseId: browseId);
    final header =
        Yt.map(res, ['header', 'musicImmersiveHeaderRenderer']) ??
        Yt.map(res, ['header', 'musicVisualHeaderRenderer']) ??
        Yt.map(res, ['header', 'musicHeaderRenderer']);
    final name = Yt.text(header?['title']) ?? '';
    final thumb = Yt.thumbnail(header?['thumbnail']) ?? Yt.thumbnail(header?['foregroundThumbnail']);
    final sub = Yt.map(header, ['subscriptionButton', 'subscribeButtonRenderer']);
    final sections = <HomeSection>[];
    String? description;
    for (final c in Yt.list(_sectionList(res)?['contents'])) {
      final s = Yt.section(c);
      if (s != null) {
        sections.add(s);
      } else {
        description ??= Yt.text(Yt.dig(c, ['musicDescriptionShelfRenderer', 'description']));
      }
    }
    return ArtistPage(
      artist: Artist(
        id: browseId,
        name: name,
        thumbnailUrl: Yt.hiRes(thumb, 1080),
        channelId: sub?['channelId'] as String?,
        subscribed: sub?['subscribed'] as bool? ?? false,
      ),
      sections: sections,
      description: description ?? Yt.text(header?['description']),
      subscriberText: Yt.text(sub?['subscriberCountText']) ?? Yt.text(sub?['longSubscriberCountText']),
      shufflePlaylistId:
          Yt.dig(header, ['playButton', 'buttonRenderer', 'navigationEndpoint', 'watchEndpoint', 'playlistId']) as String?,
      radioPlaylistId:
          Yt.dig(header, ['startRadioButton', 'buttonRenderer', 'navigationEndpoint', 'watchEndpoint', 'playlistId']) as String?,
    );
  }

  // ── Watch next / radio / lyrics ─────────────────────────────────────────

  Future<NextPage> next({String? videoId, String? playlistId, String? params, String? continuation}) async {
    final res = await tube.next(videoId: videoId, playlistId: playlistId, params: params, continuation: continuation);
    final tabs = Yt.list(res, ['contents', 'singleColumnMusicWatchNextResultsRenderer', 'tabbedRenderer', 'watchNextTabbedResultsRenderer', 'tabs']);
    final panel =
        Yt.map(res, ['continuationContents', 'playlistPanelContinuation']) ??
        Yt.map(tabs.firstOrNull, ['tabRenderer', 'content', 'musicQueueRenderer', 'content', 'playlistPanelRenderer']);
    final contents = Yt.list(panel?['contents']);
    final tracks = <Track>[];
    int? current;
    for (final c in contents) {
      final r =
          Yt.map(c, ['playlistPanelVideoRenderer']) ??
          Yt.map(c, ['playlistPanelVideoWrapperRenderer', 'primaryRenderer', 'playlistPanelVideoRenderer']);
      if (r == null) continue;
      final t = Yt.panelVideo(r);
      if (t == null) continue;
      if (r['selected'] == true) current = tracks.length;
      tracks.add(t);
    }
    String? nextPlaylist = playlistId;
    String? nextParams = params;
    var cont = Yt.continuation(panel);
    // Automix: YouTube ends the panel with a preview of the radio to continue with.
    final automix = Yt.map(contents.lastOrNull, [
      'automixPreviewVideoRenderer',
      'content',
      'automixPlaylistVideoRenderer',
      'navigationEndpoint',
      'watchPlaylistEndpoint',
    ]);
    if (automix != null && continuation == null) {
      nextPlaylist = automix['playlistId'] as String?;
      nextParams = automix['params'] as String?;
      try {
        final mix = await next(playlistId: nextPlaylist, params: nextParams);
        final ids = tracks.map((e) => e.id).toSet();
        tracks.addAll(mix.tracks.where((t) => ids.add(t.id)));
        cont = mix.continuation;
      } catch (_) {}
    }
    Map<String, Object?>? tabEndpoint(int i) => Yt.map(tabs, [i, 'tabRenderer', 'endpoint', 'browseEndpoint']);
    return NextPage(
      tracks: tracks,
      currentIndex: current,
      continuation: cont,
      lyricsBrowseId: tabEndpoint(1)?['browseId'] as String?,
      lyricsParams: tabEndpoint(1)?['params'] as String?,
      relatedBrowseId: tabEndpoint(2)?['browseId'] as String?,
      playlistId: nextPlaylist,
      params: nextParams,
    );
  }

  /// Plain lyrics from YouTube Music's lyrics tab.
  Future<({String text, String? source})?> lyrics(String browseId, {String? params}) async {
    final res = await tube.browse(browseId: browseId, params: params);
    final shelf = Yt.map(_sectionList(res), ['contents', 0, 'musicDescriptionShelfRenderer']);
    final text = Yt.text(shelf?['description']);
    if (text == null || text.trim().isEmpty) return null;
    return (text: text, source: Yt.text(shelf?['footer']));
  }

  /// "Related" tab: songs, albums, artists, playlists like the seed.
  Future<List<HomeSection>> related(String browseId) async {
    final res = await tube.browse(browseId: browseId);
    return [for (final s in Yt.list(res, ['contents', 'sectionListRenderer', 'contents'])) ?Yt.section(s)];
  }

  /// Full metadata for video ids (used by deep links / imports).
  Future<List<Track>> queue(List<String> videoIds) async {
    final out = <Track>[];
    for (var i = 0; i < videoIds.length; i += 1000) {
      final res = await tube.queue(videoIds.sublist(i, (i + 1000).clamp(0, videoIds.length)));
      for (final d in Yt.list(res['queueDatas'])) {
        final r =
            Yt.map(d, ['content', 'playlistPanelVideoRenderer']) ??
            Yt.map(d, ['content', 'playlistPanelVideoWrapperRenderer', 'primaryRenderer', 'playlistPanelVideoRenderer']);
        final t = r == null ? null : Yt.panelVideo(r);
        if (t != null) out.add(t);
      }
    }
    return out;
  }

  // ── Account ──────────────────────────────────────────────────────────────

  Future<AccountInfo?> accountInfo() async {
    final res = await tube.accountMenu();
    final h = Yt.map(res, ['actions', 0, 'openPopupAction', 'popup', 'multiPageMenuRenderer', 'header', 'activeAccountHeaderRenderer']);
    if (h == null) return null;
    return AccountInfo(
      name: Yt.text(h['accountName']) ?? 'Account',
      email: Yt.text(h['email']),
      handle: Yt.text(h['channelHandle']),
      thumbnailUrl: Yt.thumbnail(h['accountPhoto']),
    );
  }

  /// Library pages of the signed-in account (FEmusic_liked_playlists,
  /// FEmusic_library_corpus_track_artists, FEmusic_liked_albums …).
  Future<List<MediaItem>> library(String browseId) async {
    final res = await tube.browse(browseId: browseId, login: true);
    final out = <MediaItem>[];
    for (final c in Yt.list(_sectionList(res)?['contents'])) {
      final grid = Yt.map(c, ['gridRenderer']);
      final shelf = Yt.map(c, ['musicShelfRenderer']);
      out.addAll(Yt.items(grid?['items'] ?? shelf?['contents']));
      var cont = Yt.continuation(grid ?? shelf);
      var guard = 0;
      while (cont != null && guard++ < 20) {
        final more = await tube.browse(continuation: cont, login: true);
        final g = Yt.map(more, ['continuationContents', 'gridContinuation']) ??
            Yt.map(more, ['continuationContents', 'musicShelfContinuation']);
        final appended = Yt.list(more, ['onResponseReceivedActions', 0, 'appendContinuationItemsAction', 'continuationItems']);
        final items = Yt.items(g?['items'] ?? g?['contents'] ?? appended);
        if (items.isEmpty) break;
        out.addAll(items);
        cont = g != null ? Yt.continuation(g) : Yt.continuation({'contents': appended});
      }
    }
    return out;
  }
}
