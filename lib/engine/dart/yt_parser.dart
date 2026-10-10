import '../models.dart';

/// Tolerant parsers for YouTube Music renderers (port of innertube/pages/*).
///
/// YouTube changes positions of runs between layouts, so items are classified
/// by their endpoints / page types rather than by column index wherever possible.
abstract final class Yt {
  // ── JSON helpers ──────────────────────────────────────────────────────────

  /// Walks [path] (String keys / int indices) through nested maps & lists.
  static Object? dig(Object? node, List<Object> path) {
    var cur = node;
    for (final key in path) {
      if (key is String && cur is Map) {
        cur = cur[key];
      } else if (key is int && cur is List) {
        if (key < 0 || key >= cur.length) return null;
        cur = cur[key];
      } else {
        return null;
      }
      if (cur == null) return null;
    }
    return cur;
  }

  static Map<String, Object?>? map(Object? node, [List<Object> path = const []]) {
    final v = path.isEmpty ? node : dig(node, path);
    return v is Map ? v.cast<String, Object?>() : null;
  }

  static List<Object?> list(Object? node, [List<Object> path = const []]) {
    final v = path.isEmpty ? node : dig(node, path);
    return v is List ? v : const [];
  }

  static List<Map<String, Object?>> runs(Object? text) => [
    for (final r in list(text, ['runs']))
      if (r is Map) r.cast<String, Object?>(),
  ];

  static String? text(Object? text) {
    final m = map(text);
    if (m == null) return null;
    if (m['simpleText'] is String) return m['simpleText'] as String;
    final r = runs(m);
    if (r.isEmpty) return null;
    return r.map((e) => e['text'] as String? ?? '').join();
  }

  /// Splits runs on " • " separators.
  static List<List<Map<String, Object?>>> split(List<Map<String, Object?>> runs) {
    final out = <List<Map<String, Object?>>>[[]];
    for (final r in runs) {
      if ((r['text'] as String?)?.trim() == '•') {
        out.add([]);
      } else {
        out.last.add(r);
      }
    }
    return out.where((s) => s.isNotEmpty).toList();
  }

  /// Every other run (drops ", " and " & " joiners).
  static List<Map<String, Object?>> odd(List<Map<String, Object?>> runs) => [
    for (var i = 0; i < runs.length; i += 2) runs[i],
  ];

  static String? browseId(Map<String, Object?>? run) =>
      dig(run, ['navigationEndpoint', 'browseEndpoint', 'browseId']) as String?;

  static String? pageType(Object? endpoint) =>
      dig(endpoint, [
            'browseEndpoint',
            'browseEndpointContextSupportedConfigs',
            'browseEndpointContextMusicConfig',
            'pageType',
          ])
          as String?;

  static String? videoType(Object? endpoint) =>
      dig(endpoint, ['watchEndpoint', 'watchEndpointMusicSupportedConfigs', 'watchEndpointMusicConfig', 'musicVideoType'])
          as String?;

  static String? _runPageType(Map<String, Object?> run) => pageType(run['navigationEndpoint']);

  static bool _isArtistRun(Map<String, Object?> run) {
    final t = _runPageType(run);
    if (t != null) return t == 'MUSIC_PAGE_TYPE_ARTIST' || t == 'MUSIC_PAGE_TYPE_USER_CHANNEL';
    final id = browseId(run);
    return id != null && id.startsWith('UC');
  }

  static bool _isAlbumRun(Map<String, Object?> run) {
    final t = _runPageType(run);
    if (t != null) return t == 'MUSIC_PAGE_TYPE_ALBUM' || t == 'MUSIC_PAGE_TYPE_AUDIOBOOK';
    return browseId(run)?.startsWith('MPRE') ?? false;
  }

  static final _time = RegExp(r'^\d{1,2}(:\d{2}){1,2}$');
  static final _year = RegExp(r'^\d{4}$');

  static Duration parseDuration(String? s) {
    if (s == null || !_time.hasMatch(s.trim())) return Duration.zero;
    final parts = s.trim().split(':').map(int.parse).toList();
    var secs = 0;
    for (final p in parts) {
      secs = secs * 60 + p;
    }
    return Duration(seconds: secs);
  }

  /// Largest thumbnail, upscaled for googleusercontent URLs.
  static String? thumbnail(Object? node) {
    final thumbs =
        list(node, ['musicThumbnailRenderer', 'thumbnail', 'thumbnails']).isNotEmpty
        ? list(node, ['musicThumbnailRenderer', 'thumbnail', 'thumbnails'])
        : list(node, ['thumbnails']).isNotEmpty
        ? list(node, ['thumbnails'])
        : list(node, ['thumbnail', 'thumbnails']).isNotEmpty
        ? list(node, ['thumbnail', 'thumbnails'])
        : list(node, ['croppedSquareThumbnailRenderer', 'thumbnail', 'thumbnails']);
    if (thumbs.isEmpty) return null;
    final url = (thumbs.last as Map)['url'] as String?;
    return hiRes(url);
  }

  static String? hiRes(String? url, [int size = 544]) {
    if (url == null) return null;
    var u = url.startsWith('//') ? 'https:$url' : url;
    if (u.contains('googleusercontent.com') || u.contains('ggpht.com')) {
      u = u.replaceFirst(RegExp(r'=w\d+-h\d+[^&]*$'), '=w$size-h$size-l90-rj');
      u = u.replaceFirst(RegExp(r'=s\d+[^&]*$'), '=s$size');
    }
    return u;
  }

  static bool _explicit(Object? badges) => list(badges).any(
    (b) => dig(b, ['musicInlineBadgeRenderer', 'icon', 'iconType']) == 'MUSIC_EXPLICIT_BADGE',
  );

  static List<ArtistRef> _artistsFrom(List<Map<String, Object?>> runs) => [
    for (final r in runs) ArtistRef(id: browseId(r), name: (r['text'] as String).trim()),
  ];

  static bool _isVideoType(String? t) => t != null && t != 'MUSIC_VIDEO_TYPE_ATV' && t != 'MUSIC_VIDEO_TYPE_PRIVATELY_OWNED_TRACK';

  // ── Items ─────────────────────────────────────────────────────────────────

  /// Any list/card renderer wrapper → item.
  static MediaItem? item(Object? content) {
    final c = map(content);
    if (c == null) return null;
    if (c['musicTwoRowItemRenderer'] != null) return twoRow(map(c['musicTwoRowItemRenderer'])!);
    if (c['musicResponsiveListItemRenderer'] != null) return responsive(map(c['musicResponsiveListItemRenderer'])!);
    if (c['musicMultiRowListItemRenderer'] != null) return multiRow(map(c['musicMultiRowListItemRenderer'])!);
    if (c['musicNavigationButtonRenderer'] != null) return navButton(map(c['musicNavigationButtonRenderer'])!);
    if (c['playlistPanelVideoRenderer'] != null) {
      final t = panelVideo(map(c['playlistPanelVideoRenderer'])!);
      return t == null ? null : TrackItem(t);
    }
    final wrapped = map(c, ['playlistPanelVideoWrapperRenderer', 'primaryRenderer', 'playlistPanelVideoRenderer']);
    if (wrapped != null) {
      final t = panelVideo(wrapped);
      return t == null ? null : TrackItem(t);
    }
    return null;
  }

  static MediaItem? twoRow(Map<String, Object?> r) {
    final title = text(r['title']);
    if (title == null) return null;
    final nav = map(r['navigationEndpoint']);
    final thumb = thumbnail(r['thumbnailRenderer']);
    final subtitleRuns = runs(r['subtitle']);
    final subtitle = text(r['subtitle']);
    final play = map(r, ['thumbnailOverlay', 'musicItemThumbnailOverlayRenderer', 'content', 'musicPlayButtonRenderer', 'playNavigationEndpoint']);

    final watch = map(nav, ['watchEndpoint']);
    if (watch != null && watch['videoId'] != null) {
      var artists = _artistsFrom(subtitleRuns.where(_isArtistRun).toList());
      if (artists.isEmpty) {
        // "Artist • 12M views" / "Song • Artist": take the first linked-or-plain name.
        final segs = split(subtitleRuns);
        final seg = segs.firstWhere((s) => s.any((r) => r['navigationEndpoint'] != null), orElse: () => segs.isEmpty ? const [] : segs.first);
        artists = _artistsFrom(odd(seg));
      }
      final albumRun = subtitleRuns.where(_isAlbumRun).firstOrNull;
      final vt = videoType(nav);
      return TrackItem(
        Track(
          id: watch['videoId'] as String,
          title: title,
          artists: artists,
          albumId: browseId(albumRun),
          albumName: albumRun?['text'] as String?,
          thumbnailUrl: thumb,
          explicit: _explicit(r['subtitleBadges']),
          isVideo: _isVideoType(vt),
        ),
      );
    }

    final id = dig(nav, ['browseEndpoint', 'browseId']) as String?;
    if (id == null) return null;
    final type = pageType(nav);
    switch (type) {
      case 'MUSIC_PAGE_TYPE_ALBUM' || 'MUSIC_PAGE_TYPE_AUDIOBOOK':
        final artists = _artistsFrom(subtitleRuns.where(_isArtistRun).toList());
        final year = subtitleRuns.map((e) => (e['text'] as String).trim()).where(_year.hasMatch).firstOrNull;
        return AlbumItem(
          Album(
            id: id,
            title: title,
            artists: artists.isEmpty && subtitleRuns.length > 2 ? _artistsFrom(odd(subtitleRuns.skip(2).toList())) : artists,
            year: year == null ? null : int.parse(year),
            thumbnailUrl: thumb,
            playlistId: dig(play, ['watchPlaylistEndpoint', 'playlistId']) as String?,
            explicit: _explicit(r['subtitleBadges']),
          ),
        );
      case 'MUSIC_PAGE_TYPE_ARTIST' || 'MUSIC_PAGE_TYPE_USER_CHANNEL' || 'MUSIC_PAGE_TYPE_LIBRARY_ARTIST':
        return ArtistItem(Artist(id: id, name: title, thumbnailUrl: thumb, subtitle: subtitle));
      case 'MUSIC_PAGE_TYPE_PLAYLIST' || 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE':
        return PlaylistItem(
          Playlist(
            id: id.startsWith('VL') ? id.substring(2) : id,
            name: title,
            kind: PlaylistKind.online,
            thumbnailUrl: thumb,
            author: subtitleRuns.lastOrNull?['text'] as String?,
            subtitle: subtitle,
          ),
        );
      case 'MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE':
        final vid = dig(play, ['watchEndpoint', 'videoId']) as String?;
        if (vid == null) return null;
        return TrackItem(
          Track(
            id: vid,
            title: title,
            artists: _artistsFrom(odd(split(subtitleRuns).firstOrNull ?? const [])),
            thumbnailUrl: thumb,
          ),
        );
      default:
        return BrowseItem(title: title, browseId: id, params: dig(nav, ['browseEndpoint', 'params']) as String?, thumbnailUrl: thumb);
    }
  }

  static MediaItem? responsive(Map<String, Object?> r) {
    final cols = [
      for (final c in list(r['flexColumns'])) runs(dig(c, ['musicResponsiveListItemFlexColumnRenderer', 'text'])),
    ];
    if (cols.isEmpty || cols.first.isEmpty) return null;
    final title = cols.first.map((e) => e['text']).join();
    final nav = map(r['navigationEndpoint']);
    final thumb = thumbnail(r['thumbnail']);
    final rest = [for (final c in cols.skip(1)) ...c];
    final secondary = cols.length > 1 ? cols[1] : const <Map<String, Object?>>[];
    final play = map(r, ['overlay', 'musicItemThumbnailOverlayRenderer', 'content', 'musicPlayButtonRenderer', 'playNavigationEndpoint']);
    final videoId =
        dig(r, ['playlistItemData', 'videoId']) as String? ??
        dig(play, ['watchEndpoint', 'videoId']) as String? ??
        dig(nav, ['watchEndpoint', 'videoId']) as String?;

    final type = pageType(nav);
    final isSong = nav == null || nav['watchEndpoint'] != null || nav['watchPlaylistEndpoint'] != null;

    if (isSong && videoId != null) {
      var artists = _artistsFrom(rest.where(_isArtistRun).toList());
      if (artists.isEmpty) {
        final segs = split(secondary);
        if (segs.isNotEmpty) artists = _artistsFrom(odd(segs.first));
      }
      final albumRun = rest.where(_isAlbumRun).firstOrNull;
      final fixed = text(dig(r, ['fixedColumns', 0, 'musicResponsiveListItemFixedColumnRenderer', 'text']));
      final durationText = fixed ?? rest.map((e) => (e['text'] as String).trim()).where(_time.hasMatch).lastOrNull;
      final vt = videoType(play) ?? videoType(nav);
      return TrackItem(
        Track(
          id: videoId,
          title: title,
          artists: artists,
          albumId: browseId(albumRun),
          albumName: albumRun?['text'] as String?,
          thumbnailUrl: thumb,
          duration: parseDuration(durationText),
          explicit: _explicit(r['badges']),
          isVideo: _isVideoType(vt),
        ),
      );
    }

    final id = dig(nav, ['browseEndpoint', 'browseId']) as String?;
    if (id == null) return null;
    final subtitle = secondary.map((e) => e['text']).join();
    switch (type) {
      case 'MUSIC_PAGE_TYPE_ALBUM' || 'MUSIC_PAGE_TYPE_AUDIOBOOK':
        final year = rest.map((e) => (e['text'] as String).trim()).where(_year.hasMatch).firstOrNull;
        var artists = _artistsFrom(rest.where(_isArtistRun).toList());
        if (artists.isEmpty) {
          final segs = split(secondary);
          if (segs.length > 1) artists = _artistsFrom(odd(segs[1]));
        }
        return AlbumItem(
          Album(
            id: id,
            title: title,
            artists: artists,
            year: year == null ? null : int.parse(year),
            thumbnailUrl: thumb,
            playlistId:
                dig(play, ['watchPlaylistEndpoint', 'playlistId']) as String? ??
                dig(play, ['watchEndpoint', 'playlistId']) as String?,
            explicit: _explicit(r['badges']),
          ),
        );
      case 'MUSIC_PAGE_TYPE_ARTIST' || 'MUSIC_PAGE_TYPE_LIBRARY_ARTIST' || 'MUSIC_PAGE_TYPE_USER_CHANNEL':
        final segs = split(secondary);
        return ArtistItem(
          Artist(
            id: id,
            name: title,
            thumbnailUrl: thumb,
            subtitle: segs.isEmpty ? null : segs.last.map((e) => e['text']).join(),
          ),
        );
      case 'MUSIC_PAGE_TYPE_PLAYLIST' || 'MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE':
        final segs = split(secondary);
        return PlaylistItem(
          Playlist(
            id: id.startsWith('VL') ? id.substring(2) : id,
            name: title,
            kind: PlaylistKind.online,
            thumbnailUrl: thumb,
            author: segs.isEmpty ? null : segs.first.map((e) => e['text']).join(),
            subtitle: subtitle,
          ),
        );
      default:
        return null;
    }
  }

  static MediaItem? multiRow(Map<String, Object?> r) {
    final vid = dig(r, ['onTap', 'watchEndpoint', 'videoId']) as String?;
    final title = text(r['title']);
    if (vid == null || title == null) return null;
    final segs = split(runs(r['subtitle']));
    return TrackItem(
      Track(
        id: vid,
        title: title,
        artists: [
          if (r['secondTitle'] != null) ArtistRef(id: null, name: text(r['secondTitle']) ?? ''),
        ],
        thumbnailUrl: thumbnail(r['thumbnail']),
        duration: parseDuration(segs.lastOrNull?.firstOrNull?['text'] as String?),
      ),
    );
  }

  static MediaItem? navButton(Map<String, Object?> r) {
    final title = text(r['buttonText']);
    final id = dig(r, ['clickCommand', 'browseEndpoint', 'browseId']) as String?;
    if (title == null || id == null) return null;
    return BrowseItem(
      title: title,
      browseId: id,
      params: dig(r, ['clickCommand', 'browseEndpoint', 'params']) as String?,
      color: (dig(r, ['solid', 'leftStripeColor']) as num?)?.toInt(),
    );
  }

  static Track? panelVideo(Map<String, Object?> r) {
    final id = r['videoId'] as String?;
    final title = text(r['title']);
    if (id == null || title == null) return null;
    final byline = runs(r['longBylineText']);
    final segs = split(byline);
    var artists = _artistsFrom(byline.where(_isArtistRun).toList());
    if (artists.isEmpty && segs.isNotEmpty) artists = _artistsFrom(odd(segs.first));
    final albumRun = byline.where(_isAlbumRun).firstOrNull;
    final vt = videoType(r['navigationEndpoint']);
    return Track(
      id: id,
      title: title,
      artists: artists,
      albumId: browseId(albumRun),
      albumName: albumRun?['text'] as String?,
      thumbnailUrl: thumbnail(r['thumbnail']),
      duration: parseDuration(text(r['lengthText'])),
      explicit: _explicit(r['badges']),
      isVideo: _isVideoType(vt),
    );
  }

  // ── Sections ─────────────────────────────────────────────────────────────

  static HomeSection? section(Object? content) {
    final c = map(content);
    if (c == null) return null;
    final carousel = map(c['musicCarouselShelfRenderer']) ?? map(c['musicImmersiveCarouselShelfRenderer']);
    if (carousel != null) {
      final header = map(carousel, ['header', 'musicCarouselShelfBasicHeaderRenderer']) ??
          map(carousel, ['header', 'musicImmersiveCarouselShelfBasicHeaderRenderer']);
      final title = text(header?['title']);
      if (title == null) return null;
      final contents = list(carousel['contents']);
      final items = [for (final i in contents) ?item(i)];
      if (items.isEmpty) return null;
      final more = map(header, ['moreContentButton', 'buttonRenderer', 'navigationEndpoint', 'browseEndpoint']);
      final responsiveCount = contents.where((e) => map(e)?['musicResponsiveListItemRenderer'] != null).length;
      final style = items.every((i) => i is BrowseItem)
          ? HomeSectionStyle.moods
          : responsiveCount > contents.length / 2
          ? HomeSectionStyle.quickPicks
          : HomeSectionStyle.carousel;
      return HomeSection(
        title: title,
        label: text(header?['strapline']),
        items: items,
        style: style,
        moreBrowseId: more?['browseId'] as String?,
        moreParams: more?['params'] as String?,
        thumbnailUrl: thumbnail(header?['thumbnail']),
      );
    }
    final shelf = map(c['musicShelfRenderer']);
    if (shelf != null) {
      final items = [for (final i in list(shelf['contents'])) ?item(i)];
      if (items.isEmpty) return null;
      final more = map(shelf, ['title', 'runs', 0, 'navigationEndpoint', 'browseEndpoint']) ??
          map(shelf, ['bottomEndpoint', 'browseEndpoint']);
      return HomeSection(
        title: text(shelf['title']) ?? '',
        items: items,
        style: HomeSectionStyle.quickPicks,
        moreBrowseId: more?['browseId'] as String?,
        moreParams: more?['params'] as String?,
      );
    }
    final grid = map(c['gridRenderer']);
    if (grid != null) {
      final items = [for (final i in list(grid['items'])) ?item(i)];
      if (items.isEmpty) return null;
      return HomeSection(
        title: text(dig(grid, ['header', 'gridHeaderRenderer', 'title'])) ?? '',
        items: items,
        style: items.every((i) => i is BrowseItem) ? HomeSectionStyle.moods : HomeSectionStyle.carousel,
      );
    }
    return null;
  }

  /// Continuation token from a renderer's `continuations` or a trailing
  /// `continuationItemRenderer`.
  static String? continuation(Object? node) {
    final m = map(node);
    if (m == null) return null;
    final c = dig(m, ['continuations', 0, 'nextContinuationData', 'continuation']) ??
        dig(m, ['continuations', 0, 'nextRadioContinuationData', 'continuation']);
    if (c is String) return c;
    for (final key in ['contents', 'items', 'continuationItems']) {
      final l = list(m[key]);
      if (l.isEmpty) continue;
      final token = dig(l.last, ['continuationItemRenderer', 'continuationEndpoint', 'continuationCommand', 'token']);
      if (token is String) return token;
    }
    return null;
  }

  /// Items in a list that may end in a continuationItemRenderer.
  static List<MediaItem> items(Object? list_) => [for (final i in list(list_)) ?item(i)];
}
