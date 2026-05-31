import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../design/nano_tokens.dart';
import '../providers/app_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';
import 'add_server_page.dart';
import 'assistant_screen.dart';
import 'server_detail_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifyOffline = true;
  bool _notifyHigh = true;
  bool _notifyDisk = true;

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final provider = context.watch<AppProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final loggedIn = provider.servers.any((s) => s.hasFullPermissions);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, t.isIOS ? 40 : 8, 16, 96),
        children: [
          Row(
            children: [
              if (!t.isIOS)
                Builder(
                  builder: (ctx) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      icon: Icon(Icons.menu_rounded, color: t.fg),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                ),
              Text('设置',
                  style: TextStyle(
                      fontSize: t.isIOS ? 32 : 28,
                      fontWeight: t.displayWeight,
                      letterSpacing: t.displayTracking,
                      color: t.fg)),
            ],
          ),
          const SizedBox(height: 12),
          // user card
          NanoCard(
            child: NanoListRow(
              divider: false,
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [t.accent, t.tertiary]),
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: t.fg4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loggedIn ? '已登录账号' : '未登录',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: t.fg)),
                  Text(loggedIn ? '使用账号连接，拥有完整权限' : '设备令牌模式 · 只读访问',
                      style: TextStyle(fontSize: 12.5, color: t.fg3)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('服务器 (${provider.servers.length})', grouped: true),
          NanoCard(
            child: Column(
              children: [
                for (final s in provider.servers)
                  NanoListRow(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ServerDetailScreen(serverId: s.id))),
                    leading: NanoIconBox(Icons.dns_rounded),
                    trailing: Icon(Icons.chevron_right_rounded, color: t.fg4),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(s.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: t.fg)),
                        ),
                        if (s.id == provider.activeServerId) ...[
                          const SizedBox(width: 6),
                          NanoBadge('当前', color: t.info),
                        ],
                      ],
                    ),
                  ),
                NanoListRow(
                  divider: false,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AddServerPage())),
                  leading: NanoIconBox(Icons.add_rounded,
                      bg: t.accent.withValues(alpha: 0.14), fg: t.accent),
                  child: Text('添加新服务器',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: t.accent)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('工具', grouped: true),
          NanoCard(
            child: NanoListRow(
              divider: false,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AssistantScreen())),
              leading: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [t.accent, t.tertiary]),
                  borderRadius: BorderRadius.circular(7),
                ),
                child:
                    const Icon(Icons.auto_awesome, color: Colors.white, size: 15),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                NanoBadge('MCP'),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: t.fg4),
              ]),
              child: Text('AI 运维助手',
                  style: TextStyle(fontSize: 15, color: t.fg)),
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('外观', grouped: true),
          NanoCard(
            child: Column(
              children: [
                _row(context,
                    label: '主题',
                    value: _themeLabel(themeProvider.themeMode),
                    onTap: () => _pickTheme(context, themeProvider)),
                _row(context,
                    label: '语言',
                    value: context.locale.languageCode == 'zh'
                        ? '中文（简体）'
                        : 'English',
                    onTap: () => _pickLanguage(context),
                    divider: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('通知', grouped: true),
          NanoCard(
            child: Column(
              children: [
                _toggle(context, '离线告警', _notifyOffline,
                    (v) => setState(() => _notifyOffline = v)),
                _toggle(context, '高 CPU / 内存', _notifyHigh,
                    (v) => setState(() => _notifyHigh = v)),
                _toggle(context, '磁盘空间', _notifyDisk,
                    (v) => setState(() => _notifyDisk = v), divider: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('关于', grouped: true),
          NanoCard(
            child: Column(
              children: [
                _row(context, label: '版本', value: 'v0.5.0', onTap: null),
                _row(context,
                    label: '源码',
                    value: 'github.com/chenqi92/NanoLink',
                    onTap: null,
                    divider: false),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: NanoMono('NanoLink Mobile · v0.5.0', size: 11, color: t.fg4),
          ),
        ],
      ),
    );
  }

  String _themeLabel(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
      case AppThemeMode.system:
        return '跟随系统';
    }
  }

  void _pickTheme(BuildContext context, ThemeProvider tp) {
    final t = context.nano;
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(t.isIOS ? 16 : 28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in AppThemeMode.values)
              NanoListRow(
                divider: m != AppThemeMode.values.last,
                trailing: tp.themeMode == m
                    ? Icon(Icons.check_rounded, color: t.accent)
                    : null,
                onTap: () {
                  tp.setThemeMode(m);
                  Navigator.pop(ctx);
                },
                child: Text(_themeLabel(m),
                    style: TextStyle(fontSize: 15, color: t.fg)),
              ),
          ],
        ),
      ),
    );
  }

  void _pickLanguage(BuildContext context) {
    final t = context.nano;
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(t.isIOS ? 16 : 28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final lang in const [
              ['zh', '中文（简体）'],
              ['en', 'English'],
            ])
              NanoListRow(
                divider: lang[0] == 'zh',
                trailing: context.locale.languageCode == lang[0]
                    ? Icon(Icons.check_rounded, color: t.accent)
                    : null,
                onTap: () {
                  context.setLocale(Locale(lang[0]));
                  Navigator.pop(ctx);
                },
                child: Text(lang[1],
                    style: TextStyle(fontSize: 15, color: t.fg)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context,
      {required String label,
      String? value,
      VoidCallback? onTap,
      bool divider = true}) {
    final t = context.nano;
    return NanoListRow(
      divider: divider,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: t.fg3)),
            ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: t.fg4, size: 18),
          ],
        ],
      ),
      child: Text(label, style: TextStyle(fontSize: 15, color: t.fg)),
    );
  }

  Widget _toggle(BuildContext context, String label, bool value,
      ValueChanged<bool> onChanged,
      {bool divider = true}) {
    final t = context.nano;
    return NanoListRow(
      divider: divider,
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: t.ok,
        onChanged: onChanged,
      ),
      child: Text(label, style: TextStyle(fontSize: 15, color: t.fg)),
    );
  }
}
