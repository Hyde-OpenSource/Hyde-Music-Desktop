import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_menu.dart';
import '../../design/glass/glass_toast.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../design/widgets/media_tiles.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';
import '../library/collection_screens.dart';
import 'feature_codec.dart';

final _historyProvider = FutureProvider.autoDispose((ref) async {
  final raw = (await ref.watch(engineProvider).feature('history.list') as List?) ?? const [];
  return [
    for (final e in raw.cast<Map>())
      (
        id: (e['id'] as num).toInt(),
        at: DateTime.fromMillisecondsSinceEpoch((e['timestamp'] as num).toInt()),
        track: trackFromMap(e['track'] as Map),
      ),
  ];
});

/// Listening history grouped by day; swipe a row left to remove it.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  static String _day(DateTime d) {
    final today = DateTime.now();
    final date = DateTime(d.year, d.month, d.day);
    final diff = DateTime(today.year, today.month, today.day).difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]}${d.year == today.year ? '' : ' ${d.year}'}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(_historyProvider);
    final entries = history.value ?? const [];
    final tracks = [for (final e in entries) e.track];
    final widgets = <Widget>[];
    String? lastDay;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final day = _day(e.at);
      if (day != lastDay) {
        lastDay = day;
        widgets.add(SliverToBoxAdapter(child: SectionHeader(title: day)));
      }
      widgets.add(
        SliverToBoxAdapter(
          child: Dismissible(
            key: ValueKey('h${e.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: CupertinoColors.systemRed,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: const Icon(CupertinoIcons.trash, color: Color(0xFFFFFFFF)),
            ),
            onDismissed: (_) => guarded(context, () async {
              await ref.read(engineProvider).feature('history.remove', {'id': e.id});
              ref.invalidate(_historyProvider);
            }),
            child: Builder(
              builder: (rowContext) => MediaRow(
                item: TrackItem(e.track),
                onTap: () => guarded(context, () => ref.read(engineProvider).playTracks(tracks, startIndex: i)),
                onLongPress: () => showSongMenu(context, ref, e.track, globalRectOf(rowContext)),
              ),
            ),
          ),
        ),
      );
    }

    return LargeTitleScaffold(
      title: 'History',
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: () => ref.refresh(_historyProvider.future)),
        if (history.isLoading && entries.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.only(top: 80), child: CupertinoActivityIndicator()),
          )
        else if (entries.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Text(
                'Songs you play will show up here',
                textAlign: TextAlign.center,
                style: HydeText.body.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
              ),
            ),
          ),
        ...widgets,
      ],
    );
  }
}
