import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_menu.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/glass/glass_toast.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../design/widgets/media_tiles.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import '../library/collection_screens.dart';

/// Search: online (all music) or library source, live **song** suggestions
/// while typing (tap to play), recents with ✕ / Clear All, and results that
/// open on **Songs** (no "All" tab).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

const _filters = [
  (SearchFilter.songs, 'Songs'),
  (SearchFilter.videos, 'Videos'),
  (SearchFilter.albums, 'Albums'),
  (SearchFilter.artists, 'Artists'),
  (SearchFilter.playlists, 'Playlists'),
];

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _requestId = 0;
  List<Track> _suggestions = const [];
  bool _suggesting = false;
  List<MediaItem>? _results;
  bool _searching = false;
  bool _loadingMore = false;
  bool _noMore = false;
  SearchFilter _filter = SearchFilter.songs;

  Future<void> _loadMore() async {
    final results = _results;
    if (results == null || results.isEmpty || _loadingMore || _noMore || _searching || !_online) return;
    final id = _requestId;
    setState(() => _loadingMore = true);
    try {
      final more = await ref.read(engineProvider).searchMore(_controller.text, filter: _filter);
      if (!mounted || id != _requestId) return;
      setState(() {
        _noMore = more.isEmpty;
        _results = [...results, ...more];
      });
    } catch (_) {
      // Paging is best-effort; scrolling to the end again retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _online => (ref.read(settingsProvider).value?['searchSource'] as String? ?? 'ONLINE') == 'ONLINE';

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _suggestions = const [];
        _results = null;
        _suggesting = false;
      });
      return;
    }
    setState(() {
      _results = null;
      _suggesting = true;
    });
    final id = ++_requestId;
    _debounce = Timer(const Duration(milliseconds: 260), () async {
      try {
        final s = await ref.read(engineProvider).searchSuggestions(q.trim());
        if (mounted && id == _requestId) setState(() => _suggestions = s);
      } catch (_) {
        // Suggestions are best-effort; the full search reports errors.
      } finally {
        if (mounted && id == _requestId) setState(() => _suggesting = false);
      }
    });
  }

  Future<void> _submit(String q, {SearchFilter? filter}) async {
    final query = q.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    _focus.unfocus();
    _controller.text = query;
    final f = filter ?? _filter;
    final id = ++_requestId;
    setState(() {
      _filter = f;
      _searching = true;
      _noMore = false;
      _suggestions = const [];
    });
    try {
      final r = await ref.read(engineProvider).search(query, filter: f);
      ref.invalidate(recentSearchesProvider);
      if (mounted && id == _requestId) setState(() => _results = r);
    } catch (e) {
      if (mounted) showGlassToast(context, friendlyError(e));
    } finally {
      if (mounted && id == _requestId) setState(() => _searching = false);
    }
  }

  Future<void> _play(List<Track> tracks, int index) => guarded(
    context,
    () => ref.read(engineProvider).playTracks(tracks, startIndex: index),
    failure: 'Couldn’t play this song',
  );

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) _submit(text);
  }

  void _pickSource(BuildContext anchorContext) {
    final settings = ref.read(settingsProvider.notifier);
    showGlassMenu(
      context,
      anchor: globalRectOf(anchorContext),
      menu: GlassMenu(
        sections: [
          [
            GlassMenuAction(
              icon: CupertinoIcons.globe,
              label: 'All music',
              subtitle: 'Search everything',
              onSelected: () => settings.set('searchSource', 'ONLINE'),
            ),
            GlassMenuAction(
              icon: CupertinoIcons.music_house,
              label: 'Library',
              subtitle: 'Songs you saved or downloaded',
              onSelected: () => settings.set('searchSource', 'LOCAL'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsProvider);
    // A shared link / text or a youtube.com/search link asked for a search.
    ref.listen(pendingSearchProvider, (_, query) {
      if (query == null) return;
      ref.read(pendingSearchProvider.notifier).clear();
      _submit(query);
    });
    final pending = ref.read(pendingSearchProvider);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(pendingSearchProvider.notifier).clear();
        _submit(pending);
      });
    }
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final online = _online;
    final typing = _controller.text.trim().isNotEmpty && _results == null && !_searching;

    return LargeTitleScaffold(
      title: 'Search',
      onEndReached: _loadMore,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: HydeColors.groupedFill.resolveFrom(context),
                shape: StadiumBorder(side: BorderSide(color: HydeColors.separator.resolveFrom(context), width: 0.5)),
              ),
              child: SizedBox(
                height: 46,
                child: Row(
                  children: [
                    Builder(
                      builder: (anchor) => GlassPressable(
                        onTap: () => _pickSource(anchor),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 6),
                          child: Row(
                            children: [
                              Icon(
                                online ? CupertinoIcons.search : CupertinoIcons.music_house,
                                color: secondary,
                                size: 20,
                              ),
                              Icon(CupertinoIcons.chevron_down, color: secondary, size: 11),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: CupertinoTextField.borderless(
                        controller: _controller,
                        focusNode: _focus,
                        placeholder: online ? 'Songs, artists, albums…' : 'Search your library…',
                        placeholderStyle: HydeText.body.copyWith(color: secondary),
                        style: HydeText.body.copyWith(color: HydeColors.label.resolveFrom(context)),
                        cursorColor: HydeColors.accent,
                        onChanged: _onChanged,
                        onSubmitted: _submit,
                        textInputAction: TextInputAction.search,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    if (_controller.text.isNotEmpty)
                      GlassPressable(
                        onTap: () {
                          _controller.clear();
                          _onChanged('');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(CupertinoIcons.xmark_circle_fill, color: secondary, size: 20),
                        ),
                      )
                    else
                      GlassPressable(
                        onTap: _paste,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Icon(CupertinoIcons.doc_on_clipboard, color: secondary, size: 20),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_results != null || _searching)
          ..._buildResults()
        else if (typing)
          ..._buildSuggestions()
        else
          ..._buildRecents(),
      ],
    );
  }

  /// Live songs while typing — tap plays, the keyboard's Search shows all results.
  List<Widget> _buildSuggestions() {
    final q = _controller.text.trim();
    return [
      SliverToBoxAdapter(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _submit(q),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 16, HydeMetrics.gutter, 6),
            child: Row(
              children: [
                const Icon(CupertinoIcons.search, size: 18, color: HydeColors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'See all results for “$q”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HydeText.body.copyWith(color: HydeColors.accent),
                  ),
                ),
                if (_suggesting) const CupertinoActivityIndicator(radius: 8),
              ],
            ),
          ),
        ),
      ),
      SliverList.builder(
        itemCount: _suggestions.length,
        itemBuilder: (context, i) => Builder(
          builder: (rowContext) => MediaRow(
            item: TrackItem(_suggestions[i]),
            onTap: () {
              _focus.unfocus();
              _play([_suggestions[i]], 0);
            },
            onLongPress: () => showSongMenu(context, ref, _suggestions[i], globalRectOf(rowContext)),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildRecents() {
    final recents = ref.watch(recentSearchesProvider).value ?? const [];
    final engine = ref.read(engineProvider);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 22, HydeMetrics.gutter, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Recent',
                  style: HydeText.headline.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
                ),
              ),
              if (recents.isNotEmpty)
                GlassPressable(
                  onTap: () async {
                    await engine.clearRecentSearches();
                    ref.invalidate(recentSearchesProvider);
                  },
                  child: Text('Clear All', style: HydeText.headline.copyWith(color: HydeColors.accent)),
                ),
            ],
          ),
        ),
      ),
      SliverList.builder(
        itemCount: recents.length,
        itemBuilder: (context, i) {
          final r = recents[i];
          final remove = GlassPressable(
            onTap: () async {
              await engine.removeRecentSearch(r.query);
              ref.invalidate(recentSearchesProvider);
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(CupertinoIcons.xmark, size: 17, color: HydeColors.secondaryLabel.resolveFrom(context)),
            ),
          );
          if (r.item == null) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _submit(r.query),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4, vertical: 4),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.clock, size: 18, color: HydeColors.secondaryLabel.resolveFrom(context)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(r.query, style: HydeText.body.copyWith(color: HydeColors.label.resolveFrom(context))),
                    ),
                    remove,
                  ],
                ),
              ),
            );
          }
          return MediaRow(
            item: r.item!,
            showType: true,
            trailing: remove,
            onTap: () => openMediaItem(context, ref, r.item!),
          );
        },
      ),
    ];
  }

  List<Widget> _buildResults() {
    final results = _results ?? const <MediaItem>[];
    final tracks = [
      for (final r in results)
        if (r is TrackItem) r.track,
    ];
    return [
      SliverToBoxAdapter(
        child: SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 12, HydeMetrics.gutter, 6),
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GlassPressable(
                    onTap: () => _submit(_controller.text, filter: f.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: ShapeDecoration(
                        shape: const StadiumBorder(),
                        color: _filter == f.$1 ? HydeColors.accent : HydeColors.groupedFill.resolveFrom(context),
                      ),
                      child: Text(
                        f.$2,
                        style: HydeText.subhead.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _filter == f.$1 ? const Color(0xFFFFFFFF) : HydeColors.label.resolveFrom(context),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      if (_searching)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.only(top: 60), child: CupertinoActivityIndicator()),
        )
      else if (results.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Text(
              'No results',
              textAlign: TextAlign.center,
              style: HydeText.body.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
            ),
          ),
        )
      else
        SliverList.builder(
          itemCount: results.length,
          itemBuilder: (context, i) => _swipe(
            results[i],
            Builder(
              builder: (rowContext) => MediaRow(
                item: results[i],
                showType: _filter != SearchFilter.songs,
                onTap: () => results[i] is TrackItem
                    ? _play(tracks, tracks.indexOf((results[i] as TrackItem).track))
                    : openMediaItem(context, ref, results[i]),
                onLongPress: () => showItemMenu(context, ref, results[i], globalRectOf(rowContext)),
              ),
            ),
          ),
        ),
      if (_loadingMore)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.symmetric(vertical: 20), child: CupertinoActivityIndicator()),
        ),
    ];
  }

  Widget _swipe(MediaItem item, Widget child) => item is TrackItem ? SongSwipe(track: item.track, child: child) : child;
}
