import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/engine/mock_engine.dart';
import 'package:hyde_music/features/more/account_screens.dart';
import 'package:hyde_music/features/more/history_screen.dart';
import 'package:hyde_music/features/more/local_media_screen.dart';
import 'package:hyde_music/features/more/misc_screens.dart';
import 'package:hyde_music/features/more/social_screens.dart';
import 'package:hyde_music/features/more/stats_screen.dart';
import 'package:hyde_music/features/settings/settings_catalog.dart';
import 'package:hyde_music/state/providers.dart';

void main() {
  test('no settings action can open the previous native UI', () {
    const allowed = {'flutter', 'feature', 'dialog', 'system', 'import'};
    for (final t in settingActionTargets.values) {
      expect(allowed.contains(t.split(':').first), isTrue, reason: t);
    }
  });

  final screens = <String, Widget>{
    'History': const HistoryScreen(),
    'Stats': const StatsScreen(),
    'Wrapped': const WrappedScreen(),
    'Local media': const LocalMediaScreen(),
    'Account': const AccountScreen(),
    'Hyde Sync': const HydeSyncScreen(),
    'Listen Together': const ListenTogetherScreen(),
    'Nearby Sync': const NearbySyncScreen(),
    'Spotify import': const SpotifyImportScreen(),
    'About': const AboutScreen(),
    'Support': const SupportScreen(),
    'Logs': const LogsScreen(),
  };

  for (final e in screens.entries) {
    testWidgets('${e.key} renders without errors', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      final engine = MockEngine(artwork: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [engineProvider.overrideWithValue(engine)],
          child: CupertinoApp(home: e.value),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
      engine.dispose();
    });
  }
}
