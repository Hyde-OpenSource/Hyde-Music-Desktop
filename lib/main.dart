import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/theme/hyde_theme.dart';
import 'design/glass/glass_shader.dart';
import 'engine/dart/dart_engine.dart';
import 'engine/hyde_engine.dart';
import 'engine/mock_engine.dart';
import 'engine/models.dart';
import 'state/providers.dart';

/// `--dart-define=HYDE_ENGINE=mock` runs the UI on demo data (no network,
/// no audio) — useful for UI work on desktop.
const _engineMode = String.fromEnvironment('HYDE_ENGINE', defaultValue: 'dart');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GlassShader.preload();

  // Edge-to-edge; glass chrome floats over content.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      systemNavigationBarColor: Color(0x00000000),
      systemNavigationBarContrastEnforced: false,
    ),
  );

  final desktop = !kIsWeb && (Platform.isLinux || Platform.isWindows);
  if (desktop) {
    // Desktop backends: libmpv (media_kit) plays audio, FFI SQLite stores the library.
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true, libmpv: _bundledLibmpv());
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final useDart = _engineMode == 'dart' && !kIsWeb && (Platform.isAndroid || Platform.isIOS || desktop);
  HydeEngine engine;
  try {
    engine = useDart ? await DartEngine.create() : MockEngine();
  } catch (e, st) {
    // The library database or audio service couldn't start. Show why instead
    // of a blank screen.
    runApp(_StartupError(error: e, stack: st));
    return;
  }

  var initialTab = 0;
  try {
    final settings = await engine.readSettings();
    final showFind = settings['show_find_in_navbar'] as bool? ?? true;
    initialTab = switch (settings['defaultOpenTab']) {
      'LIBRARY' => 1,
      'FIND' => showFind ? 2 : 0,
      'SEARCH' => 3,
      _ => 0,
    };
  } catch (_) {}

  _devAutoplay(engine);

  runApp(
    ProviderScope(
      overrides: [engineProvider.overrideWithValue(engine), initialTabProvider.overrideWithValue(initialTab)],
      child: const HydeApp(),
    ),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.stack});
  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      theme: buildHydeTheme(Brightness.dark),
      home: CupertinoPageScaffold(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Text('Hyde Music couldn’t start', style: HydeText.title2.copyWith(color: const Color(0xFFFFFFFF))),
                const SizedBox(height: 12),
                Text('$error', style: HydeText.body.copyWith(color: const Color(0xCCFFFFFF))),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text('$stack', style: HydeText.footnote.copyWith(color: const Color(0x80FFFFFF))),
                  ),
                ),
                CupertinoButton.filled(
                  onPressed: () => Clipboard.setData(ClipboardData(text: '$error\n$stack')),
                  child: const Text('Copy details'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Developer check: `HYDE_AUTOPLAY="song name" hyde-music` searches, plays
/// the first song and logs playback state to stdout. Does nothing otherwise.
void _devAutoplay(HydeEngine engine) {
  final query = Platform.environment['HYDE_AUTOPLAY'];
  if (query == null || query.isEmpty) return;
  () async {
    try {
      final results = await engine.search(query);
      final tracks = [for (final r in results) if (r is TrackItem) r.track];
      // ignore: avoid_print
      print('[autoplay] ${tracks.length} songs for "$query"; playing ${tracks.firstOrNull?.title}');
      if (tracks.isEmpty) return;
      await engine.setVolume(0.2);
      await engine.playTracks(tracks.take(5).toList());
      engine.playback.listen((s) {
        // ignore: avoid_print
        print('[autoplay] playing=${s.isPlaying} buffering=${s.isBuffering} '
            'pos=${s.position.inSeconds}s/${s.duration.inSeconds}s error=${s.error} format=${s.format?.label}');
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('[autoplay] failed: $e\n$st');
    }
  }();
}

/// libmpv shipped with the app (AppImage / portable folder), if any; null
/// falls back to the system library (Linux) or the DLL next to the .exe
/// (Windows, bundled by media_kit_libs_windows_audio).
String? _bundledLibmpv() {
  if (!Platform.isLinux) return null;
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  for (final dir in [
    if (Platform.environment['APPDIR'] case final appDir?) '$appDir/usr/lib',
    '$exeDir/lib',
    '$exeDir/../lib',
  ]) {
    for (final name in ['libmpv.so.2', 'libmpv.so.1']) {
      final f = File('$dir/$name');
      if (f.existsSync()) return f.path;
    }
  }
  return null;
}
