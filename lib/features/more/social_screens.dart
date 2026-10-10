import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_menu.dart';
import '../../design/glass/glass_pressable.dart';
import '../../design/glass/glass_style.dart';
import '../../design/glass/glass_switch.dart';
import '../../design/glass/glass_toast.dart';
import '../../design/glass/liquid_glass.dart';
import '../../design/widgets/artwork.dart';
import '../../design/widgets/grouped_list.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../state/providers.dart';

/// Listen Together: create or join a room, see who's listening, approve
/// requests, manage people, chat and accept song suggestions.
class ListenTogetherScreen extends ConsumerStatefulWidget {
  const ListenTogetherScreen({super.key});

  @override
  ConsumerState<ListenTogetherScreen> createState() => _ListenTogetherScreenState();
}

class _ListenTogetherScreenState extends ConsumerState<ListenTogetherScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _chat = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(settingsProvider).value?['listenTogetherUsername'] as String? ?? '';
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _chat.dispose();
    super.dispose();
  }

  Future<void> _call(String method, [Map<String, Object?> args = const {}]) =>
      guarded(context, () => ref.read(engineProvider).feature(method, args));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(featureStateProvider('listenTogether')).value ?? const {};
    final room = (s['room'] as Map?)?.cast<String, Object?>();
    final connection = s['connection'] as String? ?? 'DISCONNECTED';
    final isHost = s['role'] == 'HOST';
    final me = s['me'] as String?;
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    final label = HydeColors.label.resolveFrom(context);

    return LargeTitleScaffold(
      title: 'Listen Together',
      slivers: [
        if (room == null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 0, HydeMetrics.gutter + 4, 16),
              child: Text(
                'Play music in sync with friends anywhere. Create a room and share the code, or join theirs.',
                style: HydeText.subhead.copyWith(color: secondary),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: GroupedSection(
              header: 'Your name',
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: CupertinoTextField(
                    controller: _name,
                    placeholder: 'Username',
                    padding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: GroupedSection(
              children: [
                GroupedRow(
                  title: 'Create a Room',
                  subtitle: 'You control playback',
                  icon: CupertinoIcons.plus_circle_fill,
                  iconColor: HydeColors.accent,
                  onTap: () => _call('lt.create', {'username': _name.text}),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: GroupedSection(
              header: 'Join a friend',
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: _code,
                          placeholder: 'Room code',
                          textCapitalization: TextCapitalization.characters,
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        onPressed: () => _call('lt.join', {'code': _code.text, 'username': _name.text}),
                        child: const Text('Join'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (connection != 'DISCONNECTED')
            SliverToBoxAdapter(
              child: Center(
                child: Text(_connectionLabel(connection), style: HydeText.footnote.copyWith(color: secondary)),
              ),
            ),
        ] else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter, 0, HydeMetrics.gutter, 18),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(26)),
                  gradient: const LinearGradient(colors: [Color(0xFFFA2D48), Color(0xFF7D3CFF)]),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ROOM CODE',
                            style: HydeText.caption.copyWith(color: const Color(0xCCFFFFFF), letterSpacing: 2),
                          ),
                          Text(
                            room['code'] as String? ?? '',
                            style: HydeText.largeTitle.copyWith(color: const Color(0xFFFFFFFF), letterSpacing: 4),
                          ),
                          Text(
                            '${isHost ? 'You are the host' : 'You are listening along'} · ${_connectionLabel(connection)}',
                            style: HydeText.footnote.copyWith(color: const Color(0xDDFFFFFF)),
                          ),
                        ],
                      ),
                    ),
                    GlassPressable(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: room['code'] as String? ?? ''));
                        showGlassToast(context, 'Room code copied', icon: CupertinoIcons.doc_on_doc);
                      },
                      child: const LiquidGlass.capsule(
                        style: GlassStyle.clear,
                        child: SizedBox.square(
                          dimension: 46,
                          child: Icon(CupertinoIcons.doc_on_doc, color: Color(0xFFFFFFFF)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (room['track'] is Map)
            SliverToBoxAdapter(
              child: GroupedSection(
                header: 'Now playing',
                children: [
                  GroupedRow(
                    title: (room['track'] as Map)['title'] as String? ?? '',
                    subtitle: (room['track'] as Map)['artist'] as String?,
                    leading: Artwork(url: (room['track'] as Map)['thumbnailUrl'] as String?, size: 44, radius: 8),
                  ),
                ],
              ),
            ),
          if (isHost && ((s['pending'] as List?) ?? const []).isNotEmpty)
            SliverToBoxAdapter(
              child: GroupedSection(
                header: 'Wants to join',
                children: [
                  for (final p in ((s['pending'] as List?) ?? const []).cast<Map>())
                    GroupedRow(
                      title: p['name'] as String? ?? '',
                      chevron: false,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            onPressed: () => _call('lt.reject', {'userId': p['id']}),
                            child: const Text('Decline', style: TextStyle(color: CupertinoColors.systemRed)),
                          ),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            onPressed: () => _call('lt.approve', {'userId': p['id']}),
                            child: const Text('Allow'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          SliverToBoxAdapter(
            child: GroupedSection(
              header: 'People',
              children: [
                for (final u in ((room['users'] as List?) ?? const []).cast<Map>())
                  Builder(
                    builder: (rowContext) => GroupedRow(
                      title: '${u['name']}${u['id'] == me ? ' (you)' : ''}',
                      subtitle: u['host'] == true ? 'Host' : (u['online'] == true ? 'Listening' : 'Reconnecting…'),
                      icon: u['host'] == true ? CupertinoIcons.star_circle_fill : CupertinoIcons.person_circle_fill,
                      iconColor: u['host'] == true ? HydeColors.yellow : secondary,
                      chevron: isHost && u['id'] != me,
                      onTap: isHost && u['id'] != me
                          ? () => showGlassMenu(
                              context,
                              anchor: globalRectOf(rowContext),
                              menu: GlassMenu(
                                sections: [
                                  [
                                    GlassMenuAction(
                                      icon: CupertinoIcons.star,
                                      label: 'Make host',
                                      onSelected: () => _call('lt.transferHost', {'userId': u['id']}),
                                    ),
                                    GlassMenuAction(
                                      icon: CupertinoIcons.person_badge_minus,
                                      label: 'Remove',
                                      onSelected: () => _call('lt.kick', {'userId': u['id']}),
                                    ),
                                    GlassMenuAction(
                                      icon: CupertinoIcons.nosign,
                                      label: 'Block',
                                      destructive: true,
                                      onSelected: () => _call('lt.block', {'username': u['name']}),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          if (isHost)
            SliverToBoxAdapter(
              child: GroupedSection(
                children: [
                  GroupedRow(
                    title: 'Let others control music',
                    trailing: GlassSwitch(
                      value: room['allowControl'] == true,
                      onChanged: (v) => _call('lt.allowControl', {'allow': v}),
                    ),
                  ),
                ],
              ),
            ),
          if (((s['suggestions'] as List?) ?? const []).isNotEmpty)
            SliverToBoxAdapter(
              child: GroupedSection(
                header: 'Suggestions',
                children: [
                  for (final g in ((s['suggestions'] as List?) ?? const []).cast<Map>())
                    GroupedRow(
                      title: g['title'] as String? ?? '',
                      subtitle: '${g['artist']} · from ${g['by']}',
                      chevron: false,
                      trailing: isHost
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  onPressed: () => _call('lt.rejectSuggestion', {'id': g['id']}),
                                  child: const Icon(CupertinoIcons.xmark, color: CupertinoColors.systemRed),
                                ),
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  onPressed: () => _call('lt.approveSuggestion', {'id': g['id']}),
                                  child: const Icon(CupertinoIcons.checkmark_alt),
                                ),
                              ],
                            )
                          : null,
                    ),
                ],
              ),
            ),
          SliverToBoxAdapter(
            child: GroupedSection(
              header: 'Chat',
              children: [
                for (final m
                    in ((s['chat'] as List?) ?? const []).cast<Map>().toList().reversed.take(30).toList().reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m['user']}  ',
                          style: HydeText.subhead.copyWith(color: HydeColors.accent, fontWeight: FontWeight.w600),
                        ),
                        Expanded(
                          child: Text(m['text'] as String? ?? '', style: HydeText.subhead.copyWith(color: label)),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: CupertinoTextField(
                    controller: _chat,
                    placeholder: 'Message',
                    padding: const EdgeInsets.all(12),
                    suffix: CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      onPressed: () {
                        final text = _chat.text.trim();
                        if (text.isEmpty) return;
                        _call('lt.chat', {'message': text});
                        _chat.clear();
                      },
                      child: const Icon(CupertinoIcons.arrow_up_circle_fill, size: 28),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: GroupedSection(
              children: [
                if (connection == 'ERROR' || connection == 'RECONNECTING')
                  GroupedRow(title: 'Reconnect', chevron: false, onTap: () => _call('lt.reconnect')),
                GroupedRow(title: 'Leave Room', destructive: true, chevron: false, onTap: () => _call('lt.leave')),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _connectionLabel(String c) => switch (c) {
    'CONNECTED' => 'Connected',
    'CONNECTING' => 'Connecting…',
    'RECONNECTING' => 'Reconnecting…',
    'ERROR' => 'Connection problem',
    _ => 'Offline',
  };
}

/// Nearby Sync: play in sync with phones on the same Wi-Fi.
class NearbySyncScreen extends ConsumerWidget {
  const NearbySyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(featureStateProvider('nearby')).value ?? const {};
    final state = s['state'] as String? ?? 'idle';
    final devices = ((s['devices'] as List?) ?? const []).cast<String>();
    final song = (s['song'] as Map?)?.cast<String, Object?>();
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);
    Future<void> call(String m, [Map<String, Object?> a = const {}]) =>
        guarded(context, () => ref.read(engineProvider).feature(m, a));

    return LargeTitleScaffold(
      title: 'Nearby Sync',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 0, HydeMetrics.gutter + 4, 18),
            child: Text(
              'Play the same music in sync on phones connected to the same Wi-Fi.',
              style: HydeText.subhead.copyWith(color: secondary),
            ),
          ),
        ),
        switch (state) {
          'hosting' => SliverToBoxAdapter(
            child: GroupedSection(
              children: [
                GroupedRow(
                  title: 'You are the controller',
                  subtitle: '${s['clients'] ?? 0} connected · play, pause and seek control everyone',
                  icon: CupertinoIcons.dot_radiowaves_left_right,
                  iconColor: HydeColors.accent,
                ),
                GroupedRow(title: 'Stop Session', destructive: true, chevron: false, onTap: () => call('nearby.stop')),
              ],
            ),
          ),
          'connected' => SliverToBoxAdapter(
            child: GroupedSection(
              children: [
                GroupedRow(
                  title: 'Synced to ${s['host'] ?? 'host'}',
                  subtitle: song == null ? null : '${song['title']} · ${song['artist']}',
                  leading: song == null ? null : Artwork(url: song['thumbnailUrl'] as String?, size: 44, radius: 8),
                  icon: song == null ? CupertinoIcons.link : null,
                  iconColor: HydeColors.accent,
                ),
                GroupedRow(title: 'Leave Session', destructive: true, chevron: false, onTap: () => call('nearby.stop')),
              ],
            ),
          ),
          'discovering' => SliverToBoxAdapter(
            child: GroupedSection(
              header: 'Nearby devices',
              children: [
                if (devices.isEmpty)
                  const GroupedRow(title: 'Looking for devices…', leading: CupertinoActivityIndicator()),
                for (final d in devices)
                  GroupedRow(
                    title: d,
                    icon: CupertinoIcons.device_phone_portrait,
                    onTap: () => call('nearby.connect', {'name': d}),
                  ),
                GroupedRow(title: 'Cancel', chevron: false, onTap: () => call('nearby.stopDiscovery')),
              ],
            ),
          ),
          _ => SliverToBoxAdapter(
            child: GroupedSection(
              children: [
                GroupedRow(
                  title: 'Start Nearby Sync',
                  subtitle: 'Others on your Wi-Fi can join',
                  icon: CupertinoIcons.dot_radiowaves_left_right,
                  iconColor: HydeColors.accent,
                  onTap: () => call('nearby.host'),
                ),
                GroupedRow(
                  title: 'Join Nearby Sync',
                  subtitle: 'Find a phone that is hosting',
                  icon: CupertinoIcons.search,
                  iconColor: HydeColors.blue,
                  onTap: () => call('nearby.discover'),
                ),
              ],
            ),
          ),
        },
      ],
    );
  }
}
