import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'nano_tokens.dart';

/// Builds the Material [ThemeData] that carries the NanoLink design tokens.
///
/// The whole app is rendered with Material widgets, but the look is driven by
/// [NanoTokens] (iOS vs Material You palettes). Screens read tokens via
/// `context.nano`; this class only wires the base theme so stray Material
/// defaults (scaffold color, text color, splash) match the design.
class NanoTheme {
  /// Pick the platform visual style. iOS & macOS get the Apple look; every
  /// other platform (Android, Windows, Linux, web) gets Material You.
  static NanoStyle styleForPlatform([TargetPlatform? platform]) {
    final p = platform ?? defaultTargetPlatform;
    switch (p) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return NanoStyle.ios;
      default:
        return NanoStyle.md;
    }
  }

  static ThemeData build(NanoStyle style, Brightness brightness) {
    final t = NanoTokens.resolve(style, brightness);
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
    );

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.secondary,
      onSecondary: t.onAccent,
      tertiary: t.tertiary,
      onTertiary: t.onAccent,
      error: t.crit,
      onError: Colors.white,
      surface: t.card,
      onSurface: t.fg,
      surfaceContainerHighest: t.card2,
      outline: t.sep,
      outlineVariant: t.sep2,
    );

    final textTheme = base.textTheme
        .apply(
          bodyColor: t.fg,
          displayColor: t.fg,
          fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei'],
        )
        .copyWith();

    return base.copyWith(
      extensions: [t],
      colorScheme: colorScheme,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      dividerColor: t.sep2,
      textTheme: textTheme,
      splashFactory: style == NanoStyle.ios ? NoSplash.splashFactory : null,
      highlightColor: style == NanoStyle.ios ? Colors.transparent : null,
      iconTheme: IconThemeData(color: t.fg2),
      appBarTheme: AppBarTheme(
        backgroundColor: t.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: t.fg,
        centerTitle: false,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.card2,
        contentTextStyle: TextStyle(color: t.fg),
      ),
    );
  }
}
