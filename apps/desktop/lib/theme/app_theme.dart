import 'dart:ui';
import 'package:flutter/material.dart';

/// Glassmorphism Design System for NanoLink Desktop
///
/// Features:
/// - Frosted glass effects with backdrop blur
/// - Gradient backgrounds and overlays
/// - Soft shadows and glow effects
/// - Consistent spacing and border radius
class AppTheme {
  // ==========================================================================
  // Brand Colors
  // ==========================================================================
  static const primaryBlue = Color(0xFF3B82F6);
  static const secondaryBlue = Color(0xFF60A5FA);
  static const accentCyan = Color(0xFF22D3EE);

  // Status colors
  static const successGreen = Color(0xFF22C55E);
  static const warningYellow = Color(0xFFEAB308);
  static const errorRed = Color(0xFFEF4444);
  static const infoCyan = Color(0xFF06B6D4);

  // GPU/NPU colors
  static const gpuPurple = Color(0xFF8B5CF6);
  static const npuIndigo = Color(0xFF6366F1);

  // ==========================================================================
  // Dark Theme Colors
  // ==========================================================================
  static const darkBackground = Color(0xFF0A0F1C);
  static const darkSurface = Color(0xFF111827);
  static const darkCard = Color(0xFF1F2937);
  static const darkBorder = Color(0xFF374151);
  static const darkText = Color(0xFFF9FAFB);
  static const darkTextSecondary = Color(0xFF9CA3AF);

  // ==========================================================================
  // Light Theme Colors
  // ==========================================================================
  static const lightBackground = Color(0xFFF0F4F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE5E7EB);
  static const lightText = Color(0xFF111827);
  static const lightTextSecondary = Color(0xFF6B7280);

  // ==========================================================================
  // Glassmorphism Settings
  // ==========================================================================
  static const double glassBlur = 20.0;
  static const double glassOpacity = 0.1;
  static const double glassBorderOpacity = 0.2;

  // ==========================================================================
  // Spacing & Radius
  // ==========================================================================
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;

  static const double spacingXSmall = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 12.0;
  static const double spacingLarge = 16.0;
  static const double spacingXLarge = 24.0;

  // ==========================================================================
  // Gradients
  // ==========================================================================
  static const darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
  );

  static const lightGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF0F4F8), Color(0xFFE0E7FF)],
  );

  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBlue, accentCyan],
  );

  static const successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22C55E), Color(0xFF10B981)],
  );

  // ==========================================================================
  // Utility Methods
  // ==========================================================================

  /// Get status color based on percentage value
  static Color getStatusColor(double percent) {
    if (percent > 80) return errorRed;
    if (percent > 50) return warningYellow;
    return successGreen;
  }

  /// Get glow shadow for a given color
  static List<BoxShadow> getGlowShadow(Color color, {double intensity = 0.4}) {
    return [
      BoxShadow(
        color: color.withValues(alpha: intensity),
        blurRadius: 12,
        spreadRadius: 2,
      ),
    ];
  }

  /// Get soft shadow for cards
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.1),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  // ==========================================================================
  // Dark Theme
  // ==========================================================================
  static ThemeData darkTheme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: darkBackground,
    colorScheme: const ColorScheme.dark(
      primary: primaryBlue,
      secondary: secondaryBlue,
      tertiary: accentCyan,
      surface: darkSurface,
      error: errorRed,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: darkText,
      onError: Colors.white,
      outline: darkBorder,
    ),
    cardTheme: CardThemeData(
      color: darkCard.withValues(alpha: 0.8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
        side: BorderSide(
          color: darkBorder.withValues(alpha: glassBorderOpacity),
          width: 1,
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: darkText,
      titleTextStyle: TextStyle(
        color: darkText,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCard.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: BorderSide(color: darkBorder.withValues(alpha: 0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: BorderSide(color: darkBorder.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: errorRed),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: spacingLarge,
        vertical: 14,
      ),
      hintStyle: TextStyle(color: darkTextSecondary.withValues(alpha: 0.6)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return Colors.white.withValues(alpha: 0.1);
          }
          if (states.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.2);
          }
          return null;
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryBlue,
        side: const BorderSide(color: primaryBlue),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: darkTextSecondary,
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return primaryBlue.withValues(alpha: 0.1);
          }
          return null;
        }),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: darkBorder.withValues(alpha: 0.5),
      thickness: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: darkCard.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(radiusSmall),
        border: Border.all(color: darkBorder.withValues(alpha: 0.3)),
        boxShadow: cardShadow,
      ),
      textStyle: const TextStyle(
        color: darkText,
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXLarge),
        side: BorderSide(color: darkBorder.withValues(alpha: 0.3)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkCard,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      contentTextStyle: const TextStyle(color: darkText),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryBlue,
      linearTrackColor: darkBorder,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: primaryBlue,
      inactiveTrackColor: darkBorder,
      thumbColor: primaryBlue,
      overlayColor: primaryBlue.withValues(alpha: 0.2),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: darkCard,
      selectedColor: primaryBlue.withValues(alpha: 0.2),
      labelStyle: const TextStyle(color: darkText, fontSize: 12),
      side: BorderSide(color: darkBorder.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: darkSurface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        side: BorderSide(color: darkBorder.withValues(alpha: 0.3)),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: darkText,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: darkText,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: darkText,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: darkText,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(color: darkText, fontSize: 16),
      bodyMedium: TextStyle(color: darkText, fontSize: 14),
      bodySmall: TextStyle(color: darkTextSecondary, fontSize: 12),
      labelLarge: TextStyle(
        color: darkText,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  // ==========================================================================
  // Light Theme
  // ==========================================================================
  static ThemeData lightTheme = ThemeData.light().copyWith(
    scaffoldBackgroundColor: lightBackground,
    colorScheme: const ColorScheme.light(
      primary: primaryBlue,
      secondary: secondaryBlue,
      tertiary: accentCyan,
      surface: lightSurface,
      error: errorRed,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: lightText,
      onError: Colors.white,
      outline: lightBorder,
    ),
    cardTheme: CardThemeData(
      color: lightCard.withValues(alpha: 0.9),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
        side: BorderSide(
          color: lightBorder.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: lightText,
      iconTheme: IconThemeData(color: lightTextSecondary),
      titleTextStyle: TextStyle(
        color: lightText,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightSurface.withValues(alpha: 0.8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: errorRed),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: spacingLarge,
        vertical: 14,
      ),
      hintStyle: TextStyle(color: lightTextSecondary.withValues(alpha: 0.6)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return Colors.white.withValues(alpha: 0.1);
          }
          if (states.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.2);
          }
          return null;
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryBlue,
        side: const BorderSide(color: primaryBlue),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: lightTextSecondary,
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return primaryBlue.withValues(alpha: 0.1);
          }
          return null;
        }),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: lightBorder.withValues(alpha: 0.8),
      thickness: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: lightSurface,
        borderRadius: BorderRadius.circular(radiusSmall),
        border: Border.all(color: lightBorder),
        boxShadow: cardShadow,
      ),
      textStyle: const TextStyle(
        color: lightText,
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXLarge),
        side: BorderSide(color: lightBorder.withValues(alpha: 0.5)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: lightText,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      contentTextStyle: const TextStyle(color: lightSurface),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryBlue,
      linearTrackColor: lightBorder,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: primaryBlue,
      inactiveTrackColor: lightBorder,
      thumbColor: primaryBlue,
      overlayColor: primaryBlue.withValues(alpha: 0.2),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: lightSurface,
      selectedColor: primaryBlue.withValues(alpha: 0.15),
      labelStyle: const TextStyle(color: lightText, fontSize: 12),
      side: const BorderSide(color: lightBorder),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: lightSurface,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        side: const BorderSide(color: lightBorder),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: lightText,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
      headlineMedium: TextStyle(
        color: lightText,
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: lightText,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: lightText,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyLarge: TextStyle(color: lightText, fontSize: 16),
      bodyMedium: TextStyle(color: lightText, fontSize: 14),
      bodySmall: TextStyle(color: lightTextSecondary, fontSize: 12),
      labelLarge: TextStyle(
        color: lightText,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

// =============================================================================
// Glassmorphism Widgets
// =============================================================================

/// A container with frosted glass effect
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final Color? backgroundColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = AppTheme.glassBlur,
    this.backgroundColor,
    this.borderRadius = AppTheme.radiusLarge,
    this.padding,
    this.margin,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = backgroundColor ??
        (isDark
            ? AppTheme.darkCard.withValues(alpha: 0.6)
            : AppTheme.lightCard.withValues(alpha: 0.7));

    final borderColor = isDark
        ? AppTheme.darkBorder.withValues(alpha: AppTheme.glassBorderOpacity)
        : AppTheme.lightBorder.withValues(alpha: 0.5);

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: border ?? Border.all(color: borderColor, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A card with glass effect and optional gradient overlay
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final bool showGlow;
  final Color? glowColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.gradient,
    this.showGlow = false,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget content = GlassContainer(
      padding: padding ?? const EdgeInsets.all(AppTheme.spacingLarge),
      margin: margin,
      child: child,
    );

    if (gradient != null) {
      content = Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        child: content,
      );
    }

    if (showGlow && glowColor != null) {
      content = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          boxShadow: AppTheme.getGlowShadow(glowColor!),
        ),
        child: content,
      );
    }

    if (onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Status indicator dot with glow effect
class StatusIndicator extends StatelessWidget {
  final bool isOnline;
  final double size;

  const StatusIndicator({
    super.key,
    this.isOnline = true,
    this.size = 10,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppTheme.successGreen : AppTheme.errorRed;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: size,
            spreadRadius: size / 4,
          ),
        ],
      ),
    );
  }
}

/// Animated progress bar with gradient
class GradientProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? backgroundColor;
  final Gradient? gradient;
  final Color? color;

  const GradientProgressBar({
    super.key,
    required this.value,
    this.height = 6,
    this.backgroundColor,
    this.gradient,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = backgroundColor ??
        (isDark
            ? AppTheme.darkBorder.withValues(alpha: 0.3)
            : AppTheme.lightBorder.withValues(alpha: 0.5));

    final progressColor = color ?? AppTheme.getStatusColor(value * 100);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: gradient ??
                LinearGradient(
                  colors: [progressColor, progressColor.withValues(alpha: 0.8)],
                ),
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: [
              BoxShadow(
                color: progressColor.withValues(alpha: 0.3),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
