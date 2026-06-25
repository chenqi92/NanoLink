import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/server_service.dart';
import 'nano/nano_card.dart';

/// Bottom sheet of quick actions for an agent: open terminal, request fresh
/// data (POST /data-request), copy id, and reboot host (POST /command →
/// SYSTEM_REBOOT). The data/command actions hit the backend directly via the
/// agent's [ServerService] and surface the real execution outcome through a
/// progress → result snackbar (with a dismiss action), instead of fire-and-
/// forget.
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
              onTap: () {
                final messenger = ScaffoldMessenger.of(context);
                final svc = context.read<AppProvider>().serviceForAgent(agent.id);
                Navigator.pop(ctx);
                if (svc == null) {
                  _show(messenger, 'actions.noServerForNode'.tr());
                  return;
                }
                _runRequestData(messenger, svc, agent.id);
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
                  _runReboot(messenger, svc, agent.id);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Plain transient snackbar (copy id / no-server errors).
void _show(ScaffoldMessengerState messenger, String msg) {
  messenger.showSnackBar(SnackBar(content: Text(msg)));
}

/// Persistent progress snackbar with a spinner — shown while a command is
/// dispatched and polled. Returns nothing; replaced by [_showResult] when done.
void _showProgress(ScaffoldMessengerState messenger, String msg) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(minutes: 1),
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(msg)),
        ],
      ),
    ));
}

/// Final result snackbar — carries a dismiss action ('撤销'/close), per the
/// MDSnack design (android-app.jsx L790-794).
void _showResult(ScaffoldMessengerState messenger, String msg) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text(msg),
      action: SnackBarAction(
        label: 'common.dismiss'.tr(),
        onPressed: messenger.hideCurrentSnackBar,
      ),
    ));
}

/// Request fresh data via the data-request endpoint, surfacing the real outcome
/// through a progress → result snackbar.
Future<void> _runRequestData(
  ScaffoldMessengerState messenger,
  ServerService svc,
  String agentId,
) async {
  _showProgress(messenger, 'actions.requestDataPending'.tr());
  final err = await svc.requestData(agentId);
  _showResult(
    messenger,
    err == null
        ? 'actions.dataRequested'.tr()
        : 'actions.dataRequestFailed'.tr(namedArgs: {'error': err}),
  );
}

/// Dispatch SYSTEM_REBOOT and poll its structured result so the snackbar
/// reflects the agent's actual execution (pending → ready / denied / error)
/// rather than just the dispatch ack.
Future<void> _runReboot(
  ScaffoldMessengerState messenger,
  ServerService svc,
  String agentId,
) async {
  _showProgress(messenger, 'actions.rebootPending'.tr());
  final dispatch = await svc.sendCommandReturningId(agentId, 'SYSTEM_REBOOT');
  if (!dispatch.ok) {
    _showResult(
      messenger,
      'actions.rebootFailed'.tr(namedArgs: {'error': dispatch.error ?? ''}),
    );
    return;
  }
  final result = await _pollUntilDone(svc, agentId, dispatch.commandId!);
  switch (result.status) {
    case CommandResultStatus.ready:
      _showResult(messenger, 'actions.rebootDone'.tr());
      break;
    case CommandResultStatus.denied:
      _showResult(messenger, 'actions.commandDenied'.tr());
      break;
    case CommandResultStatus.pending:
      // Reboot disconnects the host before it can report — treat as sent.
      _showResult(messenger, 'actions.rebootSent'.tr());
      break;
    case CommandResultStatus.error:
      _showResult(
        messenger,
        'actions.rebootFailed'.tr(namedArgs: {'error': result.message ?? ''}),
      );
      break;
  }
}

/// Poll a dispatched command's result with a short backoff until it leaves the
/// pending state or the attempt budget is exhausted (returns the last pending
/// result so callers can decide how to render it).
Future<CommandResult> _pollUntilDone(
  ServerService svc,
  String agentId,
  String commandId, {
  int maxAttempts = 6,
  Duration interval = const Duration(seconds: 1),
}) async {
  CommandResult result = const CommandResult(CommandResultStatus.pending);
  for (var i = 0; i < maxAttempts; i++) {
    result = await svc.pollCommandResult(agentId, commandId);
    if (!result.isPending) return result;
    await Future<void>.delayed(interval);
  }
  return result;
}

Future<bool?> _confirmReboot(BuildContext context) {
  final t = context.nano;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.isIOS ? 14 : 28),
      ),
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
        // Filled danger button (bg crit, white text) per MDDialog
        // filled-danger primary action (android-app.jsx L765-787).
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: t.crit,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.isIOS ? 10 : 20),
            ),
          ),
          child: Text('actions.rebootConfirm'.tr()),
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
