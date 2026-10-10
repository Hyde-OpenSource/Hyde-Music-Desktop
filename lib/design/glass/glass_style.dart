import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Optical parameters for one piece of Liquid Glass.
///
/// What makes it read as *liquid glass* rather than a blur: low frost, a lens
/// that magnifies what's under it ([magnify]), a thick rim that bends the
/// surroundings in ([bezel], [refraction]), the spectral fringe
/// ([dispersion]) and a bright two-sided specular rim. Frost ([blur]) is kept
/// low except where legibility needs it (menus).
@immutable
class GlassStyle {
  const GlassStyle({
    this.blur = 6,
    this.bezel = 22,
    this.refraction = 24,
    this.magnify = 1.05,
    this.dispersion = 0.5,
    this.saturation = 1.5,
    this.tint = const Color(0x00000000),
    this.tintStrength = 0,
    this.lightAngle = -math.pi * 0.70,
    this.lightIntensity = 0.8,
    this.ambient = 0.12,
  });

  /// Gaussian sigma of the frosting under the glass (logical px).
  final double blur;

  /// Width of the rim band that bends light (logical px).
  final double bezel;

  /// Maximum displacement at the very rim (logical px).
  final double refraction;

  /// Lens zoom of the body: 1 = flat pane, 1.1 = clearly magnifying.
  final double magnify;

  /// Chromatic dispersion — the rainbow fringe. 0 disables it.
  final double dispersion;

  /// Vibrancy boost of what's seen through the glass.
  final double saturation;

  final Color tint;
  final double tintStrength;

  /// Direction the key light comes from (radians, screen space).
  final double lightAngle;
  final double lightIntensity;
  final double ambient;

  static const regular = GlassStyle();

  /// Lens under a finger, pane toggles, switch/slider knobs: crisp and strongly refractive.
  static const clear = GlassStyle(
    blur: 0.6,
    bezel: 26,
    refraction: 30,
    magnify: 1.14,
    dispersion: 0.75,
    saturation: 1.2,
    lightIntensity: 1.0,
    ambient: 0.16,
  );

  /// Popover menus: frosted enough to read text over anything.
  static const menu = GlassStyle(
    blur: 22,
    bezel: 22,
    refraction: 18,
    magnify: 1.0,
    dispersion: 0.45,
    saturation: 1.8,
    tint: Color(0xFF3A3A3E),
    tintStrength: 0.30,
  );

  /// Floating chrome: tab bar, mini player, toolbar discs.
  static const bar = GlassStyle(
    blur: 4,
    bezel: 20,
    refraction: 26,
    magnify: 1.06,
    dispersion: 0.55,
    saturation: 1.6,
    tint: Color(0xFF101012),
    tintStrength: 0.22,
  );

  GlassStyle copyWith({
    double? blur,
    double? bezel,
    double? refraction,
    double? magnify,
    double? dispersion,
    double? saturation,
    Color? tint,
    double? tintStrength,
    double? lightAngle,
    double? lightIntensity,
    double? ambient,
  }) {
    return GlassStyle(
      blur: blur ?? this.blur,
      bezel: bezel ?? this.bezel,
      refraction: refraction ?? this.refraction,
      magnify: magnify ?? this.magnify,
      dispersion: dispersion ?? this.dispersion,
      saturation: saturation ?? this.saturation,
      tint: tint ?? this.tint,
      tintStrength: tintStrength ?? this.tintStrength,
      lightAngle: lightAngle ?? this.lightAngle,
      lightIntensity: lightIntensity ?? this.lightIntensity,
      ambient: ambient ?? this.ambient,
    );
  }

  static GlassStyle lerp(GlassStyle a, GlassStyle b, double t) {
    double l(double x, double y) => lerpDouble(x, y, t)!;
    return GlassStyle(
      blur: l(a.blur, b.blur),
      bezel: l(a.bezel, b.bezel),
      refraction: l(a.refraction, b.refraction),
      magnify: l(a.magnify, b.magnify),
      dispersion: l(a.dispersion, b.dispersion),
      saturation: l(a.saturation, b.saturation),
      tint: Color.lerp(a.tint, b.tint, t)!,
      tintStrength: l(a.tintStrength, b.tintStrength),
      lightAngle: l(a.lightAngle, b.lightAngle),
      lightIntensity: l(a.lightIntensity, b.lightIntensity),
      ambient: l(a.ambient, b.ambient),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassStyle &&
      other.blur == blur &&
      other.bezel == bezel &&
      other.refraction == refraction &&
      other.magnify == magnify &&
      other.dispersion == dispersion &&
      other.saturation == saturation &&
      other.tint == tint &&
      other.tintStrength == tintStrength &&
      other.lightAngle == lightAngle &&
      other.lightIntensity == lightIntensity &&
      other.ambient == ambient;

  @override
  int get hashCode => Object.hash(
    blur,
    bezel,
    refraction,
    magnify,
    dispersion,
    saturation,
    tint,
    tintStrength,
    lightAngle,
    lightIntensity,
    ambient,
  );
}
