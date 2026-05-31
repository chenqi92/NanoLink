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
class ServerDetailScreen extends StatelessWidget {
  final String serverId;
  const ServerDetailScreen({super.key, required this.serverId});

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
              NanoCard(
                child: Column(
                  children: [
                    NanoListRow(
                      leading: NanoIconBox(Icons.dns_rounded, size: 40),
                      trailing: NanoStatusLabel(
                          status: s.isConnected ? 'online' : 'offline'),
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
