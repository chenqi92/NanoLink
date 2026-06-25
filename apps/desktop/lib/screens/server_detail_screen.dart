import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/server_service.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';

/// Detail / management for a single saved server connection.
class ServerDetailScreen extends StatefulWidget {
  final String serverId;
  const ServerDetailScreen({super.key, required this.serverId});

  @override
  State<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends State<ServerDetailScreen> {
  String get serverId => widget.serverId;

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        ServerConnection? server;
        for (final s in provider.servers) {
          if (s.id == serverId) server = s;
        }
        if (server == null) {
          return Scaffold(
            backgroundColor: t.bg,
            appBar: AppBar(backgroundColor: t.bg),
            body: Center(
                child: Text('serverDetail.notFound'.tr(),
                    style: TextStyle(color: t.fg3))),
          );
        }
        final s = server;
        final mode = provider.getConnectionMode(s.id);
        final agents = provider.agentsForServer(s.id);
        final isActive = provider.activeServerId == s.id;
        final needsReauth = provider.needsReauth(s.id);

        return Scaffold(
          backgroundColor: t.bg,
          appBar: AppBar(
            backgroundColor: t.bg,
            title: Text(s.name,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: t.fg)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              if (needsReauth) ...[
                _reauthBanner(context, provider, s),
                const SizedBox(height: 16),
              ],
              NanoCard(
                child: Column(
                  children: [
                    NanoListRow(
                      leading: NanoIconBox(Icons.dns_rounded, size: 40),
                      trailing: NanoStatusLabel(
                          status: needsReauth
                              ? 'connecting'
                              : (s.isConnected ? 'online' : 'offline')),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: t.fg)),
                          NanoMono(s.url, size: 12, color: t.fg4),
                        ],
                      ),
                    ),
                    _kv(context, 'serverDetail.connectionMode'.tr(),
                        _modeLabel(mode)),
                    _kv(
                        context,
                        'serverDetail.authType'.tr(),
                        s.hasFullPermissions
                            ? 'serverDetail.authFull'.tr()
                            : 'serverDetail.authReadonly'.tr()),
                    _kv(context, 'serverDetail.nodeCount'.tr(),
                        '${agents.length}'),
                    if (s.username != null && s.username!.isNotEmpty)
                      _kv(context, 'serverDetail.username'.tr(), s.username!),
                    _kv(context, 'serverDetail.lastConnected'.tr(),
                        s.lastConnected != null
                            ? s.lastConnected!.toLocal().toString().split('.').first
                            : '—',
                        divider: false),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              NanoCard(
                child: Column(
                  children: [
                    if (needsReauth)
                      NanoListRow(
                        leading: NanoIconBox(Icons.lock_reset_rounded,
                            size: 36, fg: t.warn),
                        onTap: () => _openReauth(context, provider, s),
                        child: Text('serverDetail.reconnect'.tr(),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: t.warn)),
                      ),
                    NanoListRow(
                      leading: NanoIconBox(Icons.copy_rounded, size: 36,
                          fg: t.accent),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: s.url));
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('serverDetail.urlCopied'.tr())));
                      },
                      child: Text('serverDetail.copyUrl'.tr(),
                          style: TextStyle(fontSize: 15, color: t.fg)),
                    ),
                    if (!isActive)
                      NanoListRow(
                        leading: NanoIconBox(Icons.check_circle_outline_rounded,
                            size: 36, fg: t.accent),
                        onTap: () {
                          provider.setActiveServer(s.id);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('serverDetail.switchedTo'
                                  .tr(namedArgs: {'name': s.name}))));
                        },
                        child: Text('serverDetail.setActive'.tr(),
                            style: TextStyle(fontSize: 15, color: t.fg)),
                      ),
                    NanoListRow(
                      divider: false,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: t.crit.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.delete_outline_rounded,
                            color: t.crit, size: 18),
                      ),
                      onTap: () => _confirmRemove(context, provider, s),
                      child: Text('serverDetail.removeServer'.tr(),
                          style: TextStyle(fontSize: 15, color: t.crit)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Inline warning surfacing the needs-reauth state with a re-login action.
  Widget _reauthBanner(
      BuildContext context, AppProvider provider, ServerConnection s) {
    final t = context.nano;
    return NanoCard(
      color: t.warn.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, color: t.warn, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('serverDetail.reauthTitle'.tr(),
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: t.fg)),
                      const SizedBox(height: 3),
                      Text('serverDetail.reauthBody'.tr(),
                          style: TextStyle(
                              fontSize: 12.5, color: t.fg3, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => _openReauth(context, provider, s),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.warn,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                ),
                child: Text('serverDetail.reconnect'.tr(),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _modeLabel(ConnectionMode m) {
    switch (m) {
      case ConnectionMode.websocket:
        return 'serverDetail.modeWebsocket'.tr();
      case ConnectionMode.httpPolling:
        return 'serverDetail.modeHttp'.tr();
      default:
        return 'serverDetail.modeDisconnected'.tr();
    }
  }

  Widget _kv(BuildContext context, String k, String v, {bool divider = true}) {
    final t = context.nano;
    return NanoListRow(
      divider: divider,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Text(v,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13.5, color: t.fg2)),
      ),
      child: Text(k, style: TextStyle(fontSize: 14, color: t.fg3)),
    );
  }

  /// Open the credential sheet and re-authenticate the server.
  Future<void> _openReauth(
      BuildContext context, AppProvider provider, ServerConnection s) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReauthSheet(provider: provider, server: s),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('serverDetail.reauthSuccess'.tr())));
    }
  }

  Future<void> _confirmRemove(
      BuildContext context, AppProvider provider, ServerConnection s) async {
    final t = context.nano;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        title: Text('serverDetail.removeConfirmTitle'.tr(),
            style: TextStyle(color: t.fg)),
        content: Text(
            'serverDetail.removeConfirmBody'.tr(namedArgs: {'name': s.name}),
            style: TextStyle(color: t.fg2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr(), style: TextStyle(color: t.fg2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('serverDetail.remove'.tr(),
                  style: TextStyle(color: t.crit))),
        ],
      ),
    );
    if (ok == true) {
      await provider.removeServer(s.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

/// Bottom-sheet collecting credentials to re-authenticate a server whose
/// token / credentials were rejected.
class _ReauthSheet extends StatefulWidget {
  final AppProvider provider;
  final ServerConnection server;
  const _ReauthSheet({required this.provider, required this.server});

  @override
  State<_ReauthSheet> createState() => _ReauthSheetState();
}

class _ReauthSheetState extends State<_ReauthSheet> {
  late final TextEditingController _username =
      TextEditingController(text: widget.server.username ?? '');
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = _username.text.trim();
    final pass = _password.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _error = 'serverDetail.reauthMissing'.tr());
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await widget.provider.reauthenticate(
      serverId: widget.server.id,
      username: user,
      password: pass,
    );
    if (!mounted) return;
    if (ok) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context, true);
    } else {
      setState(() {
        _loading = false;
        _error = 'serverDetail.reauthFailed'.tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: t.fg5,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text('serverDetail.reauthSheetTitle'.tr(),
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: t.fg)),
            const SizedBox(height: 4),
            Text('serverDetail.reauthSheetBody'
                .tr(namedArgs: {'name': widget.server.name}),
                style: TextStyle(fontSize: 13, color: t.fg3, height: 1.4)),
            const SizedBox(height: 18),
            _field(t,
                controller: _username,
                label: 'addServer.username'.tr(),
                hint: 'admin'),
            _field(t,
                controller: _password,
                label: 'addServer.password'.tr(),
                hint: '••••••••',
                obscure: _obscure,
                onSubmitted: (_) => _submit(),
                suffix: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                      color: t.fg4, size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.crit.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: t.crit, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(color: t.crit, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: t.onAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.buttonRadius),
                  ),
                ),
                child: _loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: t.onAccent),
                      )
                    : Text('serverDetail.reauthLogin'.tr(),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    NanoTokens t, {
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    Widget? suffix,
    void Function(String)? onSubmitted,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: t.fg2)),
          ),
          TextField(
            controller: controller,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: onSubmitted,
            style: TextStyle(color: t.fg, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: t.fg4),
              filled: true,
              fillColor: t.card2,
              isDense: true,
              suffixIcon: suffix,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.fieldRadius),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.fieldRadius),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.fieldRadius),
                borderSide: BorderSide(color: t.accent, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
