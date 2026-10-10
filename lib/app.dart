import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/hyde_theme.dart';
import 'design/glass/glass_shader.dart';
import 'features/shell/desktop_shell.dart';
import 'state/providers.dart';

class HydeApp extends ConsumerWidget {
  const HydeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // darkMode: ON / OFF / AUTO — same values as the native preference.
    final mode = ref.watch(settingsProvider.select((s) => s.value?['darkMode'] as String?)) ?? 'ON';
    GlassShader.enabled = ref.watch(settingsProvider.select((s) => s.value?['glassQuality'] as String?)) != 'FROSTED';
    final platform = MediaQuery.platformBrightnessOf(context);
    final brightness = switch (mode) {
      'OFF' => Brightness.light,
      'AUTO' => platform,
      _ => Brightness.dark,
    };

    return CupertinoApp(
      title: 'Hyde Music',
      debugShowCheckedModeBanner: false,
      theme: buildHydeTheme(brightness),
      // Mouse and trackpad drag horizontal shelves, like touch does.
      scrollBehavior: const CupertinoScrollBehavior().copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
      ),
      home: const DesktopShell(),
    );
  }
}
