import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/motion/hyde_motion.dart';

/// The "liquid" touch response of glass controls: on touch the control swells
/// and leans a little toward the finger; on release it springs back with a
/// slight overshoot. Springs are retargeted, never restarted, so fast taps
/// feel continuous.
class GlassPressable extends StatefulWidget {
  const GlassPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 1.08,
    this.stretch = 0.04,
    this.haptic = true,
    this.builder,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  /// Extra squash/stretch toward the drag direction.
  final double stretch;
  final bool haptic;

  /// Optional: receives press progress 0..1 (overshoots allowed) to drive
  /// e.g. a glass style lerp from regular to clear.
  final Widget Function(BuildContext context, double press, Widget child)? builder;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

class _GlassPressableState extends State<GlassPressable> with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(vsync: this);
  Offset _lean = Offset.zero;
  Size _size = Size.zero;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent e) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _updateLean(e.localPosition);
    springTo(_press, 1, HydeSprings.press);
  }

  void _move(PointerMoveEvent e) => _updateLean(e.localPosition);

  void _up([Object? _]) {
    springTo(_press, 0, HydeSprings.bouncy);
    setState(() => _lean = Offset.zero);
  }

  void _updateLean(Offset local) {
    if (_size.isEmpty) return;
    final c = _size.center(Offset.zero);
    final v = Offset((local.dx - c.dx) / _size.width, (local.dy - c.dy) / _size.height);
    setState(() => _lean = Offset(v.dx.clamp(-0.5, 0.5), v.dy.clamp(-0.5, 0.5)));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: AnimatedBuilder(
          animation: _press,
          child: widget.child,
          builder: (context, child) {
            final p = _press.value;
            final grow = 1 + (widget.pressedScale - 1) * p;
            final sx = grow * (1 + widget.stretch * p * _lean.dx.abs());
            final sy = grow * (1 + widget.stretch * p * _lean.dy.abs());
            final shifted = Offset(_lean.dx * 4 * p, _lean.dy * 4 * p);
            final body = widget.builder?.call(context, p, child!) ?? child!;
            return _SizeReporter(
              onSize: (s) => _size = s,
              child: Transform.translate(
                offset: shifted,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(sx, sy, 1),
                  child: body,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);
  ValueChanged<Size> onSize;

  @override
  void performLayout() {
    super.performLayout();
    onSize(size);
  }
}
