import 'package:flutter/widgets.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import 'glass_style.dart';

/// A piece of Liquid Glass with [child] on top — rendered by
/// `liquid_glass_easy`'s [LiquidGlassLens] (live-backdrop refraction on
/// Impeller, frosted fallback elsewhere).
///
/// Keeps Hyde's [GlassStyle] vocabulary so every surface in the app is tuned
/// in one place, and adds the package's touch physics ([flex]): press and the
/// glass swells, drag and it stretches after the finger, release and it
/// springs back.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    this.style = GlassStyle.regular,
    this.radius,
    this.opacity = 1,
    this.flex = false,
    this.child,
  });

  /// Capsule glass (fully rounded ends).
  const LiquidGlass.capsule({
    super.key,
    this.style = GlassStyle.regular,
    this.opacity = 1,
    this.flex = false,
    this.child,
  }) : radius = null;

  final GlassStyle style;

  /// Corner radius; null means capsule.
  final double? radius;

  /// 0..1 — fades the whole material (glass and content). Never wrap glass in
  /// `Opacity`; use this.
  final double opacity;

  /// Soft-body touch response (press swell, drag stretch).
  final bool flex;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final o = opacity.clamp(0.0, 1.0);
    final content = child == null || o >= 1 ? child : Opacity(opacity: o, child: child);
    return LiquidGlassLens(
      visibility: o > 0.02,
      touch: flex ? const LiquidGlassTouch(flex: LiquidGlassFlex()) : null,
      style: toLensStyle(style, radius: radius ?? 1000, opacity: o),
      child: content,
    );
  }

  /// Maps a [GlassStyle] onto the package's style.
  static LiquidGlassStyle toLensStyle(GlassStyle s, {required double radius, double opacity = 1}) {
    final o = opacity;
    return LiquidGlassStyle(
      shape: LiquidGlassShape.continuousRoundedRectangle(
        cornerRadius: radius,
        lightIntensity: s.lightIntensity * o,
        lightDirection: s.lightAngle,
      ),
      appearance: LiquidGlassAppearance(
        color: s.tint.withValues(alpha: s.tintStrength * o),
        blur: LiquidGlassBlur(sigmaX: s.blur * o, sigmaY: s.blur * o),
        saturation: 1 + (s.saturation - 1) * o,
      ),
      refraction: LiquidGlassRefraction(
        distortion: (s.refraction / 160 * o).clamp(0.0, 0.5),
        distortionWidth: s.bezel,
        magnification: 1 + (s.magnify - 1) * o,
        chromaticAberration: s.dispersion * 0.008 * o,
      ),
    );
  }
}
