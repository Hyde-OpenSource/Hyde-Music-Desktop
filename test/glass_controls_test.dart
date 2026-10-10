import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyde_music/design/glass/glass_sheets.dart';
import 'package:hyde_music/design/glass/glass_switch.dart';
import 'package:hyde_music/engine/mock_engine.dart';
import 'package:hyde_music/features/settings/settings_catalog.dart';
import 'package:hyde_music/features/settings/settings_screen.dart';
import 'package:hyde_music/state/providers.dart';

void main() {
  testWidgets('GlassSwitch toggles on tap and on drag', (tester) async {
    var value = false;
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: StatefulBuilder(
            builder: (context, setState) => GlassSwitch(value: value, onChanged: (v) => setState(() => value = v)),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(GlassSwitch));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(value, isTrue);

    // Drag the knob back to the left.
    await tester.drag(find.byType(GlassSwitch), const Offset(-60, 0));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(value, isFalse);
  });

  testWidgets('GlassSlider snaps to divisions', (tester) async {
    var value = 0.0;
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: StatefulBuilder(
              builder: (context, setState) =>
                  GlassSlider(value: value, divisions: 4, onChanged: (v) => setState(() => value = v)),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(GlassSlider));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(value, 0.5);
  });

  testWidgets('settings choice opens a glass action sheet and saves the value', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 3000));
    final engine = MockEngine(artwork: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: const CupertinoApp(home: SettingsPageScreen(page: playbackPage)),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    await tester.tap(find.text('Streaming quality'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(find.byType(GlassActionSheet), findsOneWidget);
    await tester.tap(find.text('Best available'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect((await engine.readSettings())['audioQuality'], 'BEST_AVAILABLE');
    engine.dispose();
  });
}
