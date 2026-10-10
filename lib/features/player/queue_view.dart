import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/widgets/artwork.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import 'player_bar.dart' show aiShuffleProvider, setQueueShuffle;

/// "Playing Next": shuffle / repeat / autoplay toggles, reorderable queue,
/// swipe to remove (ui/player/Queue.kt).
class QueueView extends ConsumerWidget {
  const QueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(nowPlayingProvider);
    final ai = ref.watch(aiShuffleProvider);
    final engine = ref.read(engineProvider);
    final settings = ref.watch(settingsProvider).value ?? const {};
    final autoplay = settings['similarContent'] as bool? ?? true;
    final upcoming = s.queue.length > s.queueIndex + 1 ? s.queue.sublist(s.queueIndex + 1) : const <Track>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Playing Next', style: HydeText.headline.copyWith(color: const Color(0xFFFFFFFF))),
                    Text(
                      s.track?.albumName == null ? 'From queue' : 'From ${s.track!.albumName}',
                      style: HydeText.footnote.copyWith(color: const Color(0x99FFFFFF)),
                    ),
                  ],
                ),
              ),
              _Toggle(
                icon: CupertinoIcons.shuffle,
                on: s.shuffle && !ai,
                onTap: () => setQueueShuffle(ref, enabled: !(s.shuffle && !ai)),
              ),
              const SizedBox(width: 10),
              _Toggle(
                icon: CupertinoIcons.sparkles,
                on: ai,
                onTap: () => setQueueShuffle(ref, enabled: !ai, smart: true),
              ),
              const SizedBox(width: 10),
              _Toggle(
                icon: s.repeat == QueueRepeat.one ? CupertinoIcons.repeat_1 : CupertinoIcons.repeat,
                on: s.repeat != QueueRepeat.off,
                onTap: () => engine.setRepeat(QueueRepeat.values[(s.repeat.index + 1) % QueueRepeat.values.length]),
              ),
              const SizedBox(width: 10),
              _Toggle(
                icon: CupertinoIcons.infinite,
                on: autoplay,
                onTap: () => ref.read(settingsProvider.notifier).set('similarContent', !autoplay),
              ),
            ],
          ),
        ),
        Expanded(
          child: upcoming.isEmpty
              ? Center(
                  child: Text('Nothing up next', style: HydeText.body.copyWith(color: const Color(0x99FFFFFF))),
                )
              : ReorderableList(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: upcoming.length,
                  onReorderItem: (from, to) => engine.moveQueueItem(s.queueIndex + 1 + from, s.queueIndex + 1 + to),
                  itemBuilder: (context, i) {
                    final t = upcoming[i];
                    return Dismissible(
                      key: ValueKey('${t.id}-$i'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => engine.removeQueueItem(s.queueIndex + 1 + i),
                      background: Container(
                        color: const Color(0xFFFF453A),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(CupertinoIcons.xmark, color: Color(0xFFFFFFFF)),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => engine.skipToQueueItem(s.queueIndex + 1 + i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 7),
                          child: Row(
                            children: [
                              Artwork(url: t.thumbnailUrl, size: 46, radius: 6),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: HydeText.callout.copyWith(color: const Color(0xFFFFFFFF)),
                                    ),
                                    Text(
                                      t.artistLine,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: HydeText.footnote.copyWith(color: const Color(0x99FFFFFF)),
                                    ),
                                  ],
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: i,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(CupertinoIcons.line_horizontal_3, color: Color(0x99FFFFFF)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.on, required this.onTap});
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 32,
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: on ? const Color(0x40FFFFFF) : const Color(0x14FFFFFF),
        ),
        child: Icon(icon, size: 18, color: on ? const Color(0xFFFFFFFF) : const Color(0x99FFFFFF)),
      ),
    );
  }
}
