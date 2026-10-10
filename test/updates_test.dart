import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/engine/mock_engine.dart';
import 'package:hyde_music/features/settings/updates_screen.dart';
import 'package:hyde_music/state/providers.dart';

void main() {
  testWidgets('software update: check → download with progress → install', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    final engine = MockEngine(artwork: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [engineProvider.overrideWithValue(engine)],
        child: const CupertinoApp(home: UpdatesScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700)); // simulated check
    await tester.pump();
    expect(find.text('Hyde Music 5.1'), findsOneWidget);
    expect(find.text('Download and Install'), findsOneWidget);

    await tester.tap(find.text('Download and Install'));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Downloading…'), findsOneWidget);
    expect(find.text('Cancel Download'), findsOneWidget);

    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Install Now'), findsOneWidget);
    expect(find.text('Downloaded and verified'), findsOneWidget);
    engine.dispose();
  });
}
