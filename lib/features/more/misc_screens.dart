import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_sheets.dart';
import '../../design/glass/glass_toast.dart';
import '../../design/widgets/grouped_list.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../state/providers.dart';

Future<void> openUrl(BuildContext context, WidgetRef ref, String url) =>
    guarded(context, () => ref.read(engineProvider).feature('url.open', {'url': url}));

/// Import a Spotify playlist by link: fetch → review count → save as a playlist.
class SpotifyImportScreen extends ConsumerStatefulWidget {
  const SpotifyImportScreen({super.key});

  @override
  ConsumerState<SpotifyImportScreen> createState() => _SpotifyImportScreenState();
}

class _SpotifyImportScreenState extends ConsumerState<SpotifyImportScreen> {
  final _url = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(featureStateProvider('spotify')).value ?? const {};
    final fetch = (s['fetch'] as Map?)?.cast<String, Object?>() ?? const {'state': 'idle'};
    final save = (s['save'] as Map?)?.cast<String, Object?>() ?? const {'state': 'idle'};
    final engine = ref.read(engineProvider);
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);

    return LargeTitleScaffold(
      title: 'Import from Spotify',
      slivers: [
        SliverToBoxAdapter(
          child: GroupedSection(
            footer: 'Paste a public Spotify playlist link. Matching songs are saved as a playlist in your library.',
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: CupertinoTextField(
                  controller: _url,
                  placeholder: 'https://open.spotify.com/playlist/…',
                  padding: const EdgeInsets.all(12),
                  suffix: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    onPressed: () async {
                      final d = await Clipboard.getData(Clipboard.kTextPlain);
                      if (d?.text != null) _url.text = d!.text!.trim();
                    },
                    child: const Icon(CupertinoIcons.doc_on_clipboard),
                  ),
                ),
              ),
              GroupedRow(
                title: 'Fetch Playlist',
                icon: CupertinoIcons.arrow_down_doc,
                iconColor: HydeColors.green,
                onTap: () => guarded(context, () => engine.feature('spotify.fetch', {'url': _url.text.trim()})),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            children: [
              switch (fetch['state']) {
                'loading' => const GroupedRow(title: 'Loading playlist…', leading: CupertinoActivityIndicator()),
                'progress' => GroupedRow(
                  title: 'Loading ${fetch['loaded']} of ${fetch['total']} songs…',
                  leading: const CupertinoActivityIndicator(),
                ),
                'ready' => GroupedRow(
                  title: fetch['name'] as String? ?? 'Playlist',
                  subtitle: '${fetch['count']} songs found',
                  icon: CupertinoIcons.music_note_list,
                  iconColor: HydeColors.accent,
                ),
                'error' => GroupedRow(
                  title: fetch['message'] as String? ?? 'Couldn’t load the playlist',
                  destructive: true,
                ),
                _ => GroupedRow(title: 'No playlist loaded', subtitle: 'Paste a link above', icon: CupertinoIcons.info),
              },
              if (fetch['state'] == 'ready' && save['state'] != 'saving')
                GroupedRow(
                  title: 'Save to Library',
                  chevron: false,
                  onTap: () => guarded(context, () => engine.feature('spotify.save', {'name': fetch['name']})),
                ),
              if (save['state'] == 'saving')
                GroupedRow(
                  title: 'Matching ${save['matched']}/${save['total']}…',
                  subtitle: save['current'] as String?,
                  leading: const CupertinoActivityIndicator(),
                ),
              if (save['state'] == 'done')
                GroupedRow(
                  title: 'Saved “${save['name']}”',
                  subtitle: '${save['matched']} matched · ${save['failed']} not found',
                  icon: CupertinoIcons.checkmark_circle_fill,
                  iconColor: CupertinoColors.systemGreen,
                ),
              if (save['state'] == 'error')
                GroupedRow(title: save['message'] as String? ?? 'Import failed', destructive: true),
            ],
          ),
        ),
        if (fetch['state'] != 'idle')
          SliverToBoxAdapter(
            child: Center(
              child: CupertinoButton(
                onPressed: () => engine.feature('spotify.reset'),
                child: Text('Start over', style: TextStyle(color: secondary)),
              ),
            ),
          ),
      ],
    );
  }
}

/// About Hyde Music.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(_versionProvider).value;
    return LargeTitleScaffold(
      title: 'About',
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              ClipRSuperellipse(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset('assets/hyde_logo.png', width: 96, height: 96),
              ),
              const SizedBox(height: 12),
              Text('Hyde Music', style: HydeText.title2.copyWith(color: HydeColors.label.resolveFrom(context))),
              if (status != null)
                Text(
                  'Version $status',
                  style: HydeText.subhead.copyWith(color: HydeColors.secondaryLabel.resolveFrom(context)),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            children: [
              GroupedRow(
                title: 'Contact',
                subtitle: 'thenntech@gmail.com',
                icon: CupertinoIcons.mail,
                iconColor: HydeColors.blue,
                onTap: () => openUrl(context, ref, 'mailto:thenntech@gmail.com'),
              ),
              GroupedRow(
                title: 'HydeOS Website',
                subtitle: 'All HydeOS products',
                icon: CupertinoIcons.globe,
                iconColor: HydeColors.teal,
                onTap: () => openUrl(context, ref, 'https://hydeos.tech/'),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            children: [
              GroupedRow(
                title: 'Support Development',
                icon: CupertinoIcons.heart_fill,
                iconColor: HydeColors.pink,
                onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const SupportScreen())),
              ),
              GroupedRow(
                title: 'Open-source licences',
                icon: CupertinoIcons.doc_text,
                iconColor: HydeColors.slate,
                onTap: () => showGlassDialog<void>(context: context, builder: (context) => const _Licences()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final _versionProvider = FutureProvider<String?>((ref) async {
  final s = await ref.watch(engineProvider).checkForUpdate(manual: false);
  return s.currentVersion.isEmpty ? null : s.currentVersion;
});

class _Licences extends StatelessWidget {
  const _Licences();

  @override
  Widget build(BuildContext context) => GlassAlertDialog(
    title: const Text('Open-source licences'),
    content: const Text(
      'Hyde Music builds on open-source software including Flutter, liquid_glass_easy, '
      'Media3/ExoPlayer, Room, Ktor, Coil, NewPipe Extractor, Kuromoji and more, each under its own licence.',
    ),
    actions: [GlassDialogAction(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
  );
}

/// Support Development: Buy Me a Coffee, Patreon, UPI, crypto addresses.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  static const _crypto = [
    ('Bitcoin', 'bc1qcvyr7eekha8uytmffcvgzf4h7xy7shqzke35fy'),
    ('Ethereum', '0x51bc91022E2dCef9974D5db2A0e22d57B360e700'),
    ('Solana', '9wjca3EQnEiqzqgy7N5iqS1JGXJiknMQv6zHgL96t94S'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LargeTitleScaffold(
      title: 'Support Development',
      slivers: [
        SliverToBoxAdapter(
          child: GroupedSection(
            header: 'One-time or monthly',
            children: [
              GroupedRow(
                title: 'Buy Me a Coffee',
                icon: CupertinoIcons.gift_fill,
                iconColor: HydeColors.yellow,
                onTap: () => openUrl(context, ref, 'https://www.buymeacoffee.com/iad1tya'),
              ),
              GroupedRow(
                title: 'Patreon',
                subtitle: 'Monthly support',
                icon: CupertinoIcons.heart_fill,
                iconColor: HydeColors.pink,
                onTap: () => openUrl(context, ref, 'https://patreon.com/iad1tya'),
              ),
              GroupedRow(
                title: 'UPI Payment',
                subtitle: 'Direct payment (India only)',
                icon: CupertinoIcons.money_dollar_circle_fill,
                iconColor: HydeColors.green,
                onTap: () => openUrl(
                  context,
                  ref,
                  'https://intradeus.github.io/http-protocol-redirector/?r=upi://pay?pa=iad1tya@upi&pn=Tirth&am=&tn=Thank%20You%20so%20much%20for%20this%20support',
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            header: 'Cryptocurrency',
            footer: 'Tap to copy the wallet address.',
            children: [
              for (final c in _crypto)
                GroupedRow(
                  title: c.$1,
                  subtitle: c.$2,
                  icon: CupertinoIcons.bitcoin_circle_fill,
                  iconColor: HydeColors.orange,
                  chevron: false,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: c.$2));
                    showGlassToast(context, '${c.$1} address copied', icon: CupertinoIcons.doc_on_doc);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Logs: Listen Together connection log (with copy / clear).
class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(featureStateProvider('listenTogether')).value ?? const {};
    final logs = ((s['logs'] as List?) ?? const []).cast<String>();
    final mono = HydeText.footnote.copyWith(
      fontFamily: 'monospace',
      color: HydeColors.secondaryLabel.resolveFrom(context),
    );
    return LargeTitleScaffold(
      title: 'Logs',
      actions: [
        CupertinoButton(
          onPressed: logs.isEmpty
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: logs.join('\n')));
                  showGlassToast(context, 'Logs copied', icon: CupertinoIcons.doc_on_doc);
                },
          child: const Text('Copy'),
        ),
        CupertinoButton(onPressed: () => ref.read(engineProvider).feature('lt.clearLogs'), child: const Text('Clear')),
      ],
      slivers: [
        if (logs.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Text('No logs yet', textAlign: TextAlign.center, style: mono),
            ),
          ),
        SliverList.builder(
          itemCount: logs.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: HydeMetrics.gutter + 4, vertical: 3),
            child: Text(logs[logs.length - 1 - i], style: mono),
          ),
        ),
      ],
    );
  }
}
