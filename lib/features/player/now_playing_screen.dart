import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/hyde_motion.dart';
import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_menu.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/glass/glass_style.dart';
import '../../design/glass/liquid_glass.dart';
import '../../design/widgets/artwork.dart';
import '../../design/widgets/elastic_slider.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import 'artwork_palette.dart';
import 'lyrics_view.dart';
import 'player_actions.dart';
import 'queue_view.dart';

enum PlayerPane { artwork, lyrics, queue }

/// Slide-up route for the full player with interactive drag-to-dismiss.
class NowPlayingRoute extends PageRoute<void> {
  NowPlayingRoute({this.initialPane = PlayerPane.artwork});
  final PlayerPane initialPane;

  @override
  bool get opaque => false;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;
  @override
  bool get maintainState => true;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 460);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 380);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      NowPlayingScreen(initialPane: initialPane);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
      child: child,
    );
  }
}

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key, this.initialPane = PlayerPane.artwork});
  final PlayerPane initialPane;

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> with TickerProviderStateMixin {
  late PlayerPane _pane = widget.initialPane;
  late final AnimationController _compact = AnimationController.unbounded(
    vsync: this,
    value: widget.initialPane == PlayerPane.artwork ? 0 : 1,
  );
  late final AnimationController _drag = AnimationController.unbounded(vsync: this);
  double? _seekPreview;

  @override
  void dispose() {
    _compact.dispose();
    _drag.dispose();
    super.dispose();
  }

  void _setPane(PlayerPane p) {
    final next = _pane == p ? PlayerPane.artwork : p;
    setState(() => _pane = next);
    springTo(_compact, next == PlayerPane.artwork ? 0 : 1, HydeSprings.smooth);
  }

  void _onDragUpdate(DragUpdateDetails d) => _drag.value = math.max(0, _drag.value + d.delta.dy);

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_drag.value > 140 || v > 900) {
      Navigator.of(context).pop();
    } else {
      springTo(_drag, 0, HydeSprings.bouncy, velocity: v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(nowPlayingProvider);
    final track = s.track;
    final palette = ref.watch(artworkPaletteProvider(track?.thumbnailUrl)).value ?? ArtworkPalette.fallback;
    final mq = MediaQuery.of(context);

    return AnimatedBuilder(
      animation: _drag,
      builder: (context, child) {
        final dy = _drag.value;
        final radius = math.min(dy / 3, 38.0);
        return Transform.translate(
          offset: Offset(0, dy),
          child: ClipRSuperellipse(borderRadius: BorderRadius.circular(radius), child: child),
        );
      },
      child: GestureDetector(
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: palette.top),
          duration: HydeDurations.slow,
          builder: (context, top, child) => TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: palette.bottom),
            duration: HydeDurations.slow,
            builder: (context, bottom, _) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [top!, bottom!],
                ),
              ),
              child: child,
            ),
            child: child,
          ),
          child: track == null
              ? const SizedBox.expand()
              : Padding(
                  padding: EdgeInsets.only(top: mq.padding.top, bottom: mq.padding.bottom + 8),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      const _Grabber(),
                      Expanded(child: _buildMain(s, track)),
                      _buildControls(s),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  bool _flag(String key, bool fallback) => ref.read(settingsProvider).value?[key] as bool? ?? fallback;

  Widget _buildMain(PlaybackSnapshot s, Track track) {
    return LayoutBuilder(
      builder: (context, c) {
        const side = 26.0;
        final bigSize = math.min(c.maxWidth - side * 2, c.maxHeight - 112);
        final big = Rect.fromLTWH((c.maxWidth - bigSize) / 2, 28, bigSize, bigSize);
        const small = Rect.fromLTWH(side, 18, 68, 68);

        return AnimatedBuilder(
          animation: _compact,
          builder: (context, _) {
            final t = _compact.value;
            final tc = t.clamp(0.0, 1.0);
            final rect = Rect.lerp(big, small, t)!;
            final paused = !s.isPlaying && tc < 0.5;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Pane content (lyrics / queue) under the compact header.
                if (tc > 0.01)
                  Positioned.fill(
                    top: small.bottom + 8,
                    child: Opacity(
                      opacity: Curves.easeIn.transform(tc),
                      child: switch (_pane) {
                        PlayerPane.lyrics => LyricsPane(track: track),
                        PlayerPane.queue => const QueueView(),
                        PlayerPane.artwork => const SizedBox.shrink(),
                      },
                    ),
                  ),
                // Shared artwork: big in artwork mode, small in the header otherwise.
                Positioned.fromRect(
                  rect: rect,
                  child: _ArtworkGestures(
                    enabled: tc < 0.5,
                    onTap: () {
                      if (_flag('tapAlbumArtForLyrics', true)) _setPane(PlayerPane.lyrics);
                    },
                    onNext: () async {
                      if (_flag('swipeThumbnail', true)) await ref.read(engineProvider).next();
                    },
                    onPrevious: () async {
                      if (_flag('swipeThumbnail', true)) await ref.read(engineProvider).previous();
                    },
                    onLike: () async {
                      if (_flag('doubleTapToLike', false)) await ref.read(engineProvider).setLiked(track, !track.liked);
                    },
                    onLongPress: (r) => showPlayerMenu(context, ref, r),
                    child: AnimatedScale(
                      scale: paused ? 0.82 : 1,
                      duration: HydeDurations.slow,
                      curve: paused ? Curves.easeOutCubic : Curves.easeOutBack,
                      child: Hero(
                        tag: 'np-artwork',
                        child: Artwork(url: track.thumbnailUrl, radius: lerpDouble(14, 8, tc)!, shadow: tc < 0.5),
                      ),
                    ),
                  ),
                ),
                // Title row: below the big artwork, or beside the small one.
                Positioned(
                  left: lerpDouble(side, small.right + 16, tc),
                  right: side - 6,
                  top: lerpDouble(big.bottom + 26, small.top + 6, tc),
                  child: _TitleRow(track: track, compact: tc > 0.5, onMenu: (r) => showPlayerMenu(context, ref, r)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildControls(PlaybackSnapshot s) {
    final engine = ref.read(engineProvider);
    final value = _seekPreview ?? s.progress;
    final pos = Duration(milliseconds: (value * s.duration.inMilliseconds).round());
    final remaining = s.duration - pos;
    final label = HydeText.footnote.copyWith(
      color: const Color(0x99FFFFFF),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                s.error!,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: HydeText.footnote.copyWith(color: const Color(0xFFFFB4B4)),
              ),
            ),
          ElasticSlider(
            value: value,
            secondaryValue: s.duration.inMilliseconds == 0 ? 0 : s.buffered.inMilliseconds / s.duration.inMilliseconds,
            onChanged: (v) => setState(() => _seekPreview = v),
            onChangeEnd: (v) {
              engine.seek(Duration(milliseconds: (v * s.duration.inMilliseconds).round()));
              setState(() => _seekPreview = null);
            },
          ),
          Row(
            children: [
              Text(_fmt(pos), style: label),
              Expanded(
                child: s.format == null
                    ? const SizedBox.shrink()
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(CupertinoIcons.waveform, size: 13, color: Color(0x99FFFFFF)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              s.format!.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: label.copyWith(fontSize: 12, letterSpacing: 0.4),
                            ),
                          ),
                        ],
                      ),
              ),
              Text('-${_fmt(remaining)}', style: label),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Transport(icon: CupertinoIcons.backward_fill, size: 44, onTap: engine.previous),
              if (s.isBuffering)
                const SizedBox.square(
                  dimension: 62,
                  child: CupertinoActivityIndicator(radius: 16, color: Color(0xFFFFFFFF)),
                )
              else
                _Transport(
                  icon: s.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                  size: 62,
                  onTap: engine.playPause,
                ),
              _Transport(icon: CupertinoIcons.forward_fill, size: 44, onTap: engine.next),
            ],
          ),
          const SizedBox(height: 26),
          ElasticSlider(
            value: s.volume,
            height: 7,
            activeColor: const Color(0xFFE5E0DA),
            onChanged: engine.setVolume,
            leading: const Icon(CupertinoIcons.speaker_fill, size: 16, color: Color(0x99FFFFFF)),
            trailing: const Icon(CupertinoIcons.speaker_3_fill, size: 18, color: Color(0x99FFFFFF)),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _PaneButton(
                icon: CupertinoIcons.quote_bubble,
                active: _pane == PlayerPane.lyrics,
                onTap: () => _setPane(PlayerPane.lyrics),
              ),
              _PaneButton(
                icon: CupertinoIcons.hifispeaker,
                active: false,
                onTap: () => ref.read(engineProvider).systemAction('outputSwitcher'),
              ),
              _PaneButton(
                icon: CupertinoIcons.list_bullet,
                active: _pane == PlayerPane.queue,
                onTap: () => _setPane(PlayerPane.queue),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).abs().toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();
  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 5,
    decoration: const ShapeDecoration(shape: StadiumBorder(), color: Color(0x66FFFFFF)),
  );
}

class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.track, required this.compact, required this.onMenu});
  final Track track;
  final bool compact;
  final ValueChanged<Rect> onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(engineProvider);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HydeText.title2.copyWith(fontSize: compact ? 20 : 25, color: const Color(0xFFFFFFFF)),
              ),
              const SizedBox(height: 2),
              Text(
                track.artistLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HydeText.title3.copyWith(
                  fontSize: compact ? 17 : 22,
                  fontWeight: FontWeight.w400,
                  color: const Color(0x99FFFFFF),
                ),
              ),
            ],
          ),
        ),
        GlassPressable(
          onTap: () => engine.setLiked(track, !track.liked),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              track.liked ? CupertinoIcons.star_fill : CupertinoIcons.star,
              size: 26,
              color: const Color(0xFFFFFFFF),
            ),
          ),
        ),
        Builder(
          builder: (context) => GlassPressable(
            onTap: () => onMenu(globalRectOf(context)),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(CupertinoIcons.ellipsis, size: 26, color: Color(0xFFFFFFFF)),
            ),
          ),
        ),
      ],
    );
  }
}

class LyricsPane extends ConsumerWidget {
  const LyricsPane({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(track.id));
    final pos = ref.watch(nowPlayingProvider.select((s) => s.position));
    final settings = ref.watch(settingsProvider).value ?? const {};
    final appearance = LyricsAppearance(
      align: switch (settings['lyricsTextPosition']) {
        'CENTER' => TextAlign.center,
        'RIGHT' => TextAlign.right,
        _ => TextAlign.left,
      },
      fontSize: (settings['lyricsTextSize'] as num?)?.toDouble() ?? 32,
      lineSpacing: (settings['lyricsLineSpacing'] as num?)?.toDouble() ?? 1.15,
      blur: settings['appleMusicLyricsBlur'] as bool? ?? true,
      glow: settings['lyricsGlowEffect'] as bool? ?? false,
    );
    return lyrics.when(
      data: (l) => LyricsView(
        lyrics: l,
        position: pos,
        appearance: appearance,
        onSeek: (settings['lyricsClick'] as bool? ?? true) ? ref.read(engineProvider).seek : (_) async {},
      ),
      loading: () => const Center(child: CupertinoActivityIndicator(color: Color(0xFFFFFFFF))),
      error: (e, _) => Center(
        child: Text('Couldn’t load lyrics', style: HydeText.body.copyWith(color: const Color(0x99FFFFFF))),
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.icon, required this.size, required this.onTap});
  final IconData icon;
  final double size;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPressable(
      onTap: onTap,
      pressedScale: 0.86,
      stretch: 0,
      child: SizedBox.square(
        dimension: size + 36,
        child: AnimatedSwitcher(
          duration: HydeDurations.fast,
          transitionBuilder: (c, a) => ScaleTransition(
            scale: a,
            child: FadeTransition(opacity: a, child: c),
          ),
          child: Icon(icon, key: ValueKey(icon), size: size, color: const Color(0xFFFFFFFF)),
        ),
      ),
    );
  }
}

/// Bottom-row pane toggles; the active one sits on a glass disc (reference:
/// lyrics button highlighted).
class _PaneButton extends StatelessWidget {
  const _PaneButton({required this.icon, required this.active, required this.onTap});
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPressable(
      onTap: onTap,
      pressedScale: 1.12,
      builder: (context, p, child) => TweenAnimationBuilder<double>(
        tween: Tween(end: active ? 1 : 0),
        duration: HydeDurations.medium,
        builder: (context, a, _) => LiquidGlass.capsule(
          style: GlassStyle.clear.copyWith(tint: const Color(0xFFFFFFFF), tintStrength: 0.14),
          opacity: math.max(a, p.clamp(0.0, 1.0)),
          child: child,
        ),
      ),
      child: SizedBox.square(dimension: 56, child: Icon(icon, size: 27, color: const Color(0xFFFFFFFF))),
    );
  }
}

/// Artwork gestures (native: swipeThumbnail, doubleTapToLike):
/// drag sideways to skip (the cover follows the finger and flies off),
/// double-tap to like with a heart burst, long-press for the menu.
class _ArtworkGestures extends StatefulWidget {
  const _ArtworkGestures({
    required this.child,
    required this.enabled,
    required this.onTap,
    required this.onNext,
    required this.onPrevious,
    required this.onLike,
    required this.onLongPress,
  });

  final Widget child;
  final bool enabled;
  final VoidCallback onTap;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onLike;
  final ValueChanged<Rect> onLongPress;

  @override
  State<_ArtworkGestures> createState() => _ArtworkGesturesState();
}

class _ArtworkGesturesState extends State<_ArtworkGestures> with TickerProviderStateMixin {
  late final AnimationController _dx = AnimationController.unbounded(vsync: this);
  late final AnimationController _heart = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
  double _width = 1;

  @override
  void dispose() {
    _dx.dispose();
    _heart.dispose();
    super.dispose();
  }

  Future<void> _end(DragEndDetails d) async {
    final v = d.primaryVelocity ?? 0;
    final x = _dx.value;
    final skip = x.abs() > _width * 0.28 || v.abs() > 900;
    if (!skip) {
      springTo(_dx, 0, HydeSprings.bouncy, velocity: v);
      return;
    }
    HapticFeedback.mediumImpact();
    final dir = (x != 0 ? x : v).sign;
    await springTo(_dx, dir * _width * 1.3, HydeSprings.snappy, velocity: v).orCancel.catchError((_) {});
    await (dir < 0 ? widget.onNext() : widget.onPrevious());
    _dx.value = -dir * _width * 0.6;
    springTo(_dx, 0, HydeSprings.bouncy);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _width = c.maxWidth;
        return GestureDetector(
          onTap: widget.onTap,
          onDoubleTap: widget.enabled
              ? () {
                  HapticFeedback.lightImpact();
                  widget.onLike();
                  _heart.forward(from: 0);
                }
              : null,
          onLongPress: widget.enabled ? () => widget.onLongPress(globalRectOf(context)) : null,
          onHorizontalDragUpdate: widget.enabled ? (d) => _dx.value += d.delta.dx : null,
          onHorizontalDragEnd: widget.enabled ? _end : null,
          child: AnimatedBuilder(
            animation: Listenable.merge([_dx, _heart]),
            builder: (context, child) {
              final x = _dx.value;
              final h = _heart.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Transform.translate(
                    offset: Offset(x, 0),
                    child: Transform.rotate(angle: x / _width * 0.12, child: child),
                  ),
                  if (h > 0 && h < 1)
                    Opacity(
                      opacity: (1 - h) * 1.2 > 1 ? 1 : (1 - h) * 1.2,
                      child: Transform.scale(
                        scale: 0.6 + Curves.elasticOut.transform(h.clamp(0.0, 1.0)) * 0.7,
                        child: const Icon(CupertinoIcons.star_fill, size: 110, color: Color(0xEEFFFFFF)),
                      ),
                    ),
                ],
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}
