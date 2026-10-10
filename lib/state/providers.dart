import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/hyde_engine.dart';
import '../engine/mock_engine.dart';
import '../engine/models.dart';

/// Overridden in main.dart with the real engine for the platform.
final engineProvider = Provider<HydeEngine>((ref) => MockEngine());

final playbackProvider = StreamProvider<PlaybackSnapshot>((ref) async* {
  final engine = ref.watch(engineProvider);
  yield engine.currentPlayback;
  yield* engine.playback;
});

/// Current snapshot without the AsyncValue wrapper.
final nowPlayingProvider = Provider<PlaybackSnapshot>((ref) {
  return ref.watch(playbackProvider).value ?? ref.watch(engineProvider).currentPlayback;
});

/// Bumps whenever the library changes (likes, playlists, downloads, history);
/// every library list watches it, so nothing needs manual invalidation.
final libraryRevisionProvider = StreamProvider<int>((ref) async* {
  var revision = 0;
  yield revision;
  await for (final _ in ref.watch(engineProvider).libraryChanged) {
    yield ++revision;
  }
});

/// Home feed state: personal sections + YouTube Music shelves, the selected
/// mood chip and "load more" paging.
class HomeState {
  const HomeState({required this.feed, this.chip, this.loadingMore = false});
  final HomeFeed feed;

  /// Selected mood chip (null = the default feed).
  final HomeChip? chip;
  final bool loadingMore;

  HomeState copyWith({HomeFeed? feed, bool? loadingMore}) =>
      HomeState(feed: feed ?? this.feed, chip: chip, loadingMore: loadingMore ?? this.loadingMore);
}

class HomeNotifier extends AsyncNotifier<HomeState> {
  /// Chips of the default feed, kept while a chip is selected.
  List<HomeChip> _chips = const [];

  @override
  Future<HomeState> build() async {
    final feed = await ref.watch(engineProvider).home();
    _chips = feed.chips;
    return HomeState(feed: feed);
  }

  Future<void> refresh() async {
    final chip = state.value?.chip;
    final feed = await ref.read(engineProvider).home(refresh: true, chipParams: chip?.params);
    if (chip == null) _chips = feed.chips;
    state = AsyncData(HomeState(feed: _withChips(feed), chip: chip));
  }

  HomeFeed _withChips(HomeFeed feed) =>
      HomeFeed(sections: feed.sections, chips: _chips, continuation: feed.continuation);

  /// Selects a mood chip, or the default feed when [chip] is null / tapped again.
  Future<void> selectChip(HomeChip? chip) async {
    final current = state.value;
    final next = current?.chip?.title == chip?.title ? null : chip;
    if (current != null) state = AsyncData(HomeState(feed: _withChips(const HomeFeed(sections: [])), chip: next, loadingMore: true));
    state = await AsyncValue.guard(() async {
      final feed = await ref.read(engineProvider).home(chipParams: next?.params);
      if (next == null) _chips = feed.chips;
      return HomeState(feed: _withChips(feed), chip: next);
    });
  }

  Future<void> loadMore() async {
    final s = state.value;
    final continuation = s?.feed.continuation;
    if (s == null || continuation == null || s.loadingMore) return;
    state = AsyncData(s.copyWith(loadingMore: true));
    try {
      final more = await ref.read(engineProvider).homeMore(continuation);
      final titles = s.feed.sections.map((e) => e.title).toSet();
      state = AsyncData(
        HomeState(
          chip: s.chip,
          feed: HomeFeed(
            sections: [...s.feed.sections, ...more.sections.where((e) => titles.add(e.title))],
            chips: s.feed.chips,
            continuation: more.continuation,
          ),
        ),
      );
    } catch (_) {
      // Keep what we have; the next scroll to the end retries.
      state = AsyncData(s.copyWith(loadingMore: false));
    }
  }
}

final homeProvider = AsyncNotifierProvider<HomeNotifier, HomeState>(HomeNotifier.new);

/// Lyrics of a track in the current queue, keyed by id (Track instances are
/// replaced whenever a flag changes, which must not refetch lyrics).
final lyricsProvider = FutureProvider.family<Lyrics, String>((ref, id) async {
  final engine = ref.watch(engineProvider);
  final s = engine.currentPlayback;
  final track = s.track?.id == id ? s.track : s.queue.where((t) => t.id == id).firstOrNull;
  return track == null ? Lyrics.empty : engine.lyrics(track);
});

final libraryPlaylistsProvider = FutureProvider((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(engineProvider).libraryPlaylists();
});
final libraryArtistsProvider = FutureProvider((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(engineProvider).libraryArtists();
});
final libraryAlbumsProvider = FutureProvider((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(engineProvider).libraryAlbums();
});
final librarySongsProvider = FutureProvider((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(engineProvider).librarySongs();
});
final recentlyAddedProvider = FutureProvider((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(engineProvider).recentlyAdded();
});
final recentSearchesProvider = FutureProvider((ref) => ref.watch(engineProvider).recentSearches());

/// Detail pages. Local playlists re-read when the library changes.
final artistPageProvider = FutureProvider.autoDispose.family<ArtistPage, String>(
  (ref, id) => ref.watch(engineProvider).artist(id),
);
final albumPageProvider = FutureProvider.autoDispose.family<CollectionPage, String>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(engineProvider).album(id);
});
final playlistPageProvider = FutureProvider.autoDispose.family<CollectionPage, String>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(engineProvider).playlist(id);
});
final browsePageProvider = FutureProvider.autoDispose
    .family<({String? title, List<HomeSection> sections}), (String browseId, String? params)>(
      (ref, key) => ref.watch(engineProvider).browse(key.$1, params: key.$2),
    );

/// Settings values keyed by the native DataStore key names
/// (constants/PreferenceKeys.kt), so the existing user's settings carry over.
class SettingsNotifier extends AsyncNotifier<Map<String, Object?>> {
  @override
  Future<Map<String, Object?>> build() => ref.watch(engineProvider).readSettings();

  Future<void> set(String key, Object? value) async {
    final current = {...?state.value, key: value};
    state = AsyncData(current);
    await ref.read(engineProvider).writeSetting(key, value);
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, Map<String, Object?>>(SettingsNotifier.new);

/// Tab shown at launch (`defaultOpenTab`): 0 Home, 1 Library, 2 Find, 3 Search.
/// Overridden in main.dart once settings are loaded.
final initialTabProvider = Provider<int>((ref) => 0);

/// A query the Search tab should run (shared text, youtube.com/search links).
class PendingSearch extends Notifier<String?> {
  @override
  String? build() => null;
  void request(String query) => state = query;
  void clear() => state = null;
}

final pendingSearchProvider = NotifierProvider<PendingSearch, String?>(PendingSearch.new);

/// In-app navigation requests (e.g. "Go to Album" from the player), handled by
/// the shell exactly like host navigation events.
final appNavigationProvider = Provider<StreamController<NavigationEvent>>((ref) {
  final c = StreamController<NavigationEvent>.broadcast();
  ref.onDispose(c.close);
  return c;
});

/// Latest live state for a feature topic (downloads, local, spotify…).
final featureStateProvider = StreamProvider.family<Map<String, Object?>, String>((ref, topic) {
  final engine = ref.watch(engineProvider);
  final controller = StreamController<Map<String, Object?>>();
  final sub = engine.featureEvents.where((e) => e['topic'] == topic).listen(controller.add);
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  // Ask for the current state so a screen opened later doesn't wait for the next change.
  engine.feature('state', {'topic': topic}).then<void>((_) {}).catchError((_) {});
  return controller.stream;
});

/// One-shot feature query, e.g. `ref.watch(featureQueryProvider(('stats', {'period': 'month'})))`.
final featureQueryProvider = FutureProvider.family<Object?, (String, Map<String, Object?>)>((ref, q) {
  return ref.watch(engineProvider).feature(q.$1, q.$2);
});
