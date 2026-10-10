import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../core/motion/hyde_motion.dart';
import '../../core/theme/hyde_theme.dart';
import 'glass_style.dart';
import 'liquid_glass.dart';

/// iOS 26 switch — `liquid_glass_easy`'s [LiquidGlassSwitch]: the thumb lifts
/// into clear glass under the finger, refracts the track and springs back.
class GlassSwitch extends StatelessWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor = const Color(0xFF34C759),
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: LiquidGlassSwitch(
        value: value,
        activeColor: activeColor,
        inactiveColor: HydeColors.separator.resolveFrom(context),
        width: 63,
        height: 28,
        onChanged: (v) {
          if (onChanged == null) return;
          HapticFeedback.lightImpact();
          onChanged!(v);
        },
      ),
    );
  }
}

/// iOS 26 slider — `liquid_glass_easy`'s [LiquidGlassSlider] (glass thumb that
/// lifts under the finger and deforms with acceleration). Adds [divisions]
/// snapping with a haptic tick per step.
class GlassSlider extends StatefulWidget {
  const GlassSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.activeColor = HydeColors.accent,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final Color activeColor;

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<GlassSlider> {
  double? _lastStep;

  double _snap(double v) {
    final d = widget.divisions;
    if (d == null || d <= 0 || widget.max == widget.min) return v;
    final f = ((v - widget.min) / (widget.max - widget.min) * d).round() / d;
    final snapped = widget.min + f * (widget.max - widget.min);
    if (snapped != _lastStep) {
      _lastStep = snapped;
      HapticFeedback.selectionClick();
    }
    return snapped;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        height: 44,
        child: Center(
          child: LiquidGlassSlider(
            value: widget.value.clamp(widget.min, widget.max),
            minimumValue: widget.min,
            maximumValue: widget.max,
            activeColor: widget.activeColor,
            inactiveColor: HydeColors.separator.resolveFrom(context),
            width: c.maxWidth,
            onChanged: (v) => widget.onChanged?.call(_snap(v)),
          ),
        ),
      ),
    );
  }
}

/// Segmented control with a Liquid Glass selection pill that springs between
/// segments (and swells into a lens while you press it).
class GlassSegmentedControl extends StatefulWidget {
  const GlassSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 38,
  });

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  State<GlassSegmentedControl> createState() => _GlassSegmentedControlState();
}

class _GlassSegmentedControlState extends State<GlassSegmentedControl> with TickerProviderStateMixin {
  late final AnimationController _x = AnimationController.unbounded(
    vsync: this,
    value: widget.selectedIndex.toDouble(),
  );

  @override
  void didUpdateWidget(GlassSegmentedControl old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      springTo(_x, widget.selectedIndex.toDouble(), HydeSprings.snappy);
    }
  }

  @override
  void dispose() {
    _x.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.segments.length;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final seg = (w - 6) / n;
        return Container(
          height: widget.height,
          decoration: ShapeDecoration(shape: const StadiumBorder(), color: HydeColors.groupedFill.resolveFrom(context)),
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _x,
                builder: (context, _) {
                  final stretch = 1 + (_x.velocity.abs() * 0.05).clamp(0.0, 0.3);
                  return Positioned(
                    left: 3 + seg * _x.value - seg * (stretch - 1) / 2,
                    top: 3,
                    width: seg * stretch,
                    height: widget.height - 6,
                    child: LiquidGlass.capsule(
                      style: GlassStyle.clear.copyWith(tint: const Color(0xFFFFFFFF), tintStrength: 0.16),
                      flex: true,
                    ),
                  );
                },
              ),
              Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onChanged(i);
                        },
                        child: Center(
                          child: Text(
                            widget.segments[i],
                            maxLines: 1,
                            style: HydeText.footnote.copyWith(
                              fontWeight: i == widget.selectedIndex ? FontWeight.w700 : FontWeight.w500,
                              color: HydeColors.label.resolveFrom(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
