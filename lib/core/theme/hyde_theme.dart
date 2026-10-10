import 'package:flutter/cupertino.dart';

/// Colour tokens. Dark-first (matches the reference screenshots); light
/// values follow iOS system colours.
abstract final class HydeColors {
  /// Brand accent — the red used for back chevrons, active tab, links.
  static const accent = Color(0xFFFA2D48);

  static const background = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF2F2F7),
    darkColor: Color(0xFF000000),
  );

  /// Inset-grouped card fill (Settings groups, search field).
  static const groupedFill = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF1C1C1E),
  );

  static const label = CupertinoDynamicColor.withBrightness(color: Color(0xFF000000), darkColor: Color(0xFFFFFFFF));

  static const secondaryLabel = CupertinoDynamicColor.withBrightness(
    color: Color(0x993C3C43),
    darkColor: Color(0x99EBEBF5),
  );

  static const tertiaryLabel = CupertinoDynamicColor.withBrightness(
    color: Color(0x4D3C3C43),
    darkColor: Color(0x4DEBEBF5),
  );

  static const separator = CupertinoDynamicColor.withBrightness(color: Color(0x4A3C3C43), darkColor: Color(0xFF38383A));

  // Settings row icon tints (screenshot palette).
  static const teal = Color(0xFF5AC8C8);
  static const purple = Color(0xFFBF5AF2);
  static const blue = Color(0xFF4FA3F7);
  static const yellow = Color(0xFFF5C451);
  static const cyan = Color(0xFF4CC9E0);
  static const indigo = Color(0xFF7D7AFF);
  static const green = Color(0xFF7ACB6E);
  static const orange = Color(0xFFF5B342);
  static const slate = Color(0xFFA1A7B3);
  static const violet = Color(0xFF8E8CF0);
  static const mint = Color(0xFF52C7A8);
  static const tan = Color(0xFFB7A08C);
  static const pink = Color(0xFFF26D92);
}

/// Type scale (iOS metrics, Inter in place of SF Pro, which may not be
/// shipped on Android).
abstract final class HydeText {
  static const family = 'Inter';

  static const largeTitle = TextStyle(
    fontFamily: family,
    fontSize: 34,
    height: 1.12,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
  );
  static const title1 = TextStyle(fontFamily: family, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4);
  static const title2 = TextStyle(fontFamily: family, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3);
  static const title3 = TextStyle(fontFamily: family, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.2);
  static const headline = TextStyle(fontFamily: family, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2);
  static const body = TextStyle(fontFamily: family, fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.2);
  static const callout = TextStyle(fontFamily: family, fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: -0.15);
  static const subhead = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.1);
  static const footnote = TextStyle(fontFamily: family, fontSize: 13, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w500);
  static const tabLabel = TextStyle(fontFamily: family, fontSize: 10.5, fontWeight: FontWeight.w600);
}

/// Spacing / radius tokens.
abstract final class HydeMetrics {
  static const gutter = 16.0;
  static const groupRadius = 26.0;
  static const artworkRadius = 10.0;
  static const rowHeight = 52.0;
  static const tabBarHeight = 60.0;
  static const miniPlayerHeight = 56.0;
  static const glassBottomInset = 10.0;
}

CupertinoThemeData buildHydeTheme(Brightness brightness) {
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: HydeColors.accent,
    scaffoldBackgroundColor: HydeColors.background,
    barBackgroundColor: const Color(0x00000000),
    textTheme: CupertinoTextThemeData(
      primaryColor: HydeColors.accent,
      textStyle: HydeText.body.copyWith(color: HydeColors.label),
      navTitleTextStyle: HydeText.headline.copyWith(color: HydeColors.label),
      navLargeTitleTextStyle: HydeText.largeTitle.copyWith(color: HydeColors.label),
      actionTextStyle: HydeText.body.copyWith(color: HydeColors.accent),
      tabLabelTextStyle: HydeText.tabLabel,
    ),
  );
}
