import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/physics.dart';

import '../../core/motion/hyde_motion.dart';
import '../../core/theme/hyde_theme.dart';
import '../../engine/models.dart';
import 'lyrics_clock.dart';

/// Options mapped from the native lyrics preferences
/// (lyricsTextPosition, lyricsTextSize, lyricsLineSpacing,
/// appleMusicLyricsBlur, lyricsGlowEffect).
class LyricsAppearance {
  const LyricsAppearance({
    this.align = TextAlign.left,
    this.fontSize = 32,
    this.lineSpacing = 1.15,
    this.blur = true,
    this.glow = false,
  });
  final TextAlign align;
  final double fontSize;
  final double lineSpacing;
  final bool blur;
  final bool glow;
}

/// Synced lyrics, Apple Music style.
class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.lyrics,
    this.clock,
    this.position = Duration.zero,
    required this.onSeek,
    this.appearance = const LyricsAppearance(),
    this.topInset = 24,
  });

  final Lyrics lyrics;

  /// Live playback clock; without one the view shows the fixed [position].
  final LyricsClock? clock;
  final Duration position;
  final ValueChanged<Duration> onSeek;
  final LyricsAppearance appearance;
  final double topInset;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _columnKey = GlobalKey();
  late List<GlobalKey> _keys;
  late final AnimationController _scrollAnim = AnimationController.unbounded(vsync: this)
    ..addListener(() {
      if (_scroll.hasClients && !_userScrolling) {
        final max = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(_scrollAnim.value.clamp(0.0, max));
      }
    });
  int _active = -1;
  bool _userScrolling = false;
  Timer? _resumeTimer;

  /// Fires at the next line's start time: exact line changes without polling.
  Timer? _boundary;

  Duration get _now => widget.clock?.now ?? widget.position;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
    widget.clock?.addListener(_onJump);
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.clock != widget.clock) {
      old.clock?.removeListener(_onJump);
      widget.clock?.addListener(_onJump);
    }
    if (old.lyrics != widget.lyrics) {
      _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
      _active = -1;
    }
  }

  /// Seek, play or pause: re-sync the active line and its timer.
  void _onJump() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.clock?.removeListener(_onJump);
    _boundary?.cancel();
    _resumeTimer?.cancel();
    _scrollAnim.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int _indexFor(Duration p) {
    final lines = widget.lyrics.lines;
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].start <= p) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  void _syncActive() {
    if (!widget.lyrics.synced) return;
    final now = _now;
    final i = _indexFor(now);
    _scheduleBoundary(i, now);
    if (i == _active) return;
    _active = i;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
  }

  void _scheduleBoundary(int active, Duration now) {
    _boundary?.cancel();
    final clock = widget.clock;
    final lines = widget.lyrics.lines;
    if (clock == null || !clock.playing || active + 1 >= lines.length) return;
    final wait = lines[active + 1].start - now;
    // A few ms late rather than early, so the new line is already current.
    _boundary = Timer(wait.isNegative ? Duration.zero : wait + const Duration(milliseconds: 4), _onJump);
  }

  void _scrollToActive() {
    if (!mounted || _userScrolling || _active < 0 || !_scroll.hasClients) return;
    final ctx = _keys[_active].currentContext;
    final column = _columnKey.currentContext?.findRenderObject();
    if (ctx == null || column == null) return;
    final box = ctx.findRenderObject()! as RenderBox;
    final y = box.localToGlobal(Offset.zero, ancestor: column).dy;
    // Active line rests ~22% down the viewport.
    final target = y - _scroll.position.viewportDimension * 0.22;
    _scrollAnim.value = _scroll.offset;
    _scrollAnim.animateWith(SpringSimulation(HydeSprings.smooth, _scroll.offset, target, 0));
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _scrollAnim.stop();
      _resumeTimer?.cancel();
      setState(() => _userScrolling = true);
    } else if (n is ScrollEndNotification && _userScrolling) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() => _userScrolling = false);
        _scrollToActive();
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    if (lyrics.lines.isEmpty) {
      return Center(
        child: Text('Lyrics not available', style: HydeText.title3.copyWith(color: const Color(0x99FFFFFF))),
      );
    }
    _syncActive();
    final a = widget.appearance;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ShaderMask(
        // Soft fade at top and bottom edges of the lyrics area.
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.06, 0.86, 1],
        ).createShader(r),
        child: SingleChildScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(28, widget.topInset, 28, 400),
          child: Column(
            key: _columnKey,
            crossAxisAlignment: switch (a.align) {
              TextAlign.center => CrossAxisAlignment.center,
              TextAlign.right => CrossAxisAlignment.end,
              _ => CrossAxisAlignment.start,
            },
            children: [
              for (var i = 0; i < lyrics.lines.length; i++)
                KeyedSubtree(
                  key: _keys[i],
                  child: _LyricLineView(
                    line: lyrics.lines[i],
                    distance: lyrics.synced ? (i - _active) : 0,
                    active: lyrics.synced && i == _active,
                    position: _now,
                    frames: widget.clock?.frames,
                    nextStart: i + 1 < lyrics.lines.length ? lyrics.lines[i + 1].start : null,
                    appearance: a,
                    focusAll: _userScrolling || !lyrics.synced,
                    onTap: lyrics.synced ? () => widget.onSeek(lyrics.lines[i].start) : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricLineView extends StatelessWidget {
  const _LyricLineView({
    required this.line,
    required this.distance,
    required this.active,
    required this.position,
    required this.frames,
    required this.nextStart,
    required this.appearance,
    required this.focusAll,
    required this.onTap,
  });

  final LyricLine line;
  final int distance;
  final bool active;

  /// Position when the line was built; [frames] drives the active line's
  /// per-frame parts (word fill, interlude dots).
  final Duration position;
  final ValueListenable<Duration>? frames;
  final Duration? nextStart;
  final LyricsAppearance appearance;
  final bool focusAll;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = appearance;
    final style = TextStyle(
      fontFamily: HydeText.family,
      fontSize: a.fontSize,
      height: a.lineSpacing,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: const Color(0xFFFFFFFF),
      shadows: active && a.glow ? const [Shadow(color: Color(0x88FFFFFF), blurRadius: 18)] : null,
    );

    Widget textAt(Duration position) {
      final Widget text;
      if (line.text.trim().isEmpty) {
        text = active
            ? _InterludeDots(start: line.start, end: nextStart, position: position)
            : const SizedBox(height: 12);
      } else if (active && line.words.isNotEmpty) {
        text = Text.rich(
          TextSpan(
            children: [
              for (final w in line.words)
                TextSpan(
                  text: w.text,
                  style: style.copyWith(
                    color: Color.lerp(
                      const Color(0x66FFFFFF),
                      const Color(0xFFFFFFFF),
                      ((position - w.start).inMilliseconds / math.max(1, (w.end - w.start).inMilliseconds)).clamp(
                        0.0,
                        1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          textAlign: a.align,
        );
      } else {
        text = Text(line.text, style: style, textAlign: a.align);
      }
      return text;
    }

    // Only the active line moves between line changes, inside a repaint
    // boundary so the other (blurred) lines are not redrawn every frame.
    final animated = active && (line.text.trim().isEmpty || line.words.isNotEmpty);
    final f = frames;
    final Widget text = animated && f != null
        ? RepaintBoundary(
            child: ValueListenableBuilder<Duration>(valueListenable: f, builder: (context, pos, _) => textAt(pos)),
          )
        : textAt(position);

    final d = distance.abs();
    final opacity = focusAll ? 0.75 : (active ? 1.0 : (distance < 0 ? 0.32 : 0.38));
    final sigma = (!a.blur || focusAll || active) ? 0.0 : math.min(d, 4) * 1.1;

    Widget body = Column(
      crossAxisAlignment: switch (a.align) {
        TextAlign.center => CrossAxisAlignment.center,
        TextAlign.right => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.start,
      },
      children: [
        text,
        if (line.romanized != null)
          Text(
            line.romanized!,
            textAlign: a.align,
            style: HydeText.title3.copyWith(color: const Color(0xB3FFFFFF)),
          ),
        if (line.translation != null)
          Text(
            line.translation!,
            textAlign: a.align,
            style: HydeText.title3.copyWith(color: const Color(0x99FFFFFF)),
          ),
      ],
    );

    body = TweenAnimationBuilder<double>(
      tween: Tween(end: sigma),
      duration: HydeDurations.slow,
      curve: Curves.easeOutCubic,
      builder: (context, s, child) => s < 0.05
          ? child!
          : ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s),
              child: child,
            ),
      child: body,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: AnimatedOpacity(
          opacity: opacity,
          duration: HydeDurations.medium,
          child: AnimatedScale(
            scale: active ? 1.0 : 0.97,
            alignment: switch (a.align) {
              TextAlign.center => Alignment.center,
              TextAlign.right => Alignment.centerRight,
              _ => Alignment.centerLeft,
            },
            duration: HydeDurations.slow,
            curve: Curves.easeOutBack,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Three breathing dots during instrumental breaks: they light up one by
/// one over the break, breathe gently, and shrink away just before the next
/// line. Driven by the per-frame lyrics clock, so the motion is smooth.
class _InterludeDots extends StatelessWidget {
  const _InterludeDots({required this.start, required this.end, required this.position});
  final Duration start;
  final Duration? end;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final stop = end ?? start + const Duration(seconds: 3);
    final total = math.max(1, (stop - start).inMilliseconds);
    final elapsed = (position - start).inMilliseconds;
    final p = (elapsed / total).clamp(0.0, 1.0);
    // Breathing: ~1.6 s period, small amplitude.
    final breathe = 1 + 0.08 * math.sin(elapsed / 1600 * 2 * math.pi);
    // Last 450 ms: shrink and fade out, handing over to the next line.
    final left = (stop - position).inMilliseconds;
    final exit = Curves.easeInCubic.transform((1 - left / 450).clamp(0.0, 1.0));
    return Opacity(
      opacity: 1 - exit,
      child: Transform.scale(
        scale: breathe * (1 - 0.6 * exit),
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 12, bottom: 12),
                child: _Dot(lit: Curves.easeOutCubic.transform((p * 3 - i).clamp(0.0, 1.0))),
              ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.lit});
  final double lit;

  @override
  Widget build(BuildContext context) {
    final size = 12 + 3 * lit;
    return SizedBox.square(
      dimension: 15,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Color.fromRGBO(255, 255, 255, 0.28 + 0.72 * lit)),
        ),
      ),
    );
  }
}
