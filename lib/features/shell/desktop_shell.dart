import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_style.dart';
import '../../design/glass/liquid_glass.dart';
import '../../design/widgets/artwork.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import '../find/find_screen.dart';
import '../home/home_screen.dart';
import '../library/detail_screens.dart';
import '../library/library_screen.dart';
import '../more/history_screen.dart';
import '../player/artwork_palette.dart';
import '../player/desktop_now_playing.dart';
import '../player/player_bar.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/updates_screen.dart';

/// Sidebar sections; each has its own navigator so its history is kept.
enum _Section {
  home('Home', CupertinoIcons.house, CupertinoIcons.house_fill),
  search('Search', CupertinoIcons.search, CupertinoIcons.search),
  library('Library', CupertinoIcons.rectangle_stack, CupertinoIcons.rectangle_stack_fill),
  find('Recognise', CupertinoIcons.waveform_circle, CupertinoIcons.waveform_circle_fill),
  history('History', CupertinoIcons.clock, CupertinoIcons.clock_fill),
  settings('Settings', CupertinoIcons.gear_alt, CupertinoIcons.gear_alt_fill);

  const _Section(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;

  Widget get root => switch (this) {
    _Section.home => const HomeScreen(),
    _Section.search => const SearchScreen(),
    _Section.library => const LibraryScreen(),
    _Section.find => const FindScreen(),
    _Section.history => const HistoryScreen(),
    _Section.settings => const SettingsScreen(),
  };
}

/// Windows / Linux layout: a Liquid Glass sidebar, the page in the middle,
/// and the player bar floating over the bottom of the page so content
/// scrolls under the glass. Lyrics and the queue open over the page.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> with WidgetsBindingObserver {
  var _section = _Section.home;
  final _navigators = {for (final s in _Section.values) s: GlobalKey<NavigatorState>()};
  final _visited = <_Section>{_Section.home};
  StreamSubscription<NavigationEvent>? _navSub;
  StreamSubscription<NavigationEvent>? _appNavSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _navSub = ref.read(engineProvider).navigation.listen(_onNavigation);
    _appNavSub = ref.read(appNavigationProvider).stream.listen(_onNavigation);
    _devLaunchOptions();
  }

  /// Developer launch options for screenshots and testing:
  /// `HYDE_OPEN=playlist:<id>|album:<id>|artist:<id>`, `HYDE_SEARCH=<query>`,
  /// `HYDE_PANE=lyrics|queue`.
  void _devLaunchOptions() {
    final env = Platform.environment;
    if (env['HYDE_OPEN'] != null || env['HYDE_SEARCH'] != null) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        final open = env['HYDE_OPEN']?.split(':');
        if (open != null && open.length == 2)
          _onNavigation(NavigationEvent('collection', {'type': open[0], 'id': open[1]}));
        final search = env['HYDE_SEARCH'];
        if (search != null) _onNavigation(NavigationEvent('search', {'query': search}));
      });
    }
    final pane = switch (env['HYDE_PANE']) {
      'lyrics' => DesktopPane.lyrics,
      'queue' => DesktopPane.queue,
      _ => null,
    };
    if (pane != null) {
      Future<void>.delayed(const Duration(seconds: 8), () {
        if (mounted) ref.read(desktopPaneProvider.notifier).toggle(pane);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navSub?.cancel();
    _appNavSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save the queue and position before the window closes.
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      ref.read(engineProvider).flush();
    }
  }

  void _onNavigation(NavigationEvent e) {
    switch (e.route) {
      case 'tab':
        _select(switch (e.args['tab']) {
          'library' => _Section.library,
          'find' => _Section.find,
          'search' => _Section.search,
          _ => _Section.home,
        });
      case 'search':
        final query = e.args['query'] as String?;
        if (query != null) ref.read(pendingSearchProvider.notifier).request(query);
        _select(_Section.search);
      case 'collection':
        final id = e.args['id'] as String?;
        if (id == null) return;
        _push(switch (e.args['type']) {
          'album' => AlbumScreen(id: id),
          'artist' => ArtistScreen(id: id),
          _ => PlaylistScreen(id: id),
        });
      case 'nowPlaying':
        ref.read(desktopPaneProvider.notifier).toggle(DesktopPane.lyrics);
      case 'updates':
        _push(const UpdatesScreen());
    }
  }

  void _push(Widget page) {
    ref.read(desktopPaneProvider.notifier).close();
    _navigators[_section]?.currentState?.push(CupertinoPageRoute<void>(builder: (_) => page));
  }

  void _select(_Section s) {
    ref.read(desktopPaneProvider.notifier).close();
    if (s == _section) {
      _navigators[s]?.currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() {
        _section = s;
        _visited.add(s);
      });
    }
  }

  void _search(String query) {
    if (query.trim().isEmpty) return;
    ref.read(pendingSearchProvider.notifier).request(query.trim());
    _select(_Section.search);
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final engine = ref.read(engineProvider);
    final pane = ref.read(desktopPaneProvider.notifier);
    void volume(double delta) => engine.setVolume((ref.read(nowPlayingProvider).volume + delta).clamp(0.0, 1.0));
    return {
      const SingleActivator(LogicalKeyboardKey.space): engine.playPause,
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): engine.playPause,
      const SingleActivator(LogicalKeyboardKey.mediaTrackNext): engine.next,
      const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): engine.previous,
      const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): engine.next,
      const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): engine.previous,
      const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () => volume(0.05),
      const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () => volume(-0.05),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _select(_Section.search),
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): () => pane.toggle(DesktopPane.lyrics),
      const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () => pane.toggle(DesktopPane.queue),
      const SingleActivator(LogicalKeyboardKey.escape): pane.close,
      const SingleActivator(LogicalKeyboardKey.f5): () {
        _select(_Section.home);
        ref.read(homeProvider.notifier).refresh().ignore();
      },
      const SingleActivator(LogicalKeyboardKey.backspace, alt: true): () =>
          _navigators[_section]?.currentState?.maybePop(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
          _navigators[_section]?.currentState?.maybePop(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pane = ref.watch(desktopPaneProvider);
    final hasTrack = ref.watch(nowPlayingProvider.select((s) => s.track != null));

    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Focus(
        autofocus: true,
        child: _Backdrop(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 248,
                  child: _Sidebar(
                    section: _section,
                    onSelect: _select,
                    onSearch: _search,
                    onOpenPlaylist: (p) => _push(PlaylistScreen(id: p.id)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Stack(
                      children: [
                        ColoredBox(
                          color: HydeColors.background.resolveFrom(context),
                          child: IndexedStack(
                            index: _section.index,
                            children: [
                              for (final s in _Section.values)
                                // Sections are built the first time they're opened.
                                _visited.contains(s)
                                    ? CupertinoTabView(navigatorKey: _navigators[s], builder: (_) => s.root)
                                    : const SizedBox.shrink(),
                            ],
                          ),
                        ),
                        Positioned.fill(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 320),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, a) => FadeTransition(
                              opacity: a,
                              child: SlideTransition(
                                position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a),
                                child: child,
                              ),
                            ),
                            child: pane == DesktopPane.none || !hasTrack
                                ? const SizedBox.shrink(key: ValueKey('none'))
                                : DesktopNowPlaying(key: const ValueKey('pane'), pane: pane),
                          ),
                        ),
                        const Positioned(left: 12, right: 12, bottom: 12, child: PlayerBar()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Window background: the current artwork's colours, softly, so the glass
/// sidebar has something to refract.
class _Backdrop extends ConsumerWidget {
  const _Backdrop({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(nowPlayingProvider.select((s) => s.track?.thumbnailUrl));
    final palette = ref.watch(artworkPaletteProvider(url)).value ?? ArtworkPalette.fallback;
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final base = dark ? const Color(0xFF0B0B0D) : const Color(0xFFF1F1F4);
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: Color.lerp(base, palette.top, dark ? 0.55 : 0.35)),
      duration: const Duration(milliseconds: 900),
      builder: (context, tint, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(center: const Alignment(-0.9, -1), radius: 1.6, colors: [tint!, base]),
        ),
        child: child,
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.section, required this.onSelect, required this.onSearch, required this.onOpenPlaylist});
  final _Section section;
  final ValueChanged<_Section> onSelect;
  final ValueChanged<String> onSearch;
  final ValueChanged<Playlist> onOpenPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(libraryPlaylistsProvider).value ?? const <Playlist>[];
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    return LiquidGlass(
      style: GlassStyle.bar,
      radius: 26,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/hyde_logo.png', width: 30, height: 30),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Hyde Music',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HydeText.title3.copyWith(color: HydeColors.label.resolveFrom(context)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CupertinoSearchTextField(
              placeholder: 'Search',
              onSubmitted: onSearch,
              style: HydeText.subhead.copyWith(color: HydeColors.label.resolveFrom(context)),
            ),
            const SizedBox(height: 14),
            for (final s in [_Section.home, _Section.search, _Section.library, _Section.find])
              _NavItem(section: s, selected: s == section, onTap: () => onSelect(s)),
            const SizedBox(height: 18),
            if (playlists.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Text('PLAYLISTS', style: HydeText.caption.copyWith(color: secondary, letterSpacing: 0.8)),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: playlists.length,
                  itemBuilder: (context, i) =>
                      _PlaylistItem(playlist: playlists[i], onTap: () => onOpenPlaylist(playlists[i])),
                ),
              ),
            ] else
              const Spacer(),
            const SizedBox(height: 8),
            for (final s in [_Section.history, _Section.settings])
              _NavItem(section: s, selected: s == section, onTap: () => onSelect(s)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.section, required this.selected, required this.onTap});
  final _Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final label = HydeColors.label.resolveFrom(context);
    final on = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          selected: on,
          label: widget.section.label,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: ShapeDecoration(
              shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(12)),
              color: on
                  ? label.withValues(alpha: 0.12)
                  : _hover
                  ? label.withValues(alpha: 0.06)
                  : const Color(0x00000000),
            ),
            child: Row(
              children: [
                Icon(
                  on ? widget.section.activeIcon : widget.section.icon,
                  size: 19,
                  color: on ? HydeColors.accent : label.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HydeText.subhead.copyWith(fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: label),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistItem extends StatefulWidget {
  const _PlaylistItem({required this.playlist, required this.onTap});
  final Playlist playlist;
  final VoidCallback onTap;

  @override
  State<_PlaylistItem> createState() => _PlaylistItemState();
}

class _PlaylistItemState extends State<_PlaylistItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final label = HydeColors.label.resolveFrom(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: ShapeDecoration(
            shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(10)),
            color: _hover ? label.withValues(alpha: 0.06) : const Color(0x00000000),
          ),
          child: Row(
            children: [
              Artwork(
                url: widget.playlist.thumbnailUrl,
                size: 32,
                radius: 6,
                placeholderIcon: CupertinoIcons.music_note_list,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HydeText.footnote.copyWith(fontSize: 13.5, color: label.withValues(alpha: 0.9)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
