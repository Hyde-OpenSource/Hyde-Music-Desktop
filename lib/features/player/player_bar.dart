import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_style.dart';
import '../../design/glass/liquid_glass.dart';
import '../../design/widgets/artwork.dart';
import '../../design/widgets/elastic_slider.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';

/// What the desktop player shows over the content: nothing, lyrics or the queue.
enum DesktopPane { none, lyrics, queue }

/// The open [DesktopPane]; the player bar's buttons and the shortcuts toggle it.
class DesktopPaneNotifier extends Notifier<DesktopPane> {
  @override
  DesktopPane build() => DesktopPane.none;

  void toggle(DesktopPane pane) => state = state == pane ? DesktopPane.none : pane;
  void close() => state = DesktopPane.none;
}

final desktopPaneProvider = NotifierProvider<DesktopPaneNotifier, DesktopPane>(DesktopPaneNotifier.new);

/// AI Shuffle is on: the queue is shuffled with the smart order.
final aiShuffleProvider = Provider<bool>((ref) {
  final shuffle = ref.watch(nowPlayingProvider.select((s) => s.shuffle));
  final smart = ref.watch(settingsProvider.select((s) => s.value?['smartShuffleEnabled'] == true));
  return shuffle && smart;
});

/// Shuffle toggles shared by the bar, the queue and the shortcuts.
Future<void> setQueueShuffle(WidgetRef ref, {required bool enabled, bool smart = false}) async {
  await ref.read(engineProvider).setShuffle(enabled, smart: enabled ? smart : null);
  if (enabled) ref.invalidate(settingsProvider);
}

/// Desktop transport: a full-width Liquid Glass bar at the bottom of the
/// window. Track on the left, transport and seek in the middle, AI Shuffle,
/// lyrics, queue and volume on the right.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  static const height = 92.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(nowPlayingProvider.select((s) => s.track));
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return LiquidGlass(
      // Bar glass with a deeper tint: titles stay readable over busy artwork.
      style: GlassStyle.bar.copyWith(
        blur: 10,
        tint: dark ? const Color(0xFF0C0C0E) : const Color(0xFFF7F7FA),
        tintStrength: dark ? 0.5 : 0.55,
      ),
      radius: 26,
      child: SizedBox(
        height: height,
        child: track == null
            ? Center(
                child: Text(
                  'Pick a song to start listening',
                  style: HydeText.subhead.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _NowPlayingInfo(track: track)),
                    const Expanded(flex: 4, child: _Transport()),
                    const Expanded(flex: 3, child: _Extras()),
                  ],
                ),
              ),
      ),
    );
  }
}

class _NowPlayingInfo extends ConsumerWidget {
  const _NowPlayingInfo({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = HydeColors.label.resolveFrom(context);
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final pane = ref.watch(desktopPaneProvider);
    return Row(
      children: [
        _Hover(
          tooltip: pane == DesktopPane.none ? 'Show lyrics' : 'Hide player',
          onTap: () => pane == DesktopPane.none
              ? ref.read(desktopPaneProvider.notifier).toggle(DesktopPane.lyrics)
              : ref.read(desktopPaneProvider.notifier).close(),
          child: Hero(tag: 'np-artwork', child: Artwork(url: track.thumbnailUrl, size: 62, radius: 10)),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HydeText.headline.copyWith(color: label),
              ),
              const SizedBox(height: 2),
              Text(
                track.artistLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HydeText.subhead.copyWith(color: secondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _BarButton(
          icon: track.liked ? CupertinoIcons.star_fill : CupertinoIcons.star,
          tooltip: track.liked ? 'Remove from Favourites' : 'Favourite',
          active: track.liked,
          onTap: () => ref.read(engineProvider).setLiked(track, !track.liked),
        ),
      ],
    );
  }
}

class _Transport extends ConsumerStatefulWidget {
  const _Transport();

  @override
  ConsumerState<_Transport> createState() => _TransportState();
}

class _TransportState extends ConsumerState<_Transport> {
  double? _seekPreview;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(nowPlayingProvider);
    final engine = ref.read(engineProvider);
    final ai = ref.watch(aiShuffleProvider);
    final plainShuffle = s.shuffle && !ai;
    final value = _seekPreview ?? s.progress;
    final pos = Duration(milliseconds: (value * s.duration.inMilliseconds).round());
    final label = HydeText.caption.copyWith(
      color: HydeColors.secondaryLabel.resolveFrom(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _BarButton(
              icon: CupertinoIcons.shuffle,
              tooltip: plainShuffle ? 'Shuffle off' : 'Shuffle',
              active: plainShuffle,
              size: 18,
              onTap: () => setQueueShuffle(ref, enabled: !plainShuffle),
            ),
            const SizedBox(width: 10),
            _BarButton(icon: CupertinoIcons.backward_fill, tooltip: 'Previous (Ctrl+←)', size: 22, onTap: engine.previous),
            const SizedBox(width: 8),
            _PlayButton(playing: s.isPlaying, loading: s.isBuffering, onTap: engine.playPause),
            const SizedBox(width: 8),
            _BarButton(icon: CupertinoIcons.forward_fill, tooltip: 'Next (Ctrl+→)', size: 22, onTap: engine.next),
            const SizedBox(width: 10),
            _BarButton(
              icon: s.repeat == QueueRepeat.one ? CupertinoIcons.repeat_1 : CupertinoIcons.repeat,
              tooltip: switch (s.repeat) {
                QueueRepeat.off => 'Repeat',
                QueueRepeat.all => 'Repeat one',
                QueueRepeat.one => 'Repeat off',
              },
              active: s.repeat != QueueRepeat.off,
              size: 18,
              onTap: () => engine.setRepeat(QueueRepeat.values[(s.repeat.index + 1) % QueueRepeat.values.length]),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            SizedBox(width: 44, child: Text(_fmt(pos), textAlign: TextAlign.right, style: label)),
            const SizedBox(width: 10),
            Expanded(
              child: ElasticSlider(
                value: value,
                height: 5,
                activeHeight: 9,
                activeColor: HydeColors.label.resolveFrom(context),
                secondaryValue: s.duration.inMilliseconds == 0 ? 0 : s.buffered.inMilliseconds / s.duration.inMilliseconds,
                onChanged: (v) => setState(() => _seekPreview = v),
                onChangeEnd: (v) {
                  engine.seek(Duration(milliseconds: (v * s.duration.inMilliseconds).round()));
                  setState(() => _seekPreview = null);
                },
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 44, child: Text(_fmt(s.duration), style: label)),
          ],
        ),
      ],
    );
  }

  static String _fmt(Duration d) => '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

class _Extras extends ConsumerWidget {
  const _Extras();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(aiShuffleProvider);
    final pane = ref.watch(desktopPaneProvider);
    final volume = ref.watch(nowPlayingProvider.select((s) => s.volume));
    final engine = ref.read(engineProvider);
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _BarButton(
          icon: CupertinoIcons.sparkles,
          tooltip: ai ? 'AI Shuffle off' : 'AI Shuffle',
          active: ai,
          onTap: () => setQueueShuffle(ref, enabled: !ai, smart: true),
        ),
        _BarButton(
          icon: CupertinoIcons.quote_bubble,
          tooltip: 'Lyrics (Ctrl+L)',
          active: pane == DesktopPane.lyrics,
          onTap: () => ref.read(desktopPaneProvider.notifier).toggle(DesktopPane.lyrics),
        ),
        _BarButton(
          icon: CupertinoIcons.list_bullet,
          tooltip: 'Playing Next (Ctrl+Q)',
          active: pane == DesktopPane.queue,
          onTap: () => ref.read(desktopPaneProvider.notifier).toggle(DesktopPane.queue),
        ),
        const SizedBox(width: 8),
        Icon(volume == 0 ? CupertinoIcons.speaker_slash_fill : CupertinoIcons.speaker_fill, size: 15, color: secondary),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: ElasticSlider(
            value: volume,
            height: 5,
            activeHeight: 9,
            activeColor: HydeColors.label.resolveFrom(context),
            onChanged: engine.setVolume,
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.loading, required this.onTap});
  final bool playing;
  final bool loading;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final label = HydeColors.label.resolveFrom(context);
    final bg = HydeColors.background.resolveFrom(context);
    return _Hover(
      tooltip: playing ? 'Pause (Space)' : 'Play (Space)',
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: label, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: loading
            ? CupertinoActivityIndicator(radius: 9, color: bg)
            : Icon(playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, size: 20, color: bg),
      ),
    );
  }
}

/// Icon button with a hover highlight and tooltip-like semantics.
class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.tooltip, required this.onTap, this.active = false, this.size = 19});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = active ? HydeColors.accent : HydeColors.label.resolveFrom(context).withValues(alpha: 0.82);
    return _Hover(
      tooltip: tooltip,
      onTap: onTap,
      child: SizedBox.square(dimension: 36, child: Icon(icon, size: size, color: color)),
    );
  }
}

/// Pointer affordances for desktop: hand cursor, a soft hover disc, and a
/// tooltip shown after a short hover.
class _Hover extends StatefulWidget {
  const _Hover({required this.child, required this.onTap, required this.tooltip});
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: _hover ? HydeColors.label.resolveFrom(context).withValues(alpha: 0.08) : const Color(0x00000000),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
