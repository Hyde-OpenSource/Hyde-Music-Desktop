import 'models.dart';

/// The contract between the Flutter UI and the Hyde engine.
///
/// The app's implementation is `DartEngine` (lib/engine/dart): playback with
/// just_audio + audio_service, YouTube Music over InnerTube, the song.db
/// library and lyrics — all in Dart. [MockEngine] implements the same
/// contract with demo data for UI work and tests.
///
/// Rule: the UI never talks to anything but this interface.
abstract interface class HydeEngine {
  // ── Playback ────────────────────────────────────────────────────────────
  Stream<PlaybackSnapshot> get playback;
  PlaybackSnapshot get currentPlayback;

  /// [smart] plays the list in AI Shuffle order (flowing, artist-balanced).
  Future<void> playTracks(List<Track> tracks, {int startIndex = 0, bool shuffle = false, bool smart = false});
  Future<void> playPause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  /// [smart] picks AI Shuffle (true) or plain shuffle (false); an already
  /// shuffled queue is re-shuffled in the new order.
  Future<void> setShuffle(bool enabled, {bool? smart});
  Future<void> setRepeat(QueueRepeat mode);
  Future<void> setVolume(double volume);
  Future<void> playNext(List<Track> tracks);
  Future<void> addToQueue(List<Track> tracks);
  Future<void> moveQueueItem(int from, int to);
  Future<void> removeQueueItem(int index);
  Future<void> skipToQueueItem(int index);
  Future<void> startRadio(Track seed);

  /// Plays an album / playlist / artist radio straight from YouTube
  /// (the watch endpoint), without loading its page first.
  Future<void> playOnline({String? playlistId, String? videoId, String? params, bool shuffle = false});

  /// null cancels. [endOfTrack] stops after the current song.
  Future<void> setSleepTimer(Duration? duration, {bool endOfTrack = false});

  // ── Library actions ─────────────────────────────────────────────────────
  Future<void> setLiked(Track track, bool liked);
  Future<void> setInLibrary(Track track, bool inLibrary);
  Future<void> download(List<Track> tracks);
  Future<void> removeDownload(List<Track> tracks);
  Future<void> addToPlaylist(String playlistId, List<Track> tracks);
  Future<Playlist> createPlaylist(String name);
  Future<void> renamePlaylist(String playlistId, String name);
  Future<void> deletePlaylist(String playlistId);
  Future<void> removeFromPlaylist(String playlistId, Track track);
  Future<void> movePlaylistTrack(String playlistId, int from, int to);

  /// Saves an online playlist (with its tracks) into the library.
  Future<Playlist> importPlaylist(CollectionPage page);
  Future<void> setAlbumSaved(CollectionPage album, bool saved);
  Future<void> setArtistFollowed(Artist artist, bool followed);
  Future<String> shareLink(MediaItem item);

  /// Fires after anything in the library changes (likes, playlists,
  /// downloads, history) so lists can refresh.
  Stream<void> get libraryChanged;

  // ── Browse ──────────────────────────────────────────────────────────────
  /// Personal sections (quick picks, keep listening…) followed by the
  /// YouTube Music feed. [chipParams] filters the feed by mood chip.
  Future<HomeFeed> home({bool refresh = false, String? chipParams});

  /// Next page of the YouTube Music feed.
  Future<HomeFeed> homeMore(String continuation);

  /// A shelf page: explore, charts, moods & genres, "see all".
  Future<({String? title, List<HomeSection> sections})> browse(String browseId, {String? params});
  Future<ArtistPage> artist(String artistId);
  Future<CollectionPage> album(String albumId);

  /// Local, auto ("auto:liked"…) or online playlist.
  Future<CollectionPage> playlist(String playlistId);

  Future<List<MediaItem>> search(String query, {SearchFilter filter = SearchFilter.songs});

  /// More results for the last [search] with the same query and filter;
  /// empty when there are none.
  Future<List<MediaItem>> searchMore(String query, {SearchFilter filter = SearchFilter.songs});

  /// Live song suggestions while typing (songs only).
  Future<List<Track>> searchSuggestions(String query);
  Future<List<RecentSearch>> recentSearches();
  Future<void> removeRecentSearch(String query);
  Future<void> clearRecentSearches();

  Future<List<Playlist>> libraryPlaylists();
  Future<List<Artist>> libraryArtists();
  Future<List<Album>> libraryAlbums();
  Future<List<Track>> librarySongs();
  Future<List<MediaItem>> recentlyAdded();
  Future<List<Track>> playlistTracks(String playlistId);

  /// "Suggested songs" for a list: YouTube Music radio for a few of [seeds],
  /// merged round-robin, without anything in [exclude].
  Future<List<Track>> suggestions(List<Track> seeds, {Set<String> exclude = const {}});

  // ── Lyrics ──────────────────────────────────────────────────────────────
  Future<Lyrics> lyrics(Track track);

  // ── Music recognition (Shazam signature, native lib) ───────────────────
  Stream<RecognitionState> recognize();

  Future<void> setPlaybackParameters({required double speed, required double pitch});
  Future<({double speed, double pitch})> playbackParameters();

  // ── Host integration ────────────────────────────────────────────────────
  /// Deep links, widget/shortcut actions, notification taps.
  Stream<NavigationEvent> get navigation;

  /// Named feature calls (history.*, stats, local.*, storage.*, privacy.*,
  /// backup.*, import.*, account.*, discord.*, lastfm.*, lyrics.*, url.open…).
  /// Throws on failure with a user-readable message.
  Future<Object?> feature(String method, [Map<String, Object?> args = const {}]);

  /// Live feature state: maps with a `topic` (local, downloads, spotify…).
  Stream<Map<String, Object?>> get featureEvents;

  /// "equalizer", "defaultLinks", "appSettings", "outputSwitcher".
  Future<void> systemAction(String name);

  /// Persists transient state (queue, position) — called when the app is
  /// backgrounded.
  Future<void> flush();

  /// Android share sheet.
  Future<void> share(String text);

  // ── Updater ─────────────────────────────────────────────────────────────
  Stream<UpdateStatus> get updates;
  Future<UpdateStatus> checkForUpdate({bool manual = true});
  Future<void> downloadUpdate();
  Future<void> installUpdate();
  Future<void> cancelUpdate();
  Future<void> skipUpdate();
  Future<void> setUpdatePrefs({bool? beta, bool? autoDownload, bool? wifiOnly, bool? autoCheck});

  // ── Settings (DataStore "settings" — same keys as the native app) ───────
  Future<Map<String, Object?>> readSettings();
  Future<void> writeSetting(String key, Object? value);
}
