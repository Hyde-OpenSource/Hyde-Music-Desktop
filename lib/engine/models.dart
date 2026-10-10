import 'package:flutter/foundation.dart';

/// Plain data mirrored from the Kotlin engine (Room entities / innertube
/// items). Field names follow the `song`, `album`, `artist`, `playlist` tables
/// of song.db so the bridge is a 1:1 mapping (docs/05_DATA_MIGRATION.md).

@immutable
class ArtistRef {
  const ArtistRef({required this.id, required this.name});
  final String? id;
  final String name;
}

@immutable
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artists,
    this.albumId,
    this.albumName,
    this.thumbnailUrl,
    this.duration = Duration.zero,
    this.explicit = false,
    this.liked = false,
    this.inLibrary = false,
    this.isDownloaded = false,
    this.isLocal = false,
    this.isVideo = false,
  });

  final String id;
  final String title;
  final List<ArtistRef> artists;
  final String? albumId;
  final String? albumName;
  final String? thumbnailUrl;
  final Duration duration;
  final bool explicit;
  final bool liked;
  final bool inLibrary;
  final bool isDownloaded;
  final bool isLocal;
  final bool isVideo;

  String get artistLine => artists.map((a) => a.name).join(', ');

  Track copyWith({bool? liked, bool? inLibrary, bool? isDownloaded}) => Track(
    id: id,
    title: title,
    artists: artists,
    albumId: albumId,
    albumName: albumName,
    thumbnailUrl: thumbnailUrl,
    duration: duration,
    explicit: explicit,
    liked: liked ?? this.liked,
    inLibrary: inLibrary ?? this.inLibrary,
    isDownloaded: isDownloaded ?? this.isDownloaded,
    isLocal: isLocal,
    isVideo: isVideo,
  );
}

@immutable
class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artists,
    this.year,
    this.thumbnailUrl,
    this.songCount = 0,
    this.playlistId,
    this.explicit = false,
    this.inLibrary = false,
  });
  final String id;
  final String title;
  final List<ArtistRef> artists;
  final int? year;
  final String? thumbnailUrl;
  final int songCount;

  /// OLAK5uy_… playlist that plays the album (YouTube albums only).
  final String? playlistId;
  final bool explicit;
  final bool inLibrary;
  String get artistLine => artists.map((a) => a.name).join(', ');
}

@immutable
class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.subscribed = false,
    this.channelId,
    this.subtitle,
  });
  final String id;
  final String name;
  final String? thumbnailUrl;
  final bool subscribed;
  final String? channelId;

  /// e.g. "1.2M subscribers" in search results.
  final String? subtitle;
}

enum PlaylistKind { local, online, liked, downloaded, top, cached, uploaded }

@immutable
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.kind = PlaylistKind.local,
    this.thumbnailUrl,
    this.songCount = 0,
    this.author,
    this.subtitle,
    this.isEditable = false,
  });
  final String id;
  final String name;
  final PlaylistKind kind;
  final String? thumbnailUrl;
  final int songCount;
  final String? author;

  /// Free text from YouTube ("Playlist • Hyde • 50 songs"); preferred over
  /// [songCount] for online playlists, whose song count isn't known up front.
  final String? subtitle;
  final bool isEditable;

  String get displaySubtitle {
    if (subtitle != null && subtitle!.isNotEmpty) return subtitle!;
    if (kind == PlaylistKind.online || kind == PlaylistKind.uploaded) return author ?? 'Playlist';
    return songCount == 1 ? '1 song' : '$songCount songs';
  }
}

/// Anything that can appear in a carousel or search result.
sealed class MediaItem {
  const MediaItem();
  String get title;
  String get subtitle;
  String? get thumbnailUrl;
}

class TrackItem extends MediaItem {
  const TrackItem(this.track);
  final Track track;
  @override
  String get title => track.title;
  @override
  String get subtitle => track.artistLine;
  @override
  String? get thumbnailUrl => track.thumbnailUrl;
}

class AlbumItem extends MediaItem {
  const AlbumItem(this.album);
  final Album album;
  @override
  String get title => album.title;
  @override
  String get subtitle => album.artistLine;
  @override
  String? get thumbnailUrl => album.thumbnailUrl;
}

class ArtistItem extends MediaItem {
  const ArtistItem(this.artist);
  final Artist artist;
  @override
  String get title => artist.name;
  @override
  String get subtitle => artist.subtitle ?? 'Artist';
  @override
  String? get thumbnailUrl => artist.thumbnailUrl;
}

/// Mood / genre / chart tile that opens a browse page.
class BrowseItem extends MediaItem {
  const BrowseItem({required this.title, required this.browseId, this.params, this.color, this.thumbnailUrl});
  @override
  final String title;
  final String browseId;
  final String? params;

  /// ARGB tile colour for mood & genre buttons.
  final int? color;
  @override
  final String? thumbnailUrl;
  @override
  String get subtitle => '';
}

class PlaylistItem extends MediaItem {
  const PlaylistItem(this.playlist);
  final Playlist playlist;
  @override
  String get title => playlist.name;
  @override
  String get subtitle => playlist.displaySubtitle;
  @override
  String? get thumbnailUrl => playlist.thumbnailUrl;
}

@immutable
class HomeSection {
  const HomeSection({
    required this.title,
    required this.items,
    this.label,
    this.style = HomeSectionStyle.carousel,
    this.moreBrowseId,
    this.moreParams,
    this.thumbnailUrl,
  });
  final String title;
  final String? label;
  final List<MediaItem> items;
  final HomeSectionStyle style;

  /// "See all" target (YouTube browse endpoint), if any.
  final String? moreBrowseId;
  final String? moreParams;

  /// Small artwork shown next to the title ("Similar to <artist>").
  final String? thumbnailUrl;
}

/// carousel: square cards; quickPicks: paged 4-row song columns;
/// grid: big 2-row cards; moods: coloured chips; artists: round artwork.
enum HomeSectionStyle { carousel, quickPicks, chips, wide, moods }

/// A home chip ("Relax", "Workout"…) that re-filters the YouTube feed.
@immutable
class HomeChip {
  const HomeChip({required this.title, this.params});
  final String title;
  final String? params;
}

@immutable
class HomeFeed {
  const HomeFeed({required this.sections, this.chips = const [], this.continuation});
  final List<HomeSection> sections;
  final List<HomeChip> chips;
  final String? continuation;
}

/// Artist page: header + shelves (Top songs, Albums, Singles, Videos, Fans also like…).
@immutable
class ArtistPage {
  const ArtistPage({
    required this.artist,
    required this.sections,
    this.description,
    this.subscriberText,
    this.shufflePlaylistId,
    this.radioPlaylistId,
  });
  final Artist artist;
  final List<HomeSection> sections;
  final String? description;
  final String? subscriberText;
  final String? shufflePlaylistId;
  final String? radioPlaylistId;
}

/// Album or playlist page.
@immutable
class CollectionPage {
  const CollectionPage({
    required this.id,
    required this.title,
    required this.tracks,
    this.subtitle,
    this.secondSubtitle,
    this.description,
    this.thumbnailUrl,
    this.album,
    this.playlist,
    this.related = const [],
    this.saved = false,
  });
  final String id;
  final String title;
  final List<Track> tracks;

  /// "Album • 2024" / owner line.
  final String? subtitle;

  /// "12 songs • 43 minutes".
  final String? secondSubtitle;
  final String? description;
  final String? thumbnailUrl;
  final Album? album;
  final Playlist? playlist;

  /// "More from <artist>", "Other versions".
  final List<HomeSection> related;

  /// Saved in the library (album bookmarked / playlist imported).
  final bool saved;
}

/// Stream format of the playing item (song.db `format` table).
@immutable
class AudioFormat {
  const AudioFormat({required this.codec, this.bitrateKbps, this.sampleRateHz, this.bitDepth, this.loudnessDb});
  final String codec;
  final int? bitrateKbps;
  final int? sampleRateHz;
  final int? bitDepth;
  final double? loudnessDb;

  /// e.g. "OPUS · 160 kbps · 48 kHz" — the label under the scrubber.
  String get label {
    final parts = <String>[codec.toUpperCase()];
    if (bitDepth != null) parts.add('$bitDepth-bit');
    if (bitrateKbps != null && bitDepth == null) parts.add('$bitrateKbps kbps');
    if (sampleRateHz != null) {
      final k = sampleRateHz! / 1000;
      parts.add('${k == k.roundToDouble() ? k.toInt() : k.toStringAsFixed(1)} kHz');
    }
    return parts.join(' · ');
  }
}

enum QueueRepeat { off, all, one }

@immutable
class PlaybackSnapshot {
  const PlaybackSnapshot({
    this.track,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.buffered = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.queueIndex = 0,
    this.shuffle = false,
    this.repeat = QueueRepeat.off,
    this.volume = 1,
    this.format,
    this.sleepTimerEnd,
    this.error,
  });

  final Track? track;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration buffered;
  final Duration duration;
  final List<Track> queue;
  final int queueIndex;
  final bool shuffle;
  final QueueRepeat repeat;
  final double volume;
  final AudioFormat? format;
  final DateTime? sleepTimerEnd;
  final String? error;

  double get progress =>
      duration.inMilliseconds == 0 ? 0 : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  PlaybackSnapshot copyWith({
    Track? track,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? buffered,
    Duration? duration,
    List<Track>? queue,
    int? queueIndex,
    bool? shuffle,
    QueueRepeat? repeat,
    double? volume,
    AudioFormat? format,
    DateTime? sleepTimerEnd,
    bool clearSleepTimer = false,
    String? error,
  }) {
    return PlaybackSnapshot(
      track: track ?? this.track,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      volume: volume ?? this.volume,
      format: format ?? this.format,
      sleepTimerEnd: clearSleepTimer ? null : (sleepTimerEnd ?? this.sleepTimerEnd),
      error: error,
    );
  }
}

@immutable
class LyricWord {
  const LyricWord(this.text, this.start, this.end);
  final String text;
  final Duration start;
  final Duration end;
}

@immutable
class LyricLine {
  const LyricLine({required this.start, required this.text, this.words = const [], this.translation, this.romanized});
  final Duration start;
  final String text;
  final List<LyricWord> words;
  final String? translation;
  final String? romanized;
}

@immutable
class Lyrics {
  const Lyrics({required this.lines, required this.synced, this.provider});
  final List<LyricLine> lines;
  final bool synced;

  /// LRCLIB, KuGou, SimpMusic, BetterLyrics, LyricsPlus, YouTube…
  final String? provider;

  static const empty = Lyrics(lines: [], synced: false);
}

enum SearchFilter { all, songs, videos, albums, artists, playlists, communityPlaylists, featuredPlaylists, podcasts }

@immutable
class RecentSearch {
  const RecentSearch({required this.query, this.item});
  final String query;
  final MediaItem? item;
}

sealed class RecognitionState {
  const RecognitionState();
}

class RecognitionIdle extends RecognitionState {
  const RecognitionIdle();
}

class RecognitionListening extends RecognitionState {
  const RecognitionListening(this.level);

  /// Mic RMS 0..1, drives the pulsing orb.
  final double level;
}

class RecognitionMatched extends RecognitionState {
  const RecognitionMatched(this.track);
  final Track track;
}

class RecognitionFailed extends RecognitionState {
  const RecognitionFailed(this.reason);
  final String reason;
}

/// Event from the host app: deep links, widgets, shortcuts, notifications.
@immutable
class NavigationEvent {
  const NavigationEvent(this.route, [this.args = const {}]);

  /// "tab" (args.tab), "collection" (args.type, args.id), "nowPlaying", "updates".
  final String route;
  final Map<String, Object?> args;
}

enum UpdatePhase { idle, checking, upToDate, available, downloading, ready, installing, failed }

@immutable
class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.name,
    required this.notes,
    required this.size,
    this.publishedAt,
    this.prerelease = false,
    this.verifiedChecksum = false,
    this.url,
  });
  final String version;
  final String name;
  final String notes;
  final int size;
  final String? publishedAt;
  final bool prerelease;
  final bool verifiedChecksum;
  final String? url;
}

@immutable
class UpdateStatus {
  const UpdateStatus({
    required this.phase,
    required this.currentVersion,
    this.release,
    this.bytes = 0,
    this.total = 0,
    this.speed = 0,
    this.error,
    this.lastChecked,
    this.beta = false,
    this.autoDownload = true,
    this.wifiOnly = true,
    this.autoCheck = true,
  });

  final UpdatePhase phase;
  final String currentVersion;
  final UpdateRelease? release;
  final int bytes;
  final int total;

  /// Bytes per second while downloading.
  final int speed;
  final String? error;
  final DateTime? lastChecked;
  final bool beta;
  final bool autoDownload;
  final bool wifiOnly;
  final bool autoCheck;

  double get progress => total <= 0 ? 0 : (bytes / total).clamp(0.0, 1.0);

  static const initial = UpdateStatus(phase: UpdatePhase.idle, currentVersion: '');
}
