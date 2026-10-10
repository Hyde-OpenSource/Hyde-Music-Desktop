import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';

import '../../core/theme/hyde_theme.dart';

/// Rounded artwork with a neutral placeholder. Square by default.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.size,
    this.radius = HydeMetrics.artworkRadius,
    this.circle = false,
    this.shadow = false,
    this.placeholderIcon = CupertinoIcons.music_note,
  });

  final String? url;
  final double? size;
  final double radius;
  final bool circle;
  final bool shadow;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3A3C), Color(0xFF1C1C1E)],
        ),
      ),
      child: Center(
        child: LayoutBuilder(
          builder: (context, c) => Icon(
            placeholderIcon,
            size: (c.biggest.shortestSide * 0.38).clamp(12.0, 64.0),
            color: const Color(0x66FFFFFF),
          ),
        ),
      ),
    );

    final image = url == null || url!.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );

    final shape = circle
        ? const ShapeDecoration(shape: CircleBorder())
        : ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius)));

    Widget child = ClipPath(
      clipper: ShapeBorderClipper(shape: shape.shape),
      child: image,
    );
    if (shadow) {
      child = DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape.shape,
          shadows: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14))],
        ),
        child: child,
      );
    }
    return size == null ? AspectRatio(aspectRatio: 1, child: child) : SizedBox.square(dimension: size, child: child);
  }
}
