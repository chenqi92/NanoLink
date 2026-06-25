import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design/nano_tokens.dart';
import '../providers/app_provider.dart';
import '../providers/theme_provider.dart';
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
  // Notification preference keys (existing three live on AppProvider; the
  // fourth — audit-log push — is local-only and foreground-only here).
  static const _kNotifyAudit = 'notify_audit';

  // Appearance / density.
  static const _kCompact = 'ui_compact';

  // Terminal preferences (persisted locally; consumed by the shell screen).
  static const _kTermTheme = 'term_theme';
  static const _kTermFontSize = 'term_font_size';
  static const _kTermCursor = 'term_cursor';
  static const _kTermBlink = 'term_cursor_blink';

  // Security preferences (persisted; enforcement is a follow-up, no native
  // biometric deps are added here).
  static const _kFaceId = 'sec_face_id';
  static const _kAutoLock = 'sec_auto_lock'; // minutes, 0 = off

  // Terminal theme options: id -> i18n label key.
  static const _termThemes = ['phosphor', 'amber', 'mono', 'solarized'];
  static const _termCursors = ['block', 'bar', 'underline'];
  static const _termFontSizes = [11, 12, 13, 14, 15, 16];
  static const _autoLockOptions = [0, 1, 2, 5, 10]; // minutes (0 = off)

  bool _notifyAudit = false;
  bool _compact = false;
  String _termTheme = 'phosphor';
  int _termFontSize = 13;
  String _termCursor = 'block';
  bool _termBlink = true;
  bool _faceId = false;
  int _autoLock = 2;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifyAudit = prefs.getBool(_kNotifyAudit) ?? false;
      _compact = prefs.getBool(_kCompact) ?? false;
      _termTheme = prefs.getString(_kTermTheme) ?? 'phosphor';
      _termFontSize = prefs.getInt(_kTermFontSize) ?? 13;
      _termCursor = prefs.getString(_kTermCursor) ?? 'block';
      _termBlink = prefs.getBool(_kTermBlink) ?? true;
      _faceId = prefs.getBool(_kFaceId) ?? false;
      _autoLock = prefs.getInt(_kAutoLock) ?? 2;
      _prefsLoaded = true;
    });
  }

  Future<void> _setBoolPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _setStringPref(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _setIntPref(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'settings.nodeCount'.tr(namedArgs: {
                            'n': '${provider.agentsForServer(s.id).length}'
                          }),
                          style: TextStyle(fontSize: 11.5, color: t.fg4),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right_rounded, color: t.fg4),
                      ],
                    ),
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
                    onTap: () => _pickLanguage(context)),
                _toggle(context, 'settings.compactMode'.tr(), _compact, (v) {
                  setState(() => _compact = v);
                  _setBoolPref(_kCompact, v);
                }, divider: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('settings.terminal'.tr(), grouped: true),
          NanoCard(
            child: Column(
              children: [
                _row(context,
                    label: 'settings.termTheme'.tr(),
                    value: _termThemeLabel(_termTheme),
                    onTap: () => _pickTermTheme(context)),
                _row(context,
                    label: 'settings.termFontSize'.tr(),
                    value: 'settings.ptValue'
                        .tr(namedArgs: {'n': '$_termFontSize'}),
                    onTap: () => _pickTermFontSize(context)),
                _row(context,
                    label: 'settings.termCursor'.tr(),
                    value: _termCursorLabel(_termCursor),
                    onTap: () => _pickTermCursor(context)),
                _toggle(context, 'settings.termBlink'.tr(), _termBlink, (v) {
                  setState(() => _termBlink = v);
                  _setBoolPref(_kTermBlink, v);
                }, divider: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('settings.notifications'.tr(), grouped: true),
          NanoCard(
            child: Column(
              children: [
                _toggle(context, 'settings.notifyOffline'.tr(),
                    provider.notifyOffline,
                    (v) => provider.setNotifyPref('notify_offline', v)),
                _toggle(context, 'settings.notifyHigh'.tr(), provider.notifyHigh,
                    (v) => provider.setNotifyPref('notify_high', v)),
                _toggle(context, 'settings.notifyDisk'.tr(), provider.notifyDisk,
                    (v) => provider.setNotifyPref('notify_disk', v)),
                _toggle(context, 'settings.notifyAudit'.tr(), _notifyAudit, (v) {
                  setState(() => _notifyAudit = v);
                  _setBoolPref(_kNotifyAudit, v);
                  if (v) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('settings.notifyAuditNote'.tr()),
                        duration: const Duration(seconds: 2)));
                  }
                }, divider: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NanoSectionLabel('settings.security'.tr(), grouped: true),
          NanoCard(
            child: Column(
              children: [
                _toggle(context, 'settings.faceId'.tr(), _faceId, (v) {
                  setState(() => _faceId = v);
                  _setBoolPref(_kFaceId, v);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('settings.faceIdNote'.tr()),
                      duration: const Duration(seconds: 2)));
                }),
                _row(context,
                    label: 'settings.autoLock'.tr(),
                    value: _autoLockLabel(_autoLock),
                    onTap: () => _pickAutoLock(context)),
                NanoListRow(
                  divider: false,
                  onTap: () => _confirmClearTokens(context, provider),
                  child: Text('settings.clearTokens'.tr(),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: t.crit)),
                ),
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
                    onTap: () {
                      Clipboard.setData(const ClipboardData(text: 'v0.5.0'));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('settings.copied'.tr()),
                          duration: const Duration(seconds: 1)));
                    }),
                _row(context,
                    label: 'settings.sourceCodeLabel'.tr(),
                    value: 'github.com/chenqi92/NanoLink',
                    onTap: () {
                      Clipboard.setData(const ClipboardData(
                          text: 'https://github.com/chenqi92/NanoLink'));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('settings.copied'.tr()),
                          duration: const Duration(seconds: 1)));
                    }),
                _row(context,
                    label: 'settings.docsHelp'.tr(),
                    onTap: () {
                      Clipboard.setData(const ClipboardData(
                          text: 'https://github.com/chenqi92/NanoLink#readme'));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('settings.docsCopied'.tr()),
                          duration: const Duration(seconds: 2)));
                    }),
                _row(context,
                    label: 'settings.sendFeedback'.tr(),
                    onTap: () {
                      Clipboard.setData(const ClipboardData(
                          text: 'mailto:feedback@nanolink.io'));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('settings.feedbackCopied'.tr()),
                          duration: const Duration(seconds: 2)));
                    },
                    divider: false),
              ],
            ),
          ),
          if (loggedIn) ...[
            const SizedBox(height: 16),
            NanoCard(
              child: NanoListRow(
                divider: false,
                onTap: () => _confirmLogout(context, provider),
                child: Center(
                  child: Text('settings.logout'.tr(),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.crit)),
                ),
              ),
            ),
          ],
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

  String _termThemeLabel(String id) => 'settings.termTheme_$id'.tr();

  String _termCursorLabel(String id) => 'settings.termCursor_$id'.tr();

  String _autoLockLabel(int minutes) {
    if (minutes <= 0) return 'settings.autoLockOff'.tr();
    return 'settings.minutesValue'.tr(namedArgs: {'n': '$minutes'});
  }

  void _pickTheme(BuildContext context, ThemeProvider tp) {
    _sheet(
      context,
      title: 'settings.theme'.tr(),
      options: [
        for (final m in AppThemeMode.values)
          _SheetOption(
            label: _themeLabel(m),
            selected: tp.themeMode == m,
            onTap: () => tp.setThemeMode(m),
          ),
      ],
    );
  }

  void _pickLanguage(BuildContext context) {
    _sheet(
      context,
      title: 'settings.language'.tr(),
      options: [
        for (final lang in [
          ['zh', 'settings.langChinese'.tr()],
          ['en', 'settings.langEnglish'.tr()],
        ])
          _SheetOption(
            label: lang[1],
            selected: context.locale.languageCode == lang[0],
            onTap: () => context.setLocale(Locale(lang[0])),
          ),
      ],
    );
  }

  void _pickTermTheme(BuildContext context) {
    _sheet(
      context,
      title: 'settings.termTheme'.tr(),
      options: [
        for (final id in _termThemes)
          _SheetOption(
            label: _termThemeLabel(id),
            selected: _termTheme == id,
            onTap: () {
              setState(() => _termTheme = id);
              _setStringPref(_kTermTheme, id);
            },
          ),
      ],
    );
  }

  void _pickTermFontSize(BuildContext context) {
    _sheet(
      context,
      title: 'settings.termFontSize'.tr(),
      options: [
        for (final size in _termFontSizes)
          _SheetOption(
            label: 'settings.ptValue'.tr(namedArgs: {'n': '$size'}),
            selected: _termFontSize == size,
            onTap: () {
              setState(() => _termFontSize = size);
              _setIntPref(_kTermFontSize, size);
            },
          ),
      ],
    );
  }

  void _pickTermCursor(BuildContext context) {
    _sheet(
      context,
      title: 'settings.termCursor'.tr(),
      options: [
        for (final id in _termCursors)
          _SheetOption(
            label: _termCursorLabel(id),
            selected: _termCursor == id,
            onTap: () {
              setState(() => _termCursor = id);
              _setStringPref(_kTermCursor, id);
            },
          ),
      ],
    );
  }

  void _pickAutoLock(BuildContext context) {
    _sheet(
      context,
      title: 'settings.autoLock'.tr(),
      options: [
        for (final m in _autoLockOptions)
          _SheetOption(
            label: _autoLockLabel(m),
            selected: _autoLock == m,
            onTap: () {
              setState(() => _autoLock = m);
              _setIntPref(_kAutoLock, m);
            },
          ),
      ],
    );
  }

  /// Generic single-select bottom sheet matching the theme/language picker
  /// styling already used on this screen.
  void _sheet(BuildContext context,
      {required String title, required List<_SheetOption> options}) {
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
            for (var i = 0; i < options.length; i++)
              NanoListRow(
                divider: i != options.length - 1,
                trailing: options[i].selected
                    ? Icon(Icons.check_rounded, color: t.accent)
                    : null,
                onTap: () {
                  options[i].onTap();
                  Navigator.pop(ctx);
                },
                child: Text(options[i].label,
                    style: TextStyle(fontSize: 15, color: t.fg)),
              ),
          ],
        ),
      ),
    );
  }

  /// Confirm + execute the destructive "clear all tokens" action: removes every
  /// saved server, which clears their secrets from secure storage.
  Future<void> _confirmClearTokens(
      BuildContext context, AppProvider provider) async {
    final t = context.nano;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('settings.clearTokens'.tr()),
        content: Text('settings.clearTokensConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: t.crit),
            child: Text('settings.clearTokensConfirmAction'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final s in List.of(provider.servers)) {
      await provider.removeServer(s.id);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('settings.clearTokensDone'.tr()),
        duration: const Duration(seconds: 2)));
  }

  /// Confirm + execute logout: removes all servers holding a user token (full
  /// login), which clears their credentials/secrets via removeServer.
  Future<void> _confirmLogout(
      BuildContext context, AppProvider provider) async {
    final t = context.nano;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('settings.logout'.tr()),
        content: Text('settings.logoutConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: t.crit),
            child: Text('settings.logout'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final loggedInServers =
        provider.servers.where((s) => s.hasFullPermissions).toList();
    for (final s in loggedInServers) {
      await provider.removeServer(s.id);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('settings.logoutDone'.tr()),
        duration: const Duration(seconds: 2)));
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
        // Disable until prefs are hydrated so the visible state matches storage.
        onChanged: _prefsLoaded ? onChanged : null,
      ),
      child: Text(label, style: TextStyle(fontSize: 15, color: t.fg)),
    );
  }
}

/// One option in the generic single-select [_sheet].
class _SheetOption {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SheetOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
}
