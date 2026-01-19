import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../screens/dashboard_screen.dart';
import '../screens/agents_screen.dart';
import '../screens/terminal_screen.dart';
import '../screens/settings_screen.dart';
import '../theme/app_theme.dart';
import 'dart:ui';

/// Adaptive shell providing navigation for mobile (bottom bar) and desktop (sidebar).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _isSidebarExpanded = true;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const AgentsScreen(),
    const TerminalScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width > 800;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: isDesktop ? _buildDesktopLayout(isDark) : _buildMobileLayout(isDark),
      ),
    );
  }

  Widget _buildMobileLayout(bool isDark) {
    return Column(
      children: [
        Expanded(child: _screens[_selectedIndex]),
        _buildGlassNavigationBar(isDark),
      ],
    );
  }

  Widget _buildDesktopLayout(bool isDark) {
    return Row(
      children: [
        _buildSidebar(isDark),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: _screens[_selectedIndex]),
      ],
    );
  }

  Widget _buildGlassNavigationBar(bool isDark) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.darkCard.withValues(alpha: 0.6)
                : AppTheme.lightCard.withValues(alpha: 0.7),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? AppTheme.primaryBlue.withValues(alpha: 0.3)
                    : AppTheme.primaryBlue.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 65, // Standard mobile navigation bar height
              child: NavigationBar(
                backgroundColor: Colors.transparent,
                indicatorColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                height: 65,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.dashboard_outlined, size: 22),
                    selectedIcon: Icon(Icons.dashboard_rounded, color: AppTheme.primaryBlue, size: 22),
                    label: 'nav.dashboard'.tr(),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.devices_other_outlined, size: 22),
                    selectedIcon: Icon(Icons.devices_other_rounded, color: AppTheme.primaryBlue, size: 22),
                    label: 'nav.agents'.tr(),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.terminal_outlined, size: 22),
                    selectedIcon: Icon(Icons.terminal_rounded, color: AppTheme.primaryBlue, size: 22),
                    label: 'nav.terminal'.tr(),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.settings_outlined, size: 22),
                    selectedIcon: Icon(Icons.settings_rounded, color: AppTheme.primaryBlue, size: 22),
                    label: 'nav.settings'.tr(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(bool isDark) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: _isSidebarExpanded ? 220 : 72,
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.darkCard.withValues(alpha: 0.6)
                : AppTheme.lightCard.withValues(alpha: 0.7),
            border: Border(
              right: BorderSide(
                color: isDark
                    ? AppTheme.darkBorder.withValues(alpha: 0.3)
                    : AppTheme.lightBorder.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.developer_board, color: Colors.white, size: 22),
                    ),
                    if (_isSidebarExpanded) ...[
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'NanoLink',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              // Navigation Items
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _buildNavItem(0, Icons.dashboard_outlined, Icons.dashboard_rounded, 'nav.dashboard'.tr(), isDark),
                    _buildNavItem(1, Icons.devices_other_outlined, Icons.devices_other_rounded, 'nav.agents'.tr(), isDark),
                    _buildNavItem(2, Icons.terminal_outlined, Icons.terminal_rounded, 'nav.terminal'.tr(), isDark),
                    _buildNavItem(3, Icons.settings_outlined, Icons.settings_rounded, 'nav.settings'.tr(), isDark),
                  ],
                ),
              ),
              // Collapse Button
              Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  icon: Icon(_isSidebarExpanded ? Icons.chevron_left : Icons.chevron_right),
                  onPressed: () => setState(() => _isSidebarExpanded = !_isSidebarExpanded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData selectedIcon, String label, bool isDark) {
    final isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: _isSidebarExpanded ? 16 : 12,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryBlue.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  color: isSelected ? AppTheme.primaryBlue : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                  size: 22,
                ),
                if (_isSidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? AppTheme.primaryBlue : null,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
