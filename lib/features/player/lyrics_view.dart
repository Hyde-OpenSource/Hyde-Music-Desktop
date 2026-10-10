import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';

import '../../core/motion/hyde_motion.dart';
import '../../core/theme/hyde_theme.dart';
import '../../engine/models.dart';

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
    required this.position,
    required this.onSeek,
    this.appearance = const LyricsAppearance(),
    this.topInset = 24,
  });

  final Lyrics lyrics;
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

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(LyricsView old) {
    super.didUpdateWidget(old);
    if (old.lyrics != widget.lyrics) {
      _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
      _active = -1;
    }
    _syncActive();
  }

  @override
  void dispose() {
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
    final i = _indexFor(widget.position);
    if (i == _active) return;
    _active = i;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActive());
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
                    position: widget.position,
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
    required this.nextStart,
    required this.appearance,
    required this.focusAll,
    required this.onTap,
  });

  final LyricLine line;
  final int distance;
  final bool active;
  final Duration position;
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

/// Three breathing dots during instrumental breaks.
class _InterludeDots extends StatelessWidget {
  const _InterludeDots({required this.start, required this.end, required this.position});
  final Duration start;
  final Duration? end;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final total = ((end ?? start + const Duration(seconds: 3)) - start).inMilliseconds;
    final p = ((position - start).inMilliseconds / math.max(1, total)).clamp(0.0, 1.0);
    final breathe = 1 + 0.12 * math.sin(position.inMilliseconds / 260);
    return Transform.scale(
      scale: breathe,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 12, bottom: 12),
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromRGBO(255, 255, 255, 0.3 + 0.7 * ((p * 3 - i).clamp(0.0, 1.0))),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
