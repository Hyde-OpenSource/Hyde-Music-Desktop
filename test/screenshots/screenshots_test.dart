// Renders the main screens on demo data to PNGs for a visual check:
//   flutter test test/screenshots --update-goldens
// Images land in test/screenshots/out/ (not committed).
@Tags(['screenshots'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyde_music/app.dart';
import 'package:hyde_music/engine/mock_engine.dart';
import 'package:hyde_music/features/library/collection_screens.dart';
import 'package:hyde_music/state/providers.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = File(path).readAsBytesSync();
    await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }

  await load('Inter', 'assets/fonts/Inter.ttf');
  final config = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map;
  final icons = (config['packages'] as List).cast<Map>().firstWhere((p) => p['name'] == 'cupertino_icons');
  final root = Uri.parse(icons['rootUri'] as String).toFilePath();
  await load('packages/cupertino_icons/CupertinoIcons', '$root/assets/CupertinoIcons.ttf');
}

void main() {
  setUpAll(_loadFonts);

  Future<MockEngine> pumpApp(WidgetTester tester) async {
    // A 1440 × 900 desktop window.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    final engine = MockEngine(artwork: false);
    await tester.pumpWidget(ProviderScope(overrides: [engineProvider.overrideWithValue(engine)], child: const HydeApp()));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    return engine;
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(HydeApp), matchesGoldenFile('out/$name.png'));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('home, library, pages, search, player', (tester) async {
    final engine = await pumpApp(tester);
    await shot(tester, '01_home');

    await tester.tap(find.text('Library').first);
    await settle(tester);
    await shot(tester, '03_library');

    await tester.tap(find.text('Playlists').last);
    await settle(tester);
    await shot(tester, '04_playlists');

    await tester.tap(find.text('Late Night Drive').first);
    await settle(tester);
    await shot(tester, '05_playlist_page');

    final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
    nav.push(CupertinoPageRoute<void>(builder: (_) => const AlbumScreen(id: 'album0')));
    await settle(tester);
    await shot(tester, '06_album_page');

    nav.push(CupertinoPageRoute<void>(builder: (_) => const ArtistScreen(id: 'artist0')));
    await settle(tester);
    await shot(tester, '07_artist_page');

    await tester.tap(find.text('Search').at(1)); // [0] is the sidebar field's placeholder
    await settle(tester);
    await shot(tester, '08_search');

    await tester.enterText(find.byType(CupertinoTextField).last, 'glass');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    await shot(tester, '09_search_results');

    engine.playPause();
    await settle(tester);
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await settle(tester);
    await shot(tester, '10_now_playing');
    // Stop the demo engine's ticker before the test ends.
    await engine.playPause();
    await tester.pumpWidget(const SizedBox());
    engine.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
