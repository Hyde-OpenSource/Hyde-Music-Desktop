import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/hyde_theme.dart';
import '../../design/glass/glass_controls.dart';
import '../../design/glass/glass_sheets.dart';
import '../../design/glass/glass_switch.dart';
import '../../design/glass/glass_toast.dart';
import '../../design/widgets/artwork.dart';
import '../../design/widgets/grouped_list.dart';
import '../../design/widgets/large_title_scaffold.dart';
import '../../state/providers.dart';

/// Sign-in web page inside the app. [mode] is "account" (Google →
/// YouTube Music) or "discord". Pops with `true` on success.
///
/// Account: after Google redirects back to music.youtube.com the session
/// cookies, visitor id and data-sync id are handed to the engine.
/// Discord: the token is read from the web app's localStorage after login.
class WebLoginScreen extends ConsumerStatefulWidget {
  const WebLoginScreen({super.key, required this.mode});
  final String mode;

  @override
  ConsumerState<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends ConsumerState<WebLoginScreen> {
  late final WebViewController _web;
  bool _finishing = false;
  bool _loading = true;

  static const _discordTokenJs =
      "(function(){try{var i=document.createElement('iframe');document.body.appendChild(i);"
      "var t=i.contentWindow.localStorage.token;return t?t.slice(1,-1):'';}catch(e){return '';}})()";

  bool get _discord => widget.mode == 'discord';

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: _onPageFinished,
          onUrlChange: (change) {
            final url = change.url ?? '';
            if (_discord && (url.endsWith('/app') || url.contains('/channels/'))) _captureDiscord();
          },
        ),
      );
    _start();
  }

  Future<void> _start() async {
    final engine = ref.read(engineProvider);
    if (!_discord) {
      // A fresh session so "switch account" really shows the account chooser.
      try {
        await engine.feature('account.prepareLogin');
      } catch (_) {}
    }
    await _web.loadRequest(
      Uri.parse(
        _discord
            ? 'https://discord.com/login'
            : 'https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com',
      ),
    );
  }

  static String _unquote(Object? value) {
    var s = '${value ?? ''}';
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) s = s.substring(1, s.length - 1);
    return s == 'null' || s == 'undefined' ? '' : s;
  }

  Future<void> _onPageFinished(String url) async {
    if (mounted) setState(() => _loading = false);
    if (_discord) {
      if (url.endsWith('/app') || url.contains('/channels/')) await _captureDiscord();
      return;
    }
    if (_finishing || !url.startsWith('https://music.youtube.com')) return;
    final engine = ref.read(engineProvider);
    try {
      final cookie = await engine.feature('account.webCookies', {'url': 'https://music.youtube.com'}) as String? ?? '';
      if (!cookie.contains('SAPISID')) return; // not signed in yet
      final visitor = _unquote(await _web.runJavaScriptReturningResult('window.yt && window.yt.config_ ? window.yt.config_.VISITOR_DATA : ""'));
      final sync = _unquote(await _web.runJavaScriptReturningResult('window.yt && window.yt.config_ ? window.yt.config_.DATASYNC_ID : ""'));
      await _finish(() => engine.feature('account.completeLogin', {'cookie': cookie, 'visitorData': visitor, 'dataSyncId': sync}));
    } catch (_) {
      // The page isn't ready yet; the next onPageFinished tries again.
    }
  }

  Future<void> _captureDiscord() async {
    if (_finishing) return;
    try {
      final token = _unquote(await _web.runJavaScriptReturningResult(_discordTokenJs));
      if (token.isEmpty) return;
      await _finish(() => ref.read(engineProvider).feature('discord.setToken', {'token': token}));
    } catch (_) {}
  }

  Future<void> _finish(Future<Object?> Function() complete) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await complete();
      ref.invalidate(settingsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);
      showGlassToast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Stack(
          children: [
            Positioned.fill(
              top: top + 60,
              child: _finishing ? const Center(child: CupertinoActivityIndicator(radius: 14, color: Color(0xFFFFFFFF))) : WebViewWidget(controller: _web),
            ),
            Positioned(
              top: top + 8,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  GlassIconButton(
                    icon: CupertinoIcons.xmark,
                    size: 44,
                    color: HydeColors.accent,
                    onPressed: () => Navigator.of(context).pop(false),
                    semanticLabel: 'Close',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _discord ? 'Sign in to Discord' : 'Sign in',
                      style: HydeText.title3.copyWith(color: const Color(0xFFFFFFFF)),
                    ),
                  ),
                  if (_loading || _finishing) const CupertinoActivityIndicator(color: Color(0xFFFFFFFF)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _accountStateProvider = FutureProvider.autoDispose<Map<String, Object?>>((ref) async {
  ref.watch(settingsProvider);
  return ((await ref.watch(engineProvider).feature('account.state')) as Map?)?.cast<String, Object?>() ?? const {};
});

/// Settings ▸ Account: signed-in profile, account switcher, sync options.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_accountStateProvider).value ?? const {};
    final signedIn = state['signedIn'] == true;
    final accounts = ((state['accounts'] as List?) ?? const []).cast<Map>();
    final values = ref.watch(settingsProvider).value ?? const {};
    final settings = ref.read(settingsProvider.notifier);
    final engine = ref.read(engineProvider);

    Future<void> signIn() async {
      await engine.feature('account.prepareLogin');
      if (!context.mounted) return;
      // No embeddable browser on Windows / Linux: sign in with the cookie
      // of a music.youtube.com session from your own browser.
      if (Platform.isLinux || Platform.isWindows) {
        if (await showCookieLogin(context, ref) == true) ref.invalidate(_accountStateProvider);
        return;
      }
      final ok = await Navigator.of(context)
          .push<bool>(CupertinoPageRoute(builder: (_) => const WebLoginScreen(mode: 'account')));
      if (ok == true) ref.invalidate(_accountStateProvider);
    }

    return LargeTitleScaffold(
      title: 'Account',
      slivers: [
        SliverToBoxAdapter(
          child: GroupedSection(
            children: [
              if (signedIn)
                GroupedRow(
                  title: state['name'] as String? ?? 'Signed in',
                  subtitle: state['email'] as String?,
                  leading: Artwork(
                    url: state['thumbnailUrl'] as String?,
                    size: 44,
                    circle: true,
                    placeholderIcon: CupertinoIcons.person_fill,
                  ),
                )
              else
                GroupedRow(
                  title: 'Sign in',
                  subtitle: 'Sync likes, playlists and get personal picks',
                  icon: CupertinoIcons.person_crop_circle_badge_plus,
                  iconColor: HydeColors.accent,
                  onTap: signIn,
                ),
            ],
          ),
        ),
        if (accounts.length > 1)
          SliverToBoxAdapter(
            child: GroupedSection(
              header: 'Accounts',
              children: [
                for (final a in accounts)
                  GroupedRow(
                    title: a['name'] as String? ?? '',
                    subtitle: a['email'] as String?,
                    leading: Artwork(
                      url: a['thumbnailUrl'] as String?,
                      size: 36,
                      circle: true,
                      placeholderIcon: CupertinoIcons.person_fill,
                    ),
                    trailing: a['active'] == true
                        ? const Icon(CupertinoIcons.checkmark_alt, color: HydeColors.accent)
                        : null,
                    chevron: false,
                    onTap: a['active'] == true
                        ? null
                        : () => guarded(context, () async {
                            await engine.feature('account.switch', {'id': a['id']});
                            ref.invalidate(settingsProvider);
                          }),
                  ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: GroupedSection(
            children: [
              GroupedRow(
                title: 'Sync your library',
                subtitle: 'Likes, library and playlists',
                trailing: GlassSwitch(
                  value: values['ytmSync'] as bool? ?? true,
                  onChanged: (v) => settings.set('ytmSync', v),
                ),
              ),
              GroupedRow(
                title: 'Personal recommendations',
                subtitle: 'Use your account for Home',
                trailing: GlassSwitch(
                  value: values['useLoginForBrowse'] as bool? ?? false,
                  onChanged: (v) => settings.set('useLoginForBrowse', v),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: GroupedSection(
            children: [
              if (signedIn) GroupedRow(title: 'Add another account', chevron: false, onTap: signIn),
              if (signedIn)
                GroupedRow(
                  title: 'Sign Out',
                  destructive: true,
                  chevron: false,
                  onTap: () async {
                    final ok = await showGlassDialog<bool>(
                      context: context,
                      builder: (context) => GlassAlertDialog(
                        title: const Text('Sign out?'),
                        content: const Text('Your downloads and local playlists stay on this phone.'),
                        actions: [
                          GlassDialogAction(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          GlassDialogAction(
                            isDestructiveAction: true,
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) {
                      await guarded(context, () => engine.feature('account.logout'));
                      ref.invalidate(settingsProvider);
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Last.fm username/password sign-in (same API call as before).
Future<void> showLastFmLogin(BuildContext context, WidgetRef ref) async {
  final user = TextEditingController();
  final pass = TextEditingController();
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (context) => GlassAlertDialog(
      title: const Text('Sign in to Last.fm'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          CupertinoTextField(controller: user, placeholder: 'Username', autofocus: true),
          const SizedBox(height: 8),
          CupertinoTextField(controller: pass, placeholder: 'Password', obscureText: true),
        ],
      ),
      actions: [
        GlassDialogAction(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        GlassDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sign In'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await guarded(context, () async {
      final name = await ref.read(engineProvider).feature('lastfm.login', {
        'username': user.text.trim(),
        'password': pass.text,
      });
      ref.invalidate(settingsProvider);
      if (context.mounted) showGlassToast(context, 'Signed in as $name', icon: CupertinoIcons.checkmark_circle);
    });
  }
  user.dispose();
  pass.dispose();
}

/// Hyde Sync (cloud backup) sign-in / status.
class HydeSyncScreen extends ConsumerStatefulWidget {
  const HydeSyncScreen({super.key});

  @override
  ConsumerState<HydeSyncScreen> createState() => _HydeSyncScreenState();
}

class _HydeSyncScreenState extends ConsumerState<HydeSyncScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(featureStateProvider('hydesync')).value ?? const {};
    final signedIn = s['signedIn'] == true;
    final busy = s['state'] == 'loading' || s['state'] == 'syncing';
    final message = s['message'] as String?;
    final engine = ref.read(engineProvider);
    final secondary = HydeColors.secondaryLabel.resolveFrom(context);

    return LargeTitleScaffold(
      title: 'Hyde Sync',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HydeMetrics.gutter + 4, 0, HydeMetrics.gutter + 4, 18),
            child: Text(
              'Back up your library and playlists to the cloud and keep them in sync across your devices.',
              style: HydeText.subhead.copyWith(color: secondary),
            ),
          ),
        ),
        if (signedIn)
          SliverToBoxAdapter(
            child: GroupedSection(
              children: [
                GroupedRow(
                  title: 'Signed in',
                  subtitle: s['email'] as String?,
                  icon: CupertinoIcons.checkmark_seal_fill,
                  iconColor: CupertinoColors.systemGreen,
                ),
                GroupedRow(
                  title: busy ? 'Syncing…' : 'Sync Now',
                  subtitle: message,
                  chevron: false,
                  onTap: busy ? null : () => guarded(context, () => engine.feature('hydesync.sync')),
                ),
                GroupedRow(
                  title: 'Sign Out',
                  destructive: true,
                  chevron: false,
                  onTap: () => guarded(context, () => engine.feature('hydesync.signOut')),
                ),
              ],
            ),
          )
        else
          SliverToBoxAdapter(
            child: GroupedSection(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CupertinoTextField(
                        controller: _email,
                        placeholder: 'Email',
                        keyboardType: TextInputType.emailAddress,
                        padding: const EdgeInsets.all(12),
                      ),
                      const SizedBox(height: 10),
                      CupertinoTextField(
                        controller: _password,
                        placeholder: 'Password',
                        obscureText: true,
                        padding: const EdgeInsets.all(12),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: CupertinoButton.filled(
                              onPressed: busy
                                  ? null
                                  : () => guarded(
                                      context,
                                      () => engine.feature('hydesync.signIn', {
                                        'email': _email.text.trim(),
                                        'password': _password.text,
                                      }),
                                    ),
                              child: const Text('Sign In'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: CupertinoButton(
                              onPressed: busy
                                  ? null
                                  : () => guarded(
                                      context,
                                      () => engine.feature('hydesync.signUp', {
                                        'email': _email.text.trim(),
                                        'password': _password.text,
                                      }),
                                    ),
                              child: const Text('Create Account'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (busy || message != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  if (busy) const Padding(padding: EdgeInsets.only(right: 10), child: CupertinoActivityIndicator()),
                  Expanded(
                    child: Text(
                      message ?? 'Working…',
                      style: HydeText.footnote.copyWith(
                        color: s['state'] == 'error' ? CupertinoColors.systemRed.resolveFrom(context) : secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Desktop sign-in: paste the `Cookie` header of a signed-in
/// music.youtube.com tab. The engine checks it and loads the account.
Future<bool?> showCookieLogin(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  var busy = false;
  String? error;
  return showGlassDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => GlassAlertDialog(
        title: const Text('Sign in with YouTube Music'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              '1. Open music.youtube.com in your browser and sign in.\n'
              '2. Press F12 › Network, reload, and click any request to music.youtube.com.\n'
              '3. Copy the value of the “cookie” request header and paste it below.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: controller,
              placeholder: 'SAPISID=…; __Secure-3PSID=…',
              maxLines: 4,
              minLines: 3,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(fontSize: 13, color: Color(0xFFFF453A))),
              ),
            const SizedBox(height: 6),
            const Text(
              'The cookie stays on this computer. Sign out any time from Settings › Account.',
              style: TextStyle(fontSize: 12, color: Color(0x99FFFFFF)),
            ),
          ],
        ),
        actions: [
          GlassDialogAction(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          GlassDialogAction(
            isDefaultAction: true,
            onPressed: busy
                ? () {}
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await ref.read(engineProvider).feature('account.completeLogin', {'cookie': controller.text});
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (e) {
                      setState(() {
                        busy = false;
                        error = 'That cookie didn’t work. Copy the whole cookie header from a signed-in tab.';
                      });
                    }
                  },
            child: busy ? const CupertinoActivityIndicator() : const Text('Sign in'),
          ),
        ],
      ),
    ),
  );
}
