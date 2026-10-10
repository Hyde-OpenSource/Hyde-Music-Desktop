import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/app.dart';
import 'package:hyde_music/engine/mock_engine.dart';
import 'package:hyde_music/features/player/desktop_now_playing.dart';
import 'package:hyde_music/features/player/player_bar.dart';
import 'package:hyde_music/features/settings/settings_catalog.dart';
import 'package:hyde_music/features/settings/settings_screen.dart';
import 'package:hyde_music/state/providers.dart';

Widget _app(MockEngine engine) =>
    ProviderScope(overrides: [engineProvider.overrideWithValue(engine)], child: const HydeApp());

void main() {
  late MockEngine engine;
  setUp(() => engine = MockEngine(artwork: false));
  tearDown(() => engine.dispose());

  testWidgets('desktop shell shows sidebar, player bar and home sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(_app(engine));
    await tester.pump(const Duration(milliseconds: 500));

    for (final item in ['Home', 'Search', 'Library', 'Recognise', 'History', 'Settings']) {
      expect(find.text(item), findsWidgets);
    }
    expect(find.text('Quick picks'), findsOneWidget);
    // The player bar shows the current track.
    expect(find.descendant(of: find.byType(PlayerBar), matching: find.text(engine.currentPlayback.track!.title)), findsOneWidget);
  });

  testWidgets('sidebar switches to Library', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(_app(engine));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Library').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('Recently Added'), findsOneWidget);
  });

  testWidgets('player bar plays, pauses and opens lyrics', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(_app(engine));
    await tester.pump(const Duration(milliseconds: 300));

    expect(engine.currentPlayback.isPlaying, isFalse);
    await tester.tap(find.descendant(of: find.byType(PlayerBar), matching: find.byIcon(CupertinoIcons.play_fill)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(engine.currentPlayback.isPlaying, isTrue);

    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopNowPlaying), findsOneWidget);

    await engine.playPause();
    await tester.pump(const Duration(milliseconds: 300));
    engine.dispose(); // stop the mock's playback ticker before the binding checks timers
  });

  testWidgets('settings root lists every group page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: const CupertinoApp(home: SettingsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    for (final group in settingsGroups) {
      // Pages whose every row is a mobile-only feature are hidden on desktop.
      for (final page in group.where(isPageAvailable)) {
        expect(find.text(page.title), findsOneWidget, reason: page.title);
      }
    }
  });

  test('settings catalog covers every user-facing native preference key', () {
    // Keys that are internal state, not settings rows (owned by screens /
    // engine). Documented in docs/07_SETTINGS_MAP.md.
    const internal = {
      'selectedThemeColor',
      'custom_density_scale_value',
      'audioQualityPromptShown',
      'supabaseLoggedIn',
      'supabasePromptShown',
      'lastSupabasePromptTime',
      'shuffleMode',
      'chipSortType',
      'songSortType',
      'songSortDescending',
      'playlistSongSortType',
      'playlistSongSortDescending',
      'autoPlaylistSongSortType',
      'autoPlaylistSongSortDescending',
      'artistSortType',
      'artistSortDescending',
      'albumSortType',
      'albumSortDescending',
      'playlistSortType',
      'playlistSortDescending',
      'artistSongSortType',
      'artistSongSortDescending',
      'mixSortType',
      'songFilter',
      'artistFilter',
      'albumFilter',
      'last_like_song_sync',
      'last_library_song_sync',
      'last_album_sync',
      'last_artist_sync',
      'last_playlist_sync',
      'artistViewType',
      'albumViewType',
      'playlistViewType',
      'playlistEditLock',
      'queueEditLock',
      'wrapped_seen',
      'lastSeenVersion',
      'lastLocalScan',
      'listenTogetherBlockedUsers',
      'listenTogetherSessionToken',
      'listenTogetherRoomCode',
      'listenTogetherUserId',
      'listenTogetherIsHost',
      'listenTogetherSessionTimestamp',
      'showLyrics',
      'discordToken',
      'discordInfoDismissed',
      'discordUsername',
      'discordName',
      'discordAvatar',
      'lastfmSession',
      'lastfmUsername',
      'podcastFilter',
      'playerVolume',
      'repeatMode',
      'searchSource',
      'visitorData',
      'dataSyncId',
      'innerTubeCookie',
      'accountName',
      'accountEmail',
      'accountChannelHandle',
      'activeAccountId',
      'lastImportantNoticeVersion',
      'supabaseUserId',
      'supabaseEmail',
    };

    final source = File('../app/src/main/kotlin/iad1tya/echo/music/constants/PreferenceKeys.kt');
    if (!source.existsSync()) return; // Only runs inside the Echo-Music repo.
    final native = RegExp(r'PreferencesKey\("([^"]+)"\)')
        .allMatches(source.readAsStringSync())
        .map((m) => m[1]!)
        .toSet();

    final declared = <String>{};
    for (final (_, item) in allSettings()) {
      switch (item) {
        case ToggleSetting(:final key) ||
            ChoiceSetting(:final key) ||
            SliderSetting(:final key) ||
            TextSetting(:final key):
          declared.add(key);
        default:
      }
    }

    final missing = native.difference(declared).difference(internal);
    expect(missing, isEmpty, reason: 'Native settings without a row in the Flutter catalog: $missing');
  });

  test('every settings action button has a destination', () {
    final missing = [
      for (final (_, item) in allSettings())
        if (item is ActionSetting && !settingActionTargets.containsKey(item.action)) item.action,
    ];
    expect(missing, isEmpty, reason: 'ActionSettings with no target: $missing');
  });
}
