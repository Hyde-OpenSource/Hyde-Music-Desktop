import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/glass/glass_switch.dart';
import '../../design/widgets/grouped_list.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../engine/hyde_engine.dart';
import '../../engine/models.dart';
import '../../state/providers.dart';

/// Latest updater state; starts from a fresh check when first watched.
final updateStatusProvider = StreamProvider<UpdateStatus>((ref) async* {
  final engine = ref.watch(engineProvider);
  final first = engine.updates;
  yield await engine.checkForUpdate(manual: true);
  yield* first;
});

/// Settings ▸ Software Update (Hyde's in-app updater, see flutter/HydeUpdater.kt).
class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(updateStatusProvider).value ?? UpdateStatus.initial;
    final engine = ref.read(engineProvider);
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final label = HydeColors.label.resolveFrom(context);
    final r = status.release;

    return LargeTitleScaffold(
      title: 'Software Update',
      slivers: [
        SliverToBoxAdapter(
          child: GroupedSection(
            separatorIndent: 16,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipRSuperellipse(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset('assets/hyde_logo.png', width: 60, height: 60),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r == null ? 'Hyde Music ${status.currentVersion}' : r.name,
                                style: HydeText.headline.copyWith(fontSize: 19, color: label),
                              ),
                              const SizedBox(height: 2),
                              Text(_subtitle(status), style: HydeText.subhead.copyWith(color: secondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (status.phase == UpdatePhase.downloading) ...[
                      const SizedBox(height: 16),
                      _Progress(value: status.progress),
                      const SizedBox(height: 8),
                      Text(_progressLine(status), style: HydeText.footnote.copyWith(color: secondary)),
                    ],
                    if (status.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        status.error!,
                        style: HydeText.footnote.copyWith(color: CupertinoColors.systemRed.resolveFrom(context)),
                      ),
                    ],
                    if (r != null && r.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(r.notes.trim(), style: HydeText.subhead.copyWith(color: label, height: 1.35)),
                    ],
                    if (r != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            r.verifiedChecksum ? CupertinoIcons.checkmark_shield_fill : CupertinoIcons.checkmark_shield,
                            size: 16,
                            color: r.verifiedChecksum ? CupertinoColors.systemGreen : secondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              r.verifiedChecksum
                                  ? 'Checksum and signature verified before install'
                                  : 'Signature verified before install',
                              style: HydeText.footnote.copyWith(color: secondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              ..._actions(context, status, engine),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            header: 'Automatic updates',
            footer: status.lastChecked == null ? null : 'Last checked ${_ago(status.lastChecked!)}',
            separatorIndent: 16,
            children: [
              _ToggleRow(
                title: 'Check automatically',
                value: status.autoCheck,
                onChanged: (v) => engine.setUpdatePrefs(autoCheck: v),
              ),
              _ToggleRow(
                title: 'Download in background',
                value: status.autoDownload,
                onChanged: (v) => engine.setUpdatePrefs(autoDownload: v),
              ),
              _ToggleRow(
                title: 'Only on Wi-Fi',
                value: status.wifiOnly,
                onChanged: (v) => engine.setUpdatePrefs(wifiOnly: v),
              ),
              _ToggleRow(
                title: 'Beta updates',
                subtitle: 'Get pre-release builds early',
                value: status.beta,
                onChanged: (v) async {
                  await engine.setUpdatePrefs(beta: v);
                  await engine.checkForUpdate();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _actions(BuildContext context, UpdateStatus s, HydeEngine engine) {
    Widget primary(String text, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: GlassPressable(
        onTap: onTap,
        pressedScale: 0.97,
        stretch: 0,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: HydeColors.accent,
            shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(text, style: HydeText.headline.copyWith(color: const Color(0xFFFFFFFF))),
        ),
      ),
    );
    return switch (s.phase) {
      UpdatePhase.available => [
        primary('Download and Install', engine.downloadUpdate),
        GroupedRow(title: 'Skip This Version', destructive: true, chevron: false, onTap: engine.skipUpdate),
      ],
      UpdatePhase.downloading => [
        GroupedRow(title: 'Cancel Download', destructive: true, chevron: false, onTap: engine.cancelUpdate),
      ],
      UpdatePhase.ready => [primary('Install Now', engine.installUpdate)],
      UpdatePhase.failed when s.release != null => [primary('Try Again', engine.installUpdate)],
      UpdatePhase.checking || UpdatePhase.installing => [
        const Padding(padding: EdgeInsets.only(bottom: 16), child: CupertinoActivityIndicator()),
      ],
      _ => [GroupedRow(title: 'Check Now', chevron: false, onTap: () => engine.checkForUpdate())],
    };
  }

  static String _subtitle(UpdateStatus s) => switch (s.phase) {
    UpdatePhase.checking => 'Checking for updates…',
    UpdatePhase.upToDate || UpdatePhase.idle => 'Hyde Music is up to date',
    UpdatePhase.available => '${_size(s.release!.size)}${s.release!.prerelease ? ' · Beta' : ''}',
    UpdatePhase.downloading => 'Downloading…',
    UpdatePhase.ready => 'Downloaded and verified',
    UpdatePhase.installing => 'Installing…',
    UpdatePhase.failed => s.release == null ? 'Couldn’t check for updates' : 'Update paused',
  };

  static String _progressLine(UpdateStatus s) {
    final remaining = s.speed <= 0 ? null : Duration(seconds: ((s.total - s.bytes) / s.speed).ceil());
    final eta = remaining == null
        ? ''
        : remaining.inMinutes > 0
        ? ' · about ${remaining.inMinutes} min left'
        : ' · ${remaining.inSeconds}s left';
    return '${_size(s.bytes)} of ${_size(s.total)} · ${_size(s.speed)}/s$eta';
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 8,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: HydeColors.separator.resolveFrom(context)),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: const ColoredBox(color: HydeColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GroupedRow(
    title: title,
    subtitle: subtitle,
    trailing: GlassSwitch(value: value, onChanged: onChanged),
  );
}
