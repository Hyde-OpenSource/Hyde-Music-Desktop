import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Colours for the Now Playing background, derived from the artwork
/// (replaces ui/theme/PlayerColorExtractor.kt + androidx Palette).
class ArtworkPalette {
  const ArtworkPalette(this.top, this.bottom, this.accent);
  final Color top;
  final Color bottom;
  final Color accent;

  static const fallback = ArtworkPalette(Color(0xFF3A3A40), Color(0xFF1C1C20), Color(0xFF8E8E93));
}

final artworkPaletteProvider = FutureProvider.family<ArtworkPalette, String?>((ref, url) async {
  if (url == null || url.isEmpty) return ArtworkPalette.fallback;
  try {
    final image = await _load(ResizeImage(CachedNetworkImageProvider(url), width: 32, height: 32));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return ArtworkPalette.fallback;
    return _derive(data.buffer.asUint8List());
  } catch (_) {
    return ArtworkPalette.fallback;
  }
});

Future<ui.Image> _load(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      completer.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (e, s) {
      completer.completeError(e, s);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// Picks the most "characteristic" colour: 4-bit-per-channel buckets weighted
/// by population × saturation, ignoring near-black/near-white pixels. Then
/// tones it down to a dark, legible background like Apple Music's.
ArtworkPalette _derive(List<int> rgba) {
  final buckets = <int, List<double>>{}; // key -> [count, r, g, b]
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
    if (hsl.lightness < 0.08 || hsl.lightness > 0.94) continue;
    final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
    final e = buckets.putIfAbsent(key, () => [0, 0, 0, 0]);
    final w = 0.35 + hsl.saturation;
    e[0] += w;
    e[1] += r * w;
    e[2] += g * w;
    e[3] += b * w;
  }
  if (buckets.isEmpty) return ArtworkPalette.fallback;
  final best = buckets.values.reduce((a, b) => a[0] >= b[0] ? a : b);
  final base = Color.fromARGB(
    255,
    (best[1] / best[0]).round(),
    (best[2] / best[0]).round(),
    (best[3] / best[0]).round(),
  );
  final hsl = HSLColor.fromColor(base);
  final sat = math.min(hsl.saturation, 0.55);
  final top = hsl.withSaturation(sat).withLightness(0.34).toColor();
  final bottom = hsl.withSaturation(sat * 0.9).withLightness(0.18).toColor();
  final accent = hsl.withSaturation(math.min(1, sat + 0.2)).withLightness(0.62).toColor();
  return ArtworkPalette(top, bottom, accent);
}
