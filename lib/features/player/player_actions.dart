import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_sheets.dart';
import '../../design/glass/glass_menu.dart';
import '../../design/glass/glass_style.dart';
import '../../design/glass/glass_switch.dart';
import '../../design/glass/glass_toast.dart';
import '../library/detail_screens.dart' show promptText;
import '../../design/glass/liquid_glass.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';

/// The ••• menu of the player (ui/menu/PlayerMenu.kt) as a glass popover.
Future<void> showPlayerMenu(BuildContext context, WidgetRef ref, Rect anchor) {
  final engine = ref.read(engineProvider);
  final s = ref.read(nowPlayingProvider);
  final t = s.track;
  if (t == null) return Future.value();
  final artist = t.artists.isEmpty ? null : t.artists.first;

  return showGlassMenu(
    context,
    anchor: anchor,
    menu: GlassMenu(
      quickActions: [
        GlassMenuAction(
          icon: t.liked ? CupertinoIcons.star_fill : CupertinoIcons.star,
          label: t.liked ? 'Favorited' : 'Favorite',
          onSelected: () => engine.setLiked(t, !t.liked),
        ),
        GlassMenuAction(
          icon: CupertinoIcons.square_arrow_up,
          label: 'Share',
          onSelected: () async {
            await engine.share(await engine.shareLink(TrackItem(t)));
          },
        ),
      ],
      sections: [
        [
          GlassMenuAction(
            icon: CupertinoIcons.text_badge_plus,
            label: 'Add to playlist',
            onSelected: () => showAddToPlaylist(context, ref, [t]),
          ),
          GlassMenuAction(
            icon: t.isDownloaded ? CupertinoIcons.xmark_circle : CupertinoIcons.arrow_down_circle,
            label: t.isDownloaded ? 'Remove download' : 'Download',
            onSelected: () => t.isDownloaded ? engine.removeDownload([t]) : engine.download([t]),
          ),
        ],
        [
          if (t.albumName != null)
            GlassMenuAction(
              icon: CupertinoIcons.square_stack,
              label: 'Go to Album',
              subtitle: t.albumName,
              onSelected: () => goToCollection(context, ref, 'album', t.albumId),
            ),
          if (artist != null)
            GlassMenuAction(
              icon: CupertinoIcons.mic,
              label: 'Go to Artist',
              subtitle: artist.name,
              onSelected: () => goToCollection(context, ref, 'artist', artist.id),
            ),
          GlassMenuAction(
            icon: CupertinoIcons.dot_radiowaves_left_right,
            label: 'Start radio',
            onSelected: () => engine.startRadio(t),
          ),
          GlassMenuAction(
            icon: CupertinoIcons.info_circle,
            label: 'Details',
            onSelected: () => showDetails(context, s),
          ),
        ],
        [
          GlassMenuAction(
            icon: CupertinoIcons.moon_zzz,
            label: 'Sleep timer',
            subtitle: s.sleepTimerEnd == null ? null : 'Ends ${_hm(s.sleepTimerEnd!)}',
            onSelected: () => showSleepTimer(context, ref),
          ),
          GlassMenuAction(
            icon: CupertinoIcons.slider_horizontal_3,
            label: 'Equalizer',
            onSelected: () => guarded(context, () => engine.systemAction('equalizer')),
          ),
          GlassMenuAction(
            icon: CupertinoIcons.speedometer,
            label: 'Tempo & pitch',
            onSelected: () => showTempoPitch(context, ref),
          ),
        ],
      ],
    ),
  );
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Future<void> showSleepTimer(BuildContext context, WidgetRef ref) {
  final engine = ref.read(engineProvider);
  final active = ref.read(nowPlayingProvider).sleepTimerEnd != null;
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => GlassActionSheet(
      title: const Text('Sleep Timer'),
      actions: [
        for (final m in const [5, 10, 15, 30, 45, 60])
          GlassSheetAction(
            onPressed: () {
              engine.setSleepTimer(Duration(minutes: m));
              Navigator.pop(context);
            },
            child: Text('$m minutes'),
          ),
        GlassSheetAction(
          onPressed: () {
            engine.setSleepTimer(null, endOfTrack: true);
            Navigator.pop(context);
          },
          child: const Text('End of song'),
        ),
        if (active)
          GlassSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              engine.setSleepTimer(null);
              Navigator.pop(context);
            },
            child: const Text('Turn Off Timer'),
          ),
      ],
      cancelButton: GlassSheetAction(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
    ),
  );
}

Future<void> showAddToPlaylist(BuildContext context, WidgetRef ref, List<Track> tracks) async {
  final engine = ref.read(engineProvider);
  final playlists = await engine.libraryPlaylists();
  if (!context.mounted) return;
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => GlassActionSheet(
      title: const Text('Add to Playlist'),
      actions: [
        GlassSheetAction(
          onPressed: () async {
            Navigator.pop(context);
            final name = await promptText(context, title: 'New Playlist');
            if (name == null || name.isEmpty || !context.mounted) return;
            await guarded(context, () async {
              final p = await engine.createPlaylist(name);
              await engine.addToPlaylist(p.id, tracks);
              if (context.mounted) showGlassToast(context, 'Added to $name', icon: CupertinoIcons.checkmark_circle);
            });
          },
          child: const Text('New Playlist…'),
        ),
        for (final p in playlists.where((p) => p.kind == PlaylistKind.local || p.kind == PlaylistKind.liked))
          GlassSheetAction(
            onPressed: () {
              Navigator.pop(context);
              guarded(context, () async {
                await engine.addToPlaylist(p.id, tracks);
                if (context.mounted) showGlassToast(context, 'Added to ${p.name}', icon: CupertinoIcons.checkmark_circle);
              });
            },
            child: Text(p.name),
          ),
      ],
      cancelButton: GlassSheetAction(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
    ),
  );
}

Future<void> showDetails(BuildContext context, PlaybackSnapshot s) {
  final t = s.track!;
  final f = s.format;
  return showGlassDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => GlassAlertDialog(
      title: Text(t.title),
      content: Text(
        [
          t.artistLine,
          if (t.albumName != null) t.albumName!,
          'ID: ${t.id}',
          if (f != null) f.label,
          if (f?.loudnessDb != null) 'Loudness: ${f!.loudnessDb!.toStringAsFixed(1)} dB',
        ].join('\n'),
      ),
      actions: [GlassDialogAction(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );
}

/// Closes the full player (if open) and opens an album / artist page.
void goToCollection(BuildContext context, WidgetRef ref, String type, String? id) {
  if (id == null) return;
  final root = Navigator.of(context, rootNavigator: true);
  if (root.canPop()) root.pop();
  ref.read(appNavigationProvider).add(NavigationEvent('collection', {'type': type, 'id': id}));
}

/// Tempo & pitch sheet with Liquid Glass sliders (native PlayerMenu "tempo_and_pitch").
Future<void> showTempoPitch(BuildContext context, WidgetRef ref) async {
  final engine = ref.read(engineProvider);
  var p = await engine.playbackParameters();
  if (!context.mounted) return;
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Widget row(String title, double value, ValueChanged<double> onChanged) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: HydeText.headline.copyWith(color: const Color(0xFFFFFFFF))),
                  ),
                  Text('${value.toStringAsFixed(2)}×', style: HydeText.body.copyWith(color: const Color(0x99FFFFFF))),
                ],
              ),
              GlassSlider(value: value, min: 0.5, max: 2.0, divisions: 30, onChanged: onChanged),
            ],
          ),
        );
        void apply(({double speed, double pitch}) next) {
          setState(() => p = next);
          engine.setPlaybackParameters(speed: next.speed, pitch: next.pitch);
        }

        return LiquidGlass(
          radius: 34,
          style: GlassStyle.menu,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  row('Tempo', p.speed, (v) => apply((speed: v, pitch: p.pitch))),
                  row('Pitch', p.pitch, (v) => apply((speed: p.speed, pitch: v))),
                  CupertinoButton(
                    onPressed: () => apply((speed: 1, pitch: 1)),
                    child: const Text('Reset', style: TextStyle(color: HydeColors.accent)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
