import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion/hyde_motion.dart';
import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_style.dart';
import '../../design/glass/liquid_glass.dart';
import '../../design/widgets/artwork.dart';
import '../../state/providers.dart';
import 'artwork_palette.dart';
import 'now_playing_screen.dart' show LyricsPane;
import 'player_bar.dart';
import 'queue_view.dart';

/// Desktop Now Playing: fills the content area above the player bar. Cover
/// and title on the left, lyrics or the queue on the right, all on the
/// artwork's colours.
class DesktopNowPlaying extends ConsumerWidget {
  const DesktopNowPlaying({super.key, required this.pane});
  final DesktopPane pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(nowPlayingProvider.select((s) => s.track));
    final palette = ref.watch(artworkPaletteProvider(track?.thumbnailUrl)).value ?? ArtworkPalette.fallback;

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: palette.top),
      duration: HydeDurations.slow,
      builder: (context, top, child) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: palette.bottom),
        duration: HydeDurations.slow,
        builder: (context, bottom, _) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top!, Color.lerp(top, bottom, 0.6)!, bottom!],
            ),
          ),
          child: child,
        ),
        child: child,
      ),
      child: track == null
          ? const SizedBox.expand()
          : LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 900;
                final cover = math.min(wide ? c.maxWidth * 0.32 : c.maxWidth * 0.5, c.maxHeight * 0.58);
                final left = Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  children: [
                    Hero(tag: 'np-artwork', child: Artwork(url: track.thumbnailUrl, size: cover, radius: 18, shadow: true)),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: cover,
                      child: Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: wide ? TextAlign.start : TextAlign.center,
                        style: HydeText.title1.copyWith(color: const Color(0xFFFFFFFF)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: cover,
                      child: Text(
                        [track.artistLine, ?track.albumName].join(' — '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: wide ? TextAlign.start : TextAlign.center,
                        style: HydeText.title3.copyWith(fontWeight: FontWeight.w400, color: const Color(0xB3FFFFFF)),
                      ),
                    ),
                  ],
                );
                final right = ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: switch (pane) {
                    DesktopPane.queue => const QueueView(),
                    _ => LyricsPane(track: track),
                  },
                );
                return Stack(
                  children: [
                    Padding(
                      // Bottom: room for the player bar floating over this view.
                      padding: const EdgeInsets.fromLTRB(56, 40, 40, PlayerBar.height + 36),
                      child: wide
                          ? Row(
                              children: [
                                Expanded(flex: 5, child: Center(child: left)),
                                const SizedBox(width: 48),
                                Expanded(flex: 6, child: right),
                              ],
                            )
                          : Column(
                              children: [
                                SizedBox(height: c.maxHeight * 0.55, child: left),
                                Expanded(child: right),
                              ],
                            ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: _CloseButton(onTap: ref.read(desktopPaneProvider.notifier).close),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: 'Close player (Esc)',
          child: const LiquidGlass.capsule(
            style: GlassStyle.clear,
            child: SizedBox.square(
              dimension: 40,
              child: Icon(CupertinoIcons.chevron_down, size: 18, color: Color(0xFFFFFFFF)),
            ),
          ),
        ),
      ),
    );
  }
}
