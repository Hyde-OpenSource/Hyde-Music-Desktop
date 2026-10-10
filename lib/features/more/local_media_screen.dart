import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_controls.dart';
import '../../design/glass/glass_menu.dart';
import '../../design/glass/glass_toast.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../design/widgets/media_tiles.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import '../library/collection_screens.dart';
import 'feature_codec.dart';

final _localSongsProvider = FutureProvider.autoDispose((ref) async {
  ref.watch(featureStateProvider('local').select((s) => s.value?['count']));
  final raw = (await ref.watch(engineProvider).feature('local.songs') as List?) ?? const [];
  return [for (final m in raw.cast<Map>()) trackFromMap(m)];
});

/// Songs stored on the device, with a rescan button and live scan progress.
class LocalMediaScreen extends ConsumerWidget {
  const LocalMediaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(_localSongsProvider).value ?? const <Track>[];
    final scan = ref.watch(featureStateProvider('local')).value;
    final scanning = scan?['scanning'] == true;
    final progress = (scan?['progress'] as num?)?.toDouble() ?? 0;
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);

    Future<void> rescan() => guarded(context, () async {
      await ref.read(engineProvider).feature('local.scan');
    });

    return LargeTitleScaffold(
      title: 'On This Device',
      actions: [
        GlassPillButton(
          icon: CupertinoIcons.arrow_2_circlepath,
          label: scanning ? 'Scanning…' : 'Scan',
          onPressed: scanning ? null : rescan,
        ),
      ],
      slivers: [
        if (scanning)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 0, HydeMetrics.gutter + 4, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scanning your music… ${(progress * 100).round()}%',
                    style: HydeText.subhead.copyWith(color: secondary),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 6,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: HydeColors.separator.resolveFrom(context)),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress.clamp(0.0, 1.0),
                            child: const ColoredBox(color: HydeColors.accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (songs.isEmpty && !scanning)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
              child: Column(
                children: [
                  Icon(CupertinoIcons.device_phone_portrait, size: 54, color: secondary),
                  const SizedBox(height: 14),
                  Text(
                    'No music files found yet',
                    style: HydeText.title3.copyWith(color: HydeColors.label.resolveFrom(context)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap Scan to find songs stored on this phone.',
                    textAlign: TextAlign.center,
                    style: HydeText.subhead.copyWith(color: secondary),
                  ),
                  const SizedBox(height: 18),
                  CupertinoButton.filled(onPressed: rescan, child: const Text('Scan Now')),
                ],
              ),
            ),
          ),
        if (songs.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 0, HydeMetrics.gutter, 6),
              child: Text('${songs.length} songs', style: HydeText.subhead.copyWith(color: secondary)),
            ),
          ),
        SliverList.builder(
          itemCount: songs.length,
          itemBuilder: (context, i) => Builder(
            builder: (rowContext) => MediaRow(
              item: TrackItem(songs[i]),
              onTap: () => guarded(context, () => ref.read(engineProvider).playTracks(songs, startIndex: i)),
              onLongPress: () => showSongMenu(context, ref, songs[i], globalRectOf(rowContext)),
            ),
          ),
        ),
      ],
    );
  }
}
