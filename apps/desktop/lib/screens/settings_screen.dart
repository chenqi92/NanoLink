import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../design/nano_tokens.dart';
import '../providers/app_provider.dart';
import '../providers/theme_provider.dart';
import '../services/storage_service.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';
import 'add_server_page.dart';
import 'assistant_screen.dart';
import 'device_pairing_screen.dart';
import 'server_detail_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = StorageService();
  bool _notifyOffline = true;
  bool _notifyHigh = true;
  bool _notifyDisk = true;

  static const _kNotifyOffline = 'notify_offline';
  static const _kNotifyHigh = 'notify_high';
  static const _kNotifyDisk = 'notify_disk';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final off = await _storage.getBool(_kNotifyOffline);
    final high = await _storage.getBool(_kNotifyHigh);
    final disk = await _storage.getBool(_kNotifyDisk);
    if (!mounted) return;
    setState(() {
      _notifyOffline = off;
      _notifyHigh = high;
      _notifyDisk = disk;
    });
  }

  void _setNotify(String key, bool value, ValueChanged<bool> apply) {
    setState(() => apply(value));
    _storage.setBool(key, value);
  }

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
              Text('settings.title'.tr(),
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
                  Text(
                      loggedIn
                          ? 'settings.loggedIn'.tr()
                          : 'settings.notLoggedIn'.tr(),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: t.fg)),
                  Text(
                      loggedIn
                          ? 'settings.loggedInSub'.tr()
                          : 'settings.notLoggedInSub'.tr(),
                      style: TextStyle(fontSize: 12.5, color: t.fg3)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel(
              'settings.servers'
                  .tr(namedArgs: {'n': '${provider.servers.length}'}),
              grouped: true),
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
                          NanoBadge('settings.current'.tr(), color: t.info),
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
                  child: Text('settings.addNewServer'.tr(),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: t.accent)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('settings.tools'.tr(), grouped: true),
          NanoCard(
            child: Column(
              children: [
                NanoListRow(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AssistantScreen())),
                  leading: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [t.accent, t.tertiary]),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.white, size: 15),
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    NanoBadge('MCP'),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, color: t.fg4),
                  ]),
                  child: Text('settings.aiAssistant'.tr(),
                      style: TextStyle(fontSize: 15, color: t.fg)),
                ),
                NanoListRow(
                  divider: false,
                  onTap: () => _openPairing(context, provider),
                  leading: NanoIconBox(Icons.qr_code_rounded,
                      size: 30, iconSize: 16, fg: t.accent),
                  trailing: Icon(Icons.chevron_right_rounded, color: t.fg4),
                  child: Text('settings.pairDevice'.tr(),
                      style: TextStyle(fontSize: 15, color: t.fg)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('settings.appearance'.tr(), grouped: true),
          NanoCard(
            child: Column(
              children: [
                _row(context,
                    label: 'settings.theme'.tr(),
                    value: _themeLabel(themeProvider.themeMode),
                    onTap: () => _pickTheme(context, themeProvider)),
                _row(context,
                    label: 'settings.language'.tr(),
                    value: context.locale.languageCode == 'zh'
                        ? 'settings.langChinese'.tr()
                        : 'settings.langEnglish'.tr(),
                    onTap: () => _pickLanguage(context),
                    divider: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('settings.notifications'.tr(), grouped: true),
          NanoCard(
            child: Column(
              children: [
                _toggle(context, 'settings.notifyOffline'.tr(), _notifyOffline,
                    (v) => _setNotify(
                        _kNotifyOffline, v, (x) => _notifyOffline = x)),
                _toggle(context, 'settings.notifyHigh'.tr(), _notifyHigh,
                    (v) =>
                        _setNotify(_kNotifyHigh, v, (x) => _notifyHigh = x)),
                _toggle(context, 'settings.notifyDisk'.tr(), _notifyDisk,
                    (v) => _setNotify(_kNotifyDisk, v, (x) => _notifyDisk = x),
                    divider: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('settings.about'.tr(), grouped: true),
          NanoCard(
            child: Column(
              children: [
                _row(context,
                    label: 'settings.version'.tr(),
                    value: 'v0.5.0',
                    onTap: null),
                _row(context,
                    label: 'settings.sourceCodeLabel'.tr(),
                    value: 'github.com/chenqi92/NanoLink',
                    onTap: null,
                    divider: false),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: NanoMono('settings.footer'.tr(), size: 11, color: t.fg4),
          ),
        ],
      ),
    );
  }

  void _openPairing(BuildContext context, AppProvider provider) {
    final full = provider.servers.where((s) => s.hasFullPermissions).toList();
    if (full.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('settings.pairNeedsLogin'.tr())));
      return;
    }
    final active = provider.activeServer;
    final targetId =
        (active != null && active.hasFullPermissions) ? active.id : full.first.id;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DevicePairingScreen(serverId: targetId)));
  }

  String _themeLabel(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.light:
        return 'settings.themeLight'.tr();
      case AppThemeMode.dark:
        return 'settings.themeDark'.tr();
      case AppThemeMode.system:
        return 'settings.themeSystem'.tr();
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
            for (final lang in [
              ['zh', 'settings.langChinese'.tr()],
              ['en', 'settings.langEnglish'.tr()],
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
