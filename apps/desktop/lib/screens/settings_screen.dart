import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

/// Settings screen with theme and language options.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'nav.settings'.tr(),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // Appearance Section
            _buildSectionHeader('settings.appearance'.tr(), isDark),
            const SizedBox(height: 12),
            _buildGlassCard(
              isDark: isDark,
              child: Consumer<ThemeProvider>(
                builder: (context, themeProvider, _) {
                  return Column(
                    children: [
                      _buildSettingsTile(
                        icon: Icons.brightness_6_rounded,
                        title: 'settings.theme'.tr(),
                        trailing: SegmentedButton<AppThemeMode>(
                          segments: [
                            ButtonSegment(value: AppThemeMode.system, icon: Icon(Icons.brightness_auto_rounded)),
                            ButtonSegment(value: AppThemeMode.light, icon: Icon(Icons.light_mode_rounded)),
                            ButtonSegment(value: AppThemeMode.dark, icon: Icon(Icons.dark_mode_rounded)),
                          ],
                          selected: {themeProvider.themeMode},
                          onSelectionChanged: (value) => themeProvider.setThemeMode(value.first),
                          showSelectedIcon: false,
                          style: ButtonStyle(visualDensity: VisualDensity.compact),
                        ),
                        isDark: isDark,
                      ),
                      const Divider(height: 1),
                      _buildSettingsTile(
                        icon: Icons.language_rounded,
                        title: 'settings.language'.tr(),
                        trailing: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'en', label: Text('EN')),
                            ButtonSegment(value: 'zh', label: Text('中文')),
                          ],
                          selected: {context.locale.languageCode},
                          onSelectionChanged: (value) => context.setLocale(Locale(value.first)),
                          showSelectedIcon: false,
                          style: ButtonStyle(visualDensity: VisualDensity.compact),
                        ),
                        isDark: isDark,
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
            // About Section
            _buildSectionHeader('settings.about'.tr(), isDark),
            const SizedBox(height: 12),
            _buildGlassCard(
              isDark: isDark,
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: 'settings.version'.tr(),
                    trailing: const Text('0.5.0'),
                    isDark: isDark,
                  ),
                  const Divider(height: 1),
                  _buildSettingsTile(
                    icon: Icons.code_rounded,
                    title: 'settings.sourceCode'.tr(),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () {
                      // TODO: Open GitHub
                    },
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
      ),
    );
  }

  Widget _buildGlassCard({required bool isDark, required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard.withValues(alpha: 0.5) : AppTheme.lightCard.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder.withValues(alpha: 0.3) : AppTheme.lightBorder.withValues(alpha: 0.5),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required Widget trailing,
    VoidCallback? onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppTheme.primaryBlue),
            const SizedBox(width: 16),
            Expanded(child: Text(title)),
            trailing,
          ],
        ),
      ),
    );
  }
}
