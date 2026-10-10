import 'dart:ui' as ui;

import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// Renderer control for the glass (implemented by `liquid_glass_easy`).
abstract final class GlassShader {
  /// Compiles the glass programs before the first frame, so the first lens on
  /// screen is real glass immediately.
  static Future<void> preload() => LiquidGlassShaders.ensureLoaded();

  /// false = "Frosted" quality: the package's lite glass (frost, tint, lit
  /// rim, no refraction) — cheaper on old phones.
  static bool get enabled => !LiquidGlassEngine.liteGlassOnImpeller;
  static set enabled(bool value) {
    LiquidGlassEngine.liteGlassOnImpeller = !value;
    LiquidGlassEngine.liteGlassOnSkia = true;
  }

  /// Human-readable renderer state for Settings ▸ Appearance.
  static String get status {
    if (!ui.ImageFilter.isShaderFilterSupported) return 'Frosted (Impeller unavailable)';
    if (!enabled) return 'Frosted (set by you)';
    return 'Liquid Glass (Impeller)';
  }
}
