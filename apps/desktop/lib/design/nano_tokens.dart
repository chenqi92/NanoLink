import 'package:flutter/material.dart';

/// Visual language of the redesigned NanoLink mobile app.
///
/// The design ships two platform looks that share the same data and primitives:
/// - [NanoStyle.ios]  — Apple system colors, large titles, grouped cards.
/// - [NanoStyle.md]   — Material 3 / Material You surfaces.
///
/// All concrete color values mirror `design/nanolink/mobile/mobile-tokens.css`.
enum NanoStyle { ios, md }

/// Design tokens exposed through the Flutter [Theme] as a [ThemeExtension].
///
/// Read with `NanoTokens.of(context)` (or `context.nano`). Widgets should pull
/// every color/spacing value from here instead of hard-coding, so a single
/// place controls the iOS vs Material palettes in light and dark.
@immutable
class NanoTokens extends ThemeExtension<NanoTokens> {
  final NanoStyle style;
  final Brightness brightness;

  // Surfaces / backgrounds
  final Color bg; // page background
  final Color bg2; // secondary background
  final Color card; // primary grouped card / surface
  final Color card2; // nested / pressed surface
  final Color card3; // meter track / deepest surface
  final Color sep; // separators (stronger)
  final Color sep2; // separators (hairline)

  // Foreground text tiers
  final Color fg;
  final Color fg2;
  final Color fg3;
  final Color fg4;
  final Color fg5;

  // Accents
  final Color accent;
  final Color onAccent;
  final Color secondary;
  final Color tertiary;

  // Chrome
  final Color tabBg; // tab bar / bottom nav background
  final Color glassBorder;

  // Status (shared across platforms)
  final Color ok;
  final Color warn;
  final Color crit;
  final Color info;

  const NanoTokens({
    required this.style,
    required this.brightness,
    required this.bg,
    required this.bg2,
    required this.card,
    required this.card2,
    required this.card3,
    required this.sep,
    required this.sep2,
    required this.fg,
    required this.fg2,
    required this.fg3,
    required this.fg4,
    required this.fg5,
    required this.accent,
    required this.onAccent,
    required this.secondary,
    required this.tertiary,
    required this.tabBg,
    required this.glassBorder,
    required this.ok,
    required this.warn,
    required this.crit,
    required this.info,
  });

  bool get isDark => brightness == Brightness.dark;
  bool get isIOS => style == NanoStyle.ios;

  /// Corner radius conventions per platform.
  double get cardRadius => isIOS ? 14 : 16;
  double get fieldRadius => isIOS ? 12 : 8;
  double get buttonRadius => isIOS ? 14 : 100;

  /// Display title weight (iOS is heavier/tighter than Material You).
  FontWeight get displayWeight => isIOS ? FontWeight.w700 : FontWeight.w500;
  double get displayTracking => isIOS ? -0.8 : -0.3;

  // ── shared status palette ───────────────────────────────────────────────
  static const _ok = Color(0xFF30D158);
  static const _warn = Color(0xFFFFB020);
  static const _crit = Color(0xFFFF453A);
  static const _info = Color(0xFF0A84FF);

  /// Color for a 0-100 usage value: ok < 75 < warn < 90 < crit.
  Color usageColor(double pct) {
    if (pct > 90) return crit;
    if (pct > 75) return warn;
    return fg;
  }

  /// Tone color for meters/sparks (ok keeps accent for charts).
  Color meterColor(double pct) {
    if (pct > 90) return crit;
    if (pct > 75) return warn;
    return fg2;
  }

  /// Permission-level pill color (L0..L3).
  Color permColor(int level) {
    switch (level) {
      case 1:
        return _info;
      case 2:
        return warn;
      case 3:
        return crit;
      default:
        return const Color(0xFFA3A3A3);
    }
  }

  // ── factory palettes (1:1 with mobile-tokens.css) ───────────────────────
  factory NanoTokens.iosDark() => const NanoTokens(
        style: NanoStyle.ios,
        brightness: Brightness.dark,
        bg: Color(0xFF000000),
        bg2: Color(0xFF0A0A0A),
        card: Color(0xFF1C1C1E),
        card2: Color(0xFF2C2C2E),
        card3: Color(0xFF3A3A3C),
        sep: Color(0x80545458), // rgba(84,84,88,0.5)
        sep2: Color(0x52545458), // rgba(84,84,88,0.32)
        fg: Color(0xFFFFFFFF),
        fg2: Color(0xD9EBEBF5), // rgba(235,235,245,0.85)
        fg3: Color(0x99EBEBF5),
        fg4: Color(0x66EBEBF5),
        fg5: Color(0x40EBEBF5),
        accent: Color(0xFF0A84FF),
        onAccent: Color(0xFFFFFFFF),
        secondary: Color(0xFF0A84FF),
        tertiary: Color(0xFF5E5CE6),
        tabBg: Color(0xC71C1C1E), // rgba(28,28,30,0.78)
        glassBorder: Color(0x12FFFFFF),
        ok: _ok,
        warn: _warn,
        crit: _crit,
        info: _info,
      );

  factory NanoTokens.iosLight() => const NanoTokens(
        style: NanoStyle.ios,
        brightness: Brightness.light,
        bg: Color(0xFFF2F2F7),
        bg2: Color(0xFFE5E5EA),
        card: Color(0xFFFFFFFF),
        card2: Color(0xFFF2F2F7),
        card3: Color(0xFFE5E5EA),
        sep: Color(0x4A3C3C43), // rgba(60,60,67,0.29)
        sep2: Color(0x2E3C3C43),
        fg: Color(0xFF000000),
        fg2: Color(0xDB3C3C43),
        fg3: Color(0x993C3C43),
        fg4: Color(0x663C3C43),
        fg5: Color(0x403C3C43),
        accent: Color(0xFF007AFF),
        onAccent: Color(0xFFFFFFFF),
        secondary: Color(0xFF007AFF),
        tertiary: Color(0xFF5856D6),
        tabBg: Color(0xC7F8F8F8),
        glassBorder: Color(0x12000000),
        ok: _ok,
        warn: _warn,
        crit: _crit,
        info: _info,
      );

  factory NanoTokens.mdDark() => const NanoTokens(
        style: NanoStyle.md,
        brightness: Brightness.dark,
        bg: Color(0xFF131318),
        bg2: Color(0xFF1B1B21),
        card: Color(0xFF1F1F25), // surface-2
        card2: Color(0xFF28282E), // surface-3
        card3: Color(0xFF36363D),
        sep: Color(0xFF2A2A30),
        sep2: Color(0xFF36363D),
        fg: Color(0xFFE6E1E9),
        fg2: Color(0xFFCAC4D0),
        fg3: Color(0xFF938F99),
        fg4: Color(0xFF79747E),
        fg5: Color(0xFF49454F),
        accent: Color(0xFFB4C5FF),
        onAccent: Color(0xFF1B2C5D),
        secondary: Color(0xFFC6C2DC),
        tertiary: Color(0xFFEEB8E8),
        tabBg: Color(0xF21F1F25),
        glassBorder: Color(0x14FFFFFF),
        ok: _ok,
        warn: _warn,
        crit: _crit,
        info: _info,
      );

  factory NanoTokens.mdLight() => const NanoTokens(
        style: NanoStyle.md,
        brightness: Brightness.light,
        bg: Color(0xFFFFFBFF),
        bg2: Color(0xFFF4EFF4),
        card: Color(0xFFECE6EB), // surface-2
        card2: Color(0xFFE6E0E9), // surface-3
        card3: Color(0xFFE6E0E9),
        sep: Color(0xFFE6E0E9),
        sep2: Color(0xFFECE6EB),
        fg: Color(0xFF1C1B1F),
        fg2: Color(0xFF49454F),
        fg3: Color(0xFF79747E),
        fg4: Color(0xFF938F99),
        fg5: Color(0xFFCAC4D0),
        accent: Color(0xFF4F5A86),
        onAccent: Color(0xFFFFFFFF),
        secondary: Color(0xFF5A5D72),
        tertiary: Color(0xFF7E5260),
        tabBg: Color(0xEBFFFBFF),
        glassBorder: Color(0x14000000),
        ok: _ok,
        warn: _warn,
        crit: _crit,
        info: _info,
      );

  /// Resolve the tokens for a [style] + [brightness] pair.
  factory NanoTokens.resolve(NanoStyle style, Brightness brightness) {
    if (style == NanoStyle.ios) {
      return brightness == Brightness.dark
          ? NanoTokens.iosDark()
          : NanoTokens.iosLight();
    }
    return brightness == Brightness.dark
        ? NanoTokens.mdDark()
        : NanoTokens.mdLight();
  }

  static NanoTokens of(BuildContext context) {
    return Theme.of(context).extension<NanoTokens>() ?? NanoTokens.iosDark();
  }

  @override
  NanoTokens copyWith({
    NanoStyle? style,
    Brightness? brightness,
    Color? bg,
    Color? bg2,
    Color? card,
    Color? card2,
    Color? card3,
    Color? sep,
    Color? sep2,
    Color? fg,
    Color? fg2,
    Color? fg3,
    Color? fg4,
    Color? fg5,
    Color? accent,
    Color? onAccent,
    Color? secondary,
    Color? tertiary,
    Color? tabBg,
    Color? glassBorder,
    Color? ok,
    Color? warn,
    Color? crit,
    Color? info,
  }) {
    return NanoTokens(
      style: style ?? this.style,
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      bg2: bg2 ?? this.bg2,
      card: card ?? this.card,
      card2: card2 ?? this.card2,
      card3: card3 ?? this.card3,
      sep: sep ?? this.sep,
      sep2: sep2 ?? this.sep2,
      fg: fg ?? this.fg,
      fg2: fg2 ?? this.fg2,
      fg3: fg3 ?? this.fg3,
      fg4: fg4 ?? this.fg4,
      fg5: fg5 ?? this.fg5,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
      tabBg: tabBg ?? this.tabBg,
      glassBorder: glassBorder ?? this.glassBorder,
      ok: ok ?? this.ok,
      warn: warn ?? this.warn,
      crit: crit ?? this.crit,
      info: info ?? this.info,
    );
  }

  @override
  NanoTokens lerp(ThemeExtension<NanoTokens>? other, double t) {
    if (other is! NanoTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return NanoTokens(
      style: t < 0.5 ? style : other.style,
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: c(bg, other.bg),
      bg2: c(bg2, other.bg2),
      card: c(card, other.card),
      card2: c(card2, other.card2),
      card3: c(card3, other.card3),
      sep: c(sep, other.sep),
      sep2: c(sep2, other.sep2),
      fg: c(fg, other.fg),
      fg2: c(fg2, other.fg2),
      fg3: c(fg3, other.fg3),
      fg4: c(fg4, other.fg4),
      fg5: c(fg5, other.fg5),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      secondary: c(secondary, other.secondary),
      tertiary: c(tertiary, other.tertiary),
      tabBg: c(tabBg, other.tabBg),
      glassBorder: c(glassBorder, other.glassBorder),
      ok: c(ok, other.ok),
      warn: c(warn, other.warn),
      crit: c(crit, other.crit),
      info: c(info, other.info),
    );
  }
}

/// Monospace text style helper (no bundled mono font; rely on platform fonts).
const List<String> kMonoFallback = [
  'SF Mono',
  'Menlo',
  'JetBrains Mono',
  'Roboto Mono',
  'Consolas',
  'monospace',
];

extension NanoContext on BuildContext {
  NanoTokens get nano => NanoTokens.of(this);
}
