import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import 'nano/nano_card.dart';

/// Bottom sheet of quick actions for an agent: open terminal, request fresh
/// data (POST /data-request), copy id, and reboot host (POST /command →
/// SYSTEM_REBOOT). The data/command actions hit the backend directly via the
/// agent's [ServerService].
Future<void> showAgentActionsSheet(
  BuildContext context, {
  required Agent agent,
  VoidCallback? onOpenTerminal,
}) {
  final t = context.nano;
  return showModalBottomSheet(
    context: context,
    backgroundColor: t.card,
    showDragHandle: true,
    shape: RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(t.isIOS ? 16 : 28)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('actions.title'.tr(),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: t.fg)),
              ),
            ),
            if (agent.permissionLevel > 0)
              _ActionRow(
                icon: Icons.terminal_rounded,
                label: 'actions.openTerminal'.tr(),
                sub: 'actions.openTerminalSub'.tr(),
                onTap: () {
                  Navigator.pop(ctx);
                  onOpenTerminal?.call();
                },
              ),
            _ActionRow(
              icon: Icons.refresh_rounded,
              label: 'actions.requestData'.tr(),
              sub: 'actions.requestDataSub'.tr(),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final svc = context.read<AppProvider>().serviceForAgent(agent.id);
                Navigator.pop(ctx);
                if (svc == null) {
                  _show(messenger, 'actions.noServerForNode'.tr());
                  return;
                }
                final err = await svc.requestData(agent.id);
                _show(
                    messenger,
                    err == null
                        ? 'actions.dataRequested'.tr()
                        : 'actions.dataRequestFailed'
                            .tr(namedArgs: {'error': err}));
              },
            ),
            _ActionRow(
              icon: Icons.copy_rounded,
              label: 'actions.copyAgentId'.tr(),
              onTap: () {
                Clipboard.setData(ClipboardData(text: agent.id));
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                _show(messenger, 'actions.agentIdCopied'.tr());
              },
            ),
            if (agent.permissionLevel >= 3)
              _ActionRow(
                icon: Icons.power_settings_new_rounded,
                label: 'actions.reboot'.tr(),
                sub: 'actions.rebootSub'.tr(),
                danger: true,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final provider = context.read<AppProvider>();
                  Navigator.pop(ctx);
                  final ok = await _confirmReboot(context);
                  if (ok != true) return;
                  final svc = provider.serviceForAgent(agent.id);
                  if (svc == null) {
                    _show(messenger, 'actions.noServerForNode'.tr());
                    return;
                  }
                  final err = await svc.sendCommand(agent.id, 'SYSTEM_REBOOT');
                  _show(
                      messenger,
                      err == null
                          ? 'actions.rebootSent'.tr()
                          : 'actions.rebootFailed'
                              .tr(namedArgs: {'error': err}));
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

void _show(ScaffoldMessengerState messenger, String msg) {
  messenger.showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool?> _confirmReboot(BuildContext context) {
  final t = context.nano;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      title: Text('actions.rebootConfirmTitle'.tr(),
          style: TextStyle(color: t.fg)),
      content: Text(
        'actions.rebootConfirmBody'.tr(),
        style: TextStyle(color: t.fg2),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('common.cancel'.tr(), style: TextStyle(color: t.fg2)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child:
              Text('actions.rebootConfirm'.tr(), style: TextStyle(color: t.crit)),
        ),
      ],
    ),
  );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final bool danger;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    this.sub,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final color = danger ? t.crit : t.fg;
    return NanoListRow(
      divider: false,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      leading: Icon(icon, color: danger ? t.crit : t.accent, size: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500, color: color)),
          if (sub != null)
            Text(sub!, style: TextStyle(fontSize: 12, color: t.fg3)),
        ],
      ),
    );
  }
}
