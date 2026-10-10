import 'package:flutter/cupertino.dart';

import '../../core/theme/hyde_theme.dart';
import '../../engine/models.dart';
import '../glass/glass_pressable.dart';
import 'artwork.dart';

String mediaTypeLabel(MediaItem item) => switch (item) {
  TrackItem(:final track) => track.isVideo ? 'Video' : 'Song',
  AlbumItem() => 'Album',
  ArtistItem() => 'Artist',
  PlaylistItem() => 'Playlist',
  BrowseItem() => 'Browse',
};

/// Song / result row: artwork, title, subtitle ("Type • Artist" in search),
/// optional trailing action.
class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.item,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.leading,
    this.showType = false,
    this.playing = false,
    this.dense = false,
  });

  final MediaItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  /// Replaces the artwork (track numbers on album pages).
  final Widget? leading;
  final bool showType;
  final bool playing;

  /// Tighter rows for long lists inside pages.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final isSong = item is TrackItem;
    final track = item is TrackItem ? (item as TrackItem).track : null;
    final sub = item.subtitle;
    final subtitle = showType ? (sub.isEmpty ? mediaTypeLabel(item) : '${mediaTypeLabel(item)} • $sub') : sub;
    final art = dense ? 44.0 : 50.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4, vertical: dense ? 5 : 7),
        child: Row(
          children: [
            leading ?? Artwork(url: item.thumbnailUrl, size: art, radius: 6, circle: item is ArtistItem),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HydeText.body.copyWith(
                      fontSize: 16,
                      fontWeight: playing ? FontWeight.w600 : FontWeight.w400,
                      color: playing ? HydeColors.accent : HydeColors.label.resolveFrom(context),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (track?.explicit ?? false) ...[const _Badge('E'), const SizedBox(width: 5)],
                        if (track?.isDownloaded ?? false) ...[
                          Icon(CupertinoIcons.arrow_down_circle_fill, size: 13, color: secondary),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HydeText.footnote.copyWith(
                              fontSize: 13.5,
                              color: showType && isSong ? HydeColors.accent : secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HydeColors.tertiaryLabel.resolveFrom(context),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(fontFamily: HydeText.family, fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF000000)),
      ),
    );
  }
}

/// Grid / carousel card: square artwork, title, subtitle.
class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.item, this.onTap, this.onLongPress, this.width});

  final MediaItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final isArtist = item is ArtistItem;
    final card = Column(
      crossAxisAlignment: isArtist ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Artwork(url: item.thumbnailUrl, radius: 10, circle: isArtist),
        const SizedBox(height: 7),
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: isArtist ? TextAlign.center : TextAlign.start,
          style: HydeText.callout.copyWith(fontSize: 15, color: HydeColors.label.resolveFrom(context)),
        ),
        if (item.subtitle.isNotEmpty)
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: isArtist ? TextAlign.center : TextAlign.start,
            style: HydeText.footnote.copyWith(fontSize: 13.5, color: HydeColors.secondaryLabel.resolveFrom(context)),
          ),
      ],
    );
    return GlassPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      pressedScale: 0.97,
      stretch: 0,
      child: width == null ? card : SizedBox(width: width, child: card),
    );
  }
}

/// Mood / genre tile: a filled capsule with the mood's colour stripe.
class MoodTile extends StatelessWidget {
  const MoodTile({super.key, required this.item, this.onTap});
  final BrowseItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = item.color == null ? HydeColors.accent : Color(0xFF000000 | (item.color! & 0xFFFFFF));
    return GlassPressable(
      onTap: onTap,
      pressedScale: 0.96,
      stretch: 0,
      child: Container(
        height: 46,
        decoration: ShapeDecoration(
          color: HydeColors.groupedFill.resolveFrom(context),
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Container(width: 5, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HydeText.subhead.copyWith(fontWeight: FontWeight.w600, color: HydeColors.label.resolveFrom(context)),
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.label, this.onMore, this.thumbnailUrl, this.circleThumbnail = true});
  final String title;
  final String? label;
  final VoidCallback? onMore;

  /// Small artwork before the title ("Similar to" rows).
  final String? thumbnailUrl;
  final bool circleThumbnail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 22, HydeMetrics.gutter, 10),
      child: GestureDetector(
        onTap: onMore,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (thumbnailUrl != null) ...[
              Artwork(url: thumbnailUrl, size: 40, radius: 6, circle: circleThumbnail),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null && label!.isNotEmpty)
                    Text(
                      label!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HydeText.caption.copyWith(
                        fontSize: 11.5,
                        letterSpacing: 0.3,
                        color: HydeColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HydeText.title2.copyWith(color: HydeColors.label.resolveFrom(context)),
                  ),
                ],
              ),
            ),
            if (onMore != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(CupertinoIcons.chevron_forward, size: 18, color: HydeColors.secondaryLabel.resolveFrom(context)),
              ),
          ],
        ),
      ),
    );
  }
}
