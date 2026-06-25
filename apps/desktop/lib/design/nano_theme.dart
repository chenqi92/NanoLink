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

    // Per-platform button metrics (iOS .ios-btn 50/14/17 vs Material .md-btn 40/100/14).
    final isIOS = style == NanoStyle.ios;
    final btnHeight = isIOS ? 50.0 : 40.0;
    final btnShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(t.buttonRadius),
    );
    final btnTextStyle = TextStyle(
      fontSize: isIOS ? 17 : 14,
      fontWeight: isIOS ? FontWeight.w600 : FontWeight.w500,
    );

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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          elevation: 0,
          minimumSize: Size(0, btnHeight),
          shape: btnShape,
          textStyle: btnTextStyle,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          elevation: 0,
          minimumSize: Size(0, btnHeight),
          shape: btnShape,
          textStyle: btnTextStyle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accent,
          minimumSize: Size(0, isIOS ? 44 : 40),
          shape: btnShape,
          textStyle: btnTextStyle,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.fg,
          side: BorderSide(color: isIOS ? t.sep : t.fg4),
          minimumSize: Size(0, btnHeight),
          shape: btnShape,
          textStyle: btnTextStyle,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // iOS = rounded card (radius 14); Material = .md-snack (#2C2B30, radius 4).
        backgroundColor: isIOS ? t.card2 : const Color(0xFF2C2B30),
        contentTextStyle:
            TextStyle(color: isIOS ? t.fg : const Color(0xFFE6E1E9)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isIOS ? 14 : 4),
        ),
      ),
    );
  }
}
