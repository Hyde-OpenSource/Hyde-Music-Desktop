import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_sheets.dart';
import '../../design/glass/glass_controls.dart';
import '../../design/glass/glass_switch.dart';
import '../../design/glass/glass_shader.dart';
import '../../design/widgets/grouped_list.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../state/providers.dart';
import '../library/collection_screens.dart';
import '../../design/glass/glass_toast.dart';
import '../../engine/mock_engine.dart';
import '../more/account_screens.dart';
import '../more/feature_codec.dart';
import '../more/local_media_screen.dart';
import '../more/misc_screens.dart';
import '../more/social_screens.dart';
import '../player/player_actions.dart';
import 'settings_catalog.dart';
import 'updates_screen.dart';

/// Settings root (reference screenshots): search, account card, grouped pages.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final values = ref.watch(settingsProvider).value ?? const {};
    final name = (values['accountName'] as String?)?.trim();
    final q = _query.trim().toLowerCase();

    return LargeTitleScaffold(
      title: 'Settings',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 0, HydeMetrics.gutter, 22),
            child: HydeSearchField(placeholder: 'Search settings', onChanged: (v) => setState(() => _query = v)),
          ),
        ),
        if (q.isNotEmpty)
          SliverToBoxAdapter(child: _SearchResults(query: q))
        else ...[
          SliverToBoxAdapter(
            child: GroupedSection(
              children: [
                GroupedRow(
                  title: name == null || name.isEmpty ? 'Sign in' : name,
                  subtitle: name == null || name.isEmpty ? 'Your Hyde account' : values['accountEmail'] as String?,
                  leading: SizedBox(
                    width: 30,
                    child: Text(
                      (name == null || name.isEmpty) ? 'H' : name.characters.first.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: HydeText.title1.copyWith(color: HydeColors.accent),
                    ),
                  ),
                  trailing: const Icon(CupertinoIcons.chevron_forward, color: HydeColors.accent, size: 20),
                  onTap: () => openSettingsPage(context, accountPage),
                ),
              ],
            ),
          ),
          for (final group in settingsGroups)
            if (group.any(isPageAvailable))
            SliverToBoxAdapter(
              child: GroupedSection(
                children: [
                  for (final page in group.where(isPageAvailable))
                    GroupedRow(
                      title: page.title,
                      icon: page.icon,
                      iconColor: page.color is CupertinoDynamicColor
                          ? (page.color as CupertinoDynamicColor).resolveFrom(context)
                          : page.color,
                      onTap: () => openSettingsPage(context, page),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

void openSettingsPage(BuildContext context, SettingsPage page) {
  // Pages that are full Flutter screens rather than settings lists.
  final Widget screen = switch (page.id) {
    'account' => const AccountScreen(),
    'about' => const AboutScreen(),
    'support' => const SupportScreen(),
    'logs' => const LogsScreen(),
    'hydesync' => const HydeSyncScreen(),
    _ => SettingsPageScreen(page: page),
  };
  Navigator.of(context).push(CupertinoPageRoute(builder: (_) => screen));
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final hits = [
      for (final (page, item) in allSettings())
        if (isSettingAvailable(item) &&
            (item.title.toLowerCase().contains(query) || (item.subtitle?.toLowerCase().contains(query) ?? false)))
          (page, item),
    ];
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          'No results',
          textAlign: TextAlign.center,
          style: HydeText.body.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
        ),
      );
    }
    return GroupedSection(
      separatorIndent: 16,
      children: [
        for (final (page, item) in hits)
          GroupedRow(title: item.title, subtitle: page.title, onTap: () => openSettingsPage(context, page)),
      ],
    );
  }
}

/// Renders any [SettingsPage] from the catalog.
class SettingsPageScreen extends ConsumerWidget {
  const SettingsPageScreen({super.key, required this.page});
  final SettingsPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = ref.watch(settingsProvider).value ?? const {};
    return LargeTitleScaffold(
      title: page.title,
      slivers: [
        for (final section in visibleSections(page))
          SliverToBoxAdapter(
            child: GroupedSection(
              header: section.header,
              footer: section.footer,
              separatorIndent: 16,
              children: [for (final item in section.items) _SettingRow(item: item, values: values)],
            ),
          ),
      ],
    );
  }
}

class _SettingRow extends ConsumerWidget {
  const _SettingRow({required this.item, required this.values});
  final SettingItem item;
  final Map<String, Object?> values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsProvider.notifier);
    switch (item) {
      case ToggleSetting(:final key, :final defaultValue):
        final on = values[key] as bool? ?? defaultValue;
        return GroupedRow(
          title: item.title,
          subtitle: item.subtitle,
          trailing: GlassSwitch(value: on, onChanged: (v) => settings.set(key, v)),
        );
      case ChoiceSetting(:final key, :final options, :final defaultValue):
        final current = values[key]?.toString() ?? defaultValue;
        final label = options.firstWhere((o) => o.$1 == current, orElse: () => options.first).$2;
        return GroupedRow(
          title: item.title,
          subtitle: item.subtitle,
          value: label,
          onTap: () => _pickChoice(context, settings, item as ChoiceSetting, current),
        );
      case SliderSetting(
        :final key,
        :final min,
        :final max,
        :final defaultValue,
        :final divisions,
        :final unit,
        :final isInt,
      ):
        final v = ((values[key] as num?)?.toDouble() ?? defaultValue).clamp(min, max);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: HydeText.body.copyWith(color: HydeColors.label.resolveFrom(context)),
                    ),
                  ),
                  Text(
                    '${isInt || v >= 10 ? v.round() : v.toStringAsFixed(2)}$unit',
                    style: HydeText.body.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
                  ),
                ],
              ),
              GlassSlider(
                value: v,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: (n) => settings.set(key, isInt ? n.round() : n),
              ),
            ],
          ),
        );
      case TextSetting(:final key, :final placeholder, :final secret):
        final current = values[key] as String? ?? '';
        return GroupedRow(
          title: item.title,
          value: current.isEmpty ? (placeholder.isEmpty ? 'Not set' : placeholder) : (secret ? '••••••' : current),
          onTap: () => _editText(context, settings, item as TextSetting, current),
        );
      case ActionSetting(:final action, :final destructive, :final confirm):
        return GroupedRow(
          title: item.title,
          subtitle: item.subtitle,
          destructive: destructive,
          chevron: !destructive,
          onTap: () async {
            if (confirm != null) {
              final ok = await showGlassDialog<bool>(
                context: context,
                builder: (context) => GlassAlertDialog(
                  title: Text(item.title),
                  content: Text(confirm),
                  actions: [
                    GlassDialogAction(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    GlassDialogAction(
                      isDestructiveAction: destructive,
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
            }
            if (context.mounted) await runSettingAction(context, ref, action);
          },
        );
      case InfoSetting(:final info):
        return GroupedRow(
          title: item.title,
          value: switch (info) {
            'glass.renderer' => GlassShader.status,
            'discord.user' => _signedIn(values['discordUsername']),
            'lastfm.user' => _signedIn(values['lastfmUsername']),
            'engine' => ref.read(engineProvider) is MockEngine ? 'Demo data' : 'Hyde engine (Dart)',
            _ => null,
          },
          trailing: info.startsWith('storage.') ? _StorageUsage(kind: info.substring(8)) : null,
        );
      case PageLink(:final page):
        return GroupedRow(title: page.title, subtitle: item.subtitle, onTap: () => openSettingsPage(context, page));
    }
  }

  Future<void> _pickChoice(BuildContext context, SettingsNotifier settings, ChoiceSetting s, String current) {
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => GlassActionSheet(
        title: Text(s.title),
        actions: [
          for (final (value, label) in s.options)
            GlassSheetAction(
              isDefaultAction: value == current,
              onPressed: () {
                settings.set(s.key, value);
                if (s.key == 'glassQuality') GlassShader.enabled = value == 'FULL';
                Navigator.pop(context);
              },
              child: Text(label),
            ),
        ],
        cancelButton: GlassSheetAction(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ),
    );
  }

  Future<void> _editText(BuildContext context, SettingsNotifier settings, TextSetting s, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showGlassDialog<String>(
      context: context,
      builder: (context) => GlassAlertDialog(
        title: Text(s.title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            obscureText: s.secret,
            placeholder: s.placeholder,
          ),
        ),
        actions: [
          GlassDialogAction(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          GlassDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) await settings.set(s.key, result.trim());
  }
}

/// Executes an [ActionSetting] via [settingActionTargets].
Future<void> runSettingAction(BuildContext context, WidgetRef ref, String action) async {
  final engine = ref.read(engineProvider);
  final target = settingActionTargets[action];
  if (target == null) return;
  final (kind, value) = (target.split(':').first, target.substring(target.indexOf(':') + 1));
  switch (kind) {
    case 'system':
      await engine.systemAction(value);
    case 'feature':
      final parts = value.split('?');
      await guarded(context, () async {
        final r = await engine.feature(parts.first, {if (parts.length > 1) 'kind': parts[1]});
        ref.invalidate(settingsProvider);
        ref.invalidate(storageUsageProvider);
        if (context.mounted && r != false) showGlassToast(context, 'Done', icon: CupertinoIcons.checkmark_circle);
      });
    case 'dialog':
      if (value == 'lastfm') await showLastFmLogin(context, ref);
    case 'import':
      await guarded(context, () async {
        final raw = (await engine.feature(value == 'csv' ? 'import.csv' : 'import.m3u') as List?) ?? const [];
        final tracks = [for (final m in raw.cast<Map>()) trackFromMap(m)];
        if (tracks.isEmpty || !context.mounted) return;
        await showAddToPlaylist(context, ref, tracks);
      });
    case 'flutter':
      final Widget page = switch (value) {
        'updates' => const UpdatesScreen(),
        'account' => const AccountScreen(),
        'discordLogin' => const WebLoginScreen(mode: 'discord'),
        'listenTogether' => const ListenTogetherScreen(),
        'logs' => const LogsScreen(),
        'hydesync' => const HydeSyncScreen(),
        'nearby' => const NearbySyncScreen(),
        'local' => const LocalMediaScreen(),
        'spotify' => const SpotifyImportScreen(),
        'support' => const SupportScreen(),
        'about' => const AboutScreen(),
        _ => const CollectionScreen(collection: LibraryCollection.downloads),
      };
      if (context.mounted) await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => page));
      ref.invalidate(settingsProvider);
  }
}

String _signedIn(Object? name) {
  final n = (name as String?)?.trim() ?? '';
  return n.isEmpty ? 'Not signed in' : n;
}

final storageUsageProvider = FutureProvider.autoDispose<Map<String, Object?>>((ref) async {
  return ((await ref.watch(engineProvider).feature('storage.usage')) as Map?)?.cast<String, Object?>() ?? const {};
});

class _StorageUsage extends ConsumerWidget {
  const _StorageUsage({required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(storageUsageProvider).value;
    final bytes = (usage?[kind] as num?)?.toInt();
    return Text(
      bytes == null ? '…' : formatBytes(bytes),
      style: HydeText.body.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
    );
  }
}
