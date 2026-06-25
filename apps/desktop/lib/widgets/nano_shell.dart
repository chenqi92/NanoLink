import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../services/server_service.dart' show ConnectionMode;
import '../screens/dashboard_screen.dart';
import '../screens/agents_screen.dart';
import '../screens/terminal_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/assistant_screen.dart';
import '../screens/add_server_page.dart';
import '../screens/audit_log_screen.dart';
import '../screens/permissions_screen.dart';
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

/// App version string surfaced in the drawer header (mirrors settings.footer).
const String _kAppVersion = 'v0.5.0';

class _MaterialDrawer extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onAssistant;
  const _MaterialDrawer({required this.onSettings, required this.onAssistant});

  void _pushScreen(BuildContext context, Widget screen) {
    Navigator.pop(context); // close drawer
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final provider = context.watch<AppProvider>();
    final servers = provider.servers;
    final activeId = provider.activeServerId;

    return Drawer(
      backgroundColor: t.bg2,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header: brand + version ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 12),
                  Text('shell.appName'.tr(),
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: t.displayTracking,
                          color: t.fg)),
                  const SizedBox(height: 2),
                  Text(_kAppVersion,
                      style: TextStyle(
                          fontSize: 12,
                          color: t.fg3,
                          fontFamilyFallback: kMonoFallback)),
                ],
              ),
            ),
            // ── Scrollable nav body ──────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerSectionLabel('shell.sectionServers'.tr()),
                  for (final s in servers)
                    _ServerRow(
                      server: s,
                      active: s.id == activeId,
                      online:
                          provider.getConnectionMode(s.id) != ConnectionMode.disconnected,
                      agentCount: provider.agentsForServer(s.id).length,
                      onTap: () {
                        provider.setActiveServer(s.id);
                        Navigator.pop(context);
                      },
                    ),
                  _DrawerNavItem(
                    icon: Icons.add_rounded,
                    label: 'shell.addServer'.tr(),
                    accent: true,
                    onTap: () => _pushScreen(context, const AddServerPage()),
                  ),
                  _DrawerSectionLabel('shell.sectionOther'.tr()),
                  _DrawerNavItem(
                    icon: Icons.shield_outlined,
                    label: 'shell.permissions'.tr(),
                    onTap: () =>
                        _pushScreen(context, const PermissionsScreen()),
                  ),
                  _DrawerNavItem(
                    icon: Icons.history_rounded,
                    label: 'shell.auditLog'.tr(),
                    onTap: () => _pushScreen(context, const AuditLogScreen()),
                  ),
                  _DrawerNavItem(
                    icon: Icons.auto_awesome,
                    label: 'shell.aiAssistant'.tr(),
                    onTap: onAssistant,
                  ),
                  _DrawerNavItem(
                    icon: Icons.settings_outlined,
                    label: 'shell.settings'.tr(),
                    onTap: () {
                      Navigator.pop(context);
                      onSettings();
                    },
                  ),
                ],
              ),
            ),
            // ── User footer ──────────────────────────────────────────
            _DrawerUserFooter(provider: provider),
          ],
        ),
      ),
    );
  }
}

/// Uppercase grouping label inside the drawer (M3 "服务器" / "其他").
class _DrawerSectionLabel extends StatelessWidget {
  final String label;
  const _DrawerSectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 11.5,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w500,
              color: t.fg4)),
    );
  }
}

/// A server row in the drawer: status dot + name + url + agent count.
class _ServerRow extends StatelessWidget {
  final ServerConnection server;
  final bool active;
  final bool online;
  final int agentCount;
  final VoidCallback onTap;
  const _ServerRow({
    required this.server,
    required this.active,
    required this.online,
    required this.agentCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: Material(
        color: active ? t.accent.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                NanoStatusDot(
                    color: online ? t.ok : t.crit, pulse: online, size: 8),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w500,
                              color: active ? t.accent : t.fg2)),
                      const SizedBox(height: 1),
                      Text(server.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: t.fg4,
                              fontFamilyFallback: kMonoFallback)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('$agentCount',
                    style: TextStyle(
                        fontSize: 11,
                        color: t.fg4,
                        fontFamilyFallback: kMonoFallback)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A generic pill-shaped nav row in the drawer (M3 list item).
class _DrawerNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;
  const _DrawerNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final color = accent ? t.accent : t.fg2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 14),
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Footer with the active account avatar/name/role and a power (sign-out)
/// button. Signing out removes the active server connection.
class _DrawerUserFooter extends StatelessWidget {
  final AppProvider provider;
  const _DrawerUserFooter({required this.provider});

  /// Initials for the avatar, derived from the username or server name.
  String _initials(String source) {
    final cleaned = source.replaceAll(RegExp(r'[._@-]+'), ' ').trim();
    if (cleaned.isEmpty) return 'NL';
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
  }

  Future<void> _confirmSignOut(BuildContext context, ServerConnection s) async {
    final t = context.nano;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card2,
        title: Text('shell.signOutTitle'.tr(),
            style: TextStyle(color: t.fg, fontSize: 18)),
        content: Text('shell.signOutBody'.tr(namedArgs: {'name': s.name}),
            style: TextStyle(color: t.fg2, fontSize: 14, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr(),
                style: TextStyle(color: t.fg2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('shell.signOut'.tr(),
                style: TextStyle(color: t.crit)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await provider.removeServer(s.id);
      if (context.mounted) Navigator.pop(context); // close drawer
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final active = provider.activeServer;
    final username = (active?.username != null && active!.username!.isNotEmpty)
        ? active.username!
        : (active?.name ?? 'shell.appName'.tr());
    final hasAccount = active?.hasFullPermissions ?? false;
    final role = active == null
        ? 'shell.noServer'.tr()
        : (hasAccount ? 'shell.roleAccount'.tr() : 'shell.roleDevice'.tr());

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.sep2, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [t.accent, t.tertiary]),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(_initials(username),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.onAccent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: t.fg)),
                const SizedBox(height: 1),
                Text(role, style: TextStyle(fontSize: 11, color: t.fg3)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'shell.signOut'.tr(),
            icon: Icon(Icons.power_settings_new_rounded, color: t.fg3, size: 20),
            onPressed: active == null
                ? null
                : () => _confirmSignOut(context, active),
          ),
        ],
      ),
    );
  }
}
