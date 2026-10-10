import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/motion/hyde_motion.dart';

/// Apple Music style slider: a thin track that thickens and brightens while
/// touched, follows the finger relatively (no jump on touch-down), and
/// rubber-bands past either end before springing back.
class ElasticSlider extends StatefulWidget {
  const ElasticSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.secondaryValue,
    this.leading,
    this.trailing,
    this.height = 7,
    this.activeHeight = 13,
    this.activeColor = const Color(0xFFFFFFFF),
  });

  final double value;
  final double? secondaryValue;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Widget? leading;
  final Widget? trailing;
  final double height;
  final double activeHeight;
  final Color activeColor;

  @override
  State<ElasticSlider> createState() => _ElasticSliderState();
}

class _ElasticSliderState extends State<ElasticSlider> with TickerProviderStateMixin {
  late final AnimationController _active = AnimationController.unbounded(vsync: this);
  late final AnimationController _overdrag = AnimationController.unbounded(vsync: this);
  double? _dragValue;
  double _width = 1;

  @override
  void dispose() {
    _active.dispose();
    _overdrag.dispose();
    super.dispose();
  }

  void _start(DragStartDetails d) {
    _dragValue = widget.value;
    springTo(_active, 1, HydeSprings.press);
  }

  void _update(DragUpdateDetails d) {
    final raw = (_dragValue ?? widget.value) + d.delta.dx / _width;
    final clamped = raw.clamp(0.0, 1.0);
    // Rubber band: sqrt-damped overshoot, in px.
    final over = (raw - clamped) * _width;
    _overdrag.value = over.sign * math.sqrt(over.abs()) * 2.2;
    if ((clamped == 0 || clamped == 1) && _dragValue != clamped) HapticFeedback.lightImpact();
    _dragValue = raw.clamp(-0.2, 1.2);
    widget.onChanged(clamped);
  }

  void _end([DragEndDetails? _]) {
    final v = (_dragValue ?? widget.value).clamp(0.0, 1.0);
    _dragValue = null;
    springTo(_active, 0, HydeSprings.bouncy);
    springTo(_overdrag, 0, HydeSprings.bouncy);
    widget.onChangeEnd?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_active, _overdrag]),
      builder: (context, _) {
        final a = _active.value.clamp(0.0, 1.2);
        final od = _overdrag.value;
        final h = widget.height + (widget.activeHeight - widget.height) * a;
        Widget edge(Widget? w, bool left) => w == null
            ? const SizedBox.shrink()
            : Transform.translate(
                offset: Offset(left ? math.min(od, 0) * 0.6 : math.max(od, 0) * 0.6, 0),
                child: Transform.scale(scale: 1 + 0.15 * ((left ? od < 0 : od > 0) ? a : 0), child: w),
              );
        return Row(
          children: [
            edge(widget.leading, true),
            if (widget.leading != null) const SizedBox(width: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  _width = c.maxWidth;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: _start,
                    onHorizontalDragUpdate: _update,
                    onHorizontalDragEnd: _end,
                    onHorizontalDragCancel: _end,
                    onTapDown: (_) => springTo(_active, 1, HydeSprings.press),
                    onTapUp: (_) => springTo(_active, 0, HydeSprings.bouncy),
                    onTapCancel: () => springTo(_active, 0, HydeSprings.bouncy),
                    child: SizedBox(
                      height: 34,
                      child: Center(
                        child: Transform(
                          alignment: od < 0 ? Alignment.centerRight : Alignment.centerLeft,
                          transform: Matrix4.translationValues(od < 0 ? od : 0, 0, 0)
                            ..scaleByDouble(1 + od.abs() / _width, 1 - od.abs() / 300, 1, 1),
                          child: CustomPaint(
                            size: Size(c.maxWidth, h),
                            painter: _TrackPainter(
                              value: widget.value,
                              secondary: widget.secondaryValue,
                              active: a,
                              color: widget.activeColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.trailing != null) const SizedBox(width: 12),
            edge(widget.trailing, false),
          ],
        );
      },
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.value, required this.secondary, required this.active, required this.color});
  final double value;
  final double? secondary;
  final double active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.clipRRect(track);
    canvas.drawRRect(track, Paint()..color = color.withValues(alpha: 0.22 + 0.06 * active));
    if (secondary != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * secondary!.clamp(0.0, 1.0), size.height),
        Paint()..color = color.withValues(alpha: 0.12),
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * value.clamp(0.0, 1.0), size.height),
      Paint()..color = color.withValues(alpha: 0.82 + 0.18 * active.clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.value != value || old.secondary != secondary || old.active != active || old.color != color;
}
