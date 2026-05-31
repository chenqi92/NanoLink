import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../providers/app_provider.dart';
import '../screens/dashboard_screen.dart';
import '../screens/agents_screen.dart';
import '../screens/terminal_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/assistant_screen.dart';
import 'nano/nano_primitives.dart';

class _Dest {
  final IconData icon;
  final IconData activeIcon;
  final String labelKey;
  const _Dest(this.icon, this.activeIcon, this.labelKey);

  String get label => labelKey.tr();
}

const _destinations = <_Dest>[
  _Dest(Icons.grid_view_outlined, Icons.grid_view_rounded, 'nav.overview'),
  _Dest(Icons.dns_outlined, Icons.dns_rounded, 'nav.nodes'),
  _Dest(Icons.terminal_outlined, Icons.terminal_rounded, 'nav.terminal'),
  _Dest(Icons.notifications_none_rounded, Icons.notifications_rounded,
      'nav.activity'),
  _Dest(Icons.settings_outlined, Icons.settings_rounded, 'nav.settings'),
];

/// Adaptive navigation shell for the redesigned mobile app.
///
/// - iOS  → 5-item translucent tab bar.
/// - Material → 4-item NavigationBar + drawer (Settings / AI assistant).
/// - Wide layouts → NavigationRail sidebar.
class NanoShell extends StatefulWidget {
  const NanoShell({super.key});

  @override
  State<NanoShell> createState() => _NanoShellState();
}

class _NanoShellState extends State<NanoShell> {
  int _index = 0;

  static const _screens = <Widget>[
    DashboardScreen(),
    AgentsScreen(),
    TerminalScreen(),
    AlertsScreen(),
    SettingsScreen(),
  ];

  void _go(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final width = MediaQuery.sizeOf(context).width;
    final body = IndexedStack(index: _index, children: _screens);

    if (width > 800) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Row(
          children: [
            _Sidebar(index: _index, onSelect: _go),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (t.isIOS) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Stack(
          children: [
            Positioned.fill(child: body),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _IOSTabBar(index: _index, onSelect: _go),
            ),
          ],
        ),
      );
    }

    // Material
    return Scaffold(
      backgroundColor: t.bg,
      drawer: _MaterialDrawer(
        onSettings: () => _go(4),
        onAssistant: () {
          Navigator.pop(context);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AssistantScreen()),
          );
        },
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        backgroundColor: t.card,
        indicatorColor: t.accent.withValues(alpha: 0.18),
        selectedIndex: _index > 3 ? 0 : _index,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: _go,
        destinations: [
          for (var i = 0; i < 4; i++)
            NavigationDestination(
              icon: Icon(_destinations[i].icon, color: t.fg3),
              selectedIcon: Icon(_destinations[i].activeIcon, color: t.accent),
              label: _destinations[i].label,
            ),
        ],
      ),
    );
  }
}

class _IOSTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _IOSTabBar({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 12),
          decoration: BoxDecoration(
            color: t.tabBg,
            border: Border(top: BorderSide(color: t.sep, width: 0.5)),
          ),
          child: SizedBox(
            height: 50,
            child: Row(
              children: [
                for (var i = 0; i < _destinations.length; i++)
                  Expanded(
                    child: _TabButton(
                      dest: _destinations[i],
                      selected: index == i,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton(
      {required this.dest, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final color = selected ? t.accent : t.fg3;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? dest.activeIcon : dest.icon, size: 24, color: color),
          const SizedBox(height: 3),
          Text(
            dest.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _Sidebar({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: t.card,
        border: Border(right: BorderSide(color: t.sep2)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [t.accent, t.tertiary]),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.hub_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('NanoLink',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: t.fg)),
                ],
              ),
            ),
            Divider(height: 1, color: t.sep2),
            const SizedBox(height: 8),
            for (var i = 0; i < _destinations.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelect(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: index == i
                            ? t.accent.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            index == i
                                ? _destinations[i].activeIcon
                                : _destinations[i].icon,
                            size: 20,
                            color: index == i ? t.accent : t.fg3,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _destinations[i].label,
                            style: TextStyle(
                              color: index == i ? t.accent : t.fg2,
                              fontWeight: index == i
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AssistantScreen()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 20, color: t.accent),
                        const SizedBox(width: 12),
                        Text('nav.assistant'.tr(),
                            style: TextStyle(
                                color: t.fg2, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialDrawer extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onAssistant;
  const _MaterialDrawer({required this.onSettings, required this.onAssistant});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final provider = context.watch<AppProvider>();
    return Drawer(
      backgroundColor: t.bg2,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [t.accent, t.tertiary]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.hub_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NanoLink',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: t.fg)),
                      Text(
                          'shell.servers'.tr(
                              namedArgs: {'n': '${provider.servers.length}'}),
                          style: TextStyle(fontSize: 12, color: t.fg3)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _DrawerItem(
              icon: Icons.auto_awesome,
              label: 'shell.aiAssistant'.tr(),
              onTap: onAssistant,
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'shell.settings'.tr(),
              onTap: () {
                Navigator.pop(context);
                onSettings();
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('shell.footer'.tr(),
                  style: TextStyle(
                      fontSize: 11,
                      color: t.fg4,
                      fontFamilyFallback: kMonoFallback)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DrawerItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return ListTile(
      leading: Icon(icon, color: t.fg2),
      title: Text(label, style: TextStyle(color: t.fg, fontSize: 14)),
      shape: const StadiumBorder(),
      onTap: onTap,
    );
  }
}
