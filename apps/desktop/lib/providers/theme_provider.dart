import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

/// Theme mode enum
enum AppThemeMode { light, dark, system }

/// Theme provider managing light/dark mode
class ThemeProvider extends ChangeNotifier {
  static const _themeModeKey = 'theme_mode';
  
  AppThemeMode _themeMode = AppThemeMode.dark;
  AppThemeMode get themeMode => _themeMode;
  
  bool get isDarkMode {
    if (_themeMode == AppThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
    return _themeMode == AppThemeMode.dark;
  }

  ThemeMode get materialThemeMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  /// Initialize theme from storage
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_themeModeKey) ?? 1; // Default to dark
    _themeMode = AppThemeMode.values[modeIndex.clamp(0, 2)];
    notifyListeners();
  }

  /// Set theme mode
  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  /// Cycle through theme modes
  void cycleTheme() {
    final modes = AppThemeMode.values;
    final nextIndex = (modes.indexOf(_themeMode) + 1) % modes.length;
    setThemeMode(modes[nextIndex]);
  }
}
