import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import 'nano/nano_card.dart';

/// Bottom sheet of quick actions for an agent (open terminal, request data,
/// copy id, restart). Restart/data-request hit the backend in a later milestone.
Future<void> showAgentActionsSheet(
  BuildContext context, {
  required Agent agent,
  VoidCallback? onOpenTerminal,
  Future<void> Function()? onRequestData,
  Future<void> Function()? onRestart,
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
                child: Text('操作',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: t.fg)),
              ),
            ),
            if (agent.permissionLevel > 0)
              _ActionRow(
                icon: Icons.terminal_rounded,
                label: '打开远程终端',
                sub: '开启 SSH/PTY 通道',
                onTap: () {
                  Navigator.pop(ctx);
                  onOpenTerminal?.call();
                },
              ),
            _ActionRow(
              icon: Icons.refresh_rounded,
              label: '请求最新数据',
              sub: '强制 Agent 立即上报指标',
              onTap: () async {
                Navigator.pop(ctx);
                if (onRequestData != null) {
                  await onRequestData();
                } else {
                  _toast(context, '已请求新数据');
                }
              },
            ),
            _ActionRow(
              icon: Icons.copy_rounded,
              label: '复制 Agent ID',
              onTap: () {
                Clipboard.setData(ClipboardData(text: agent.id));
                Navigator.pop(ctx);
                _toast(context, '已复制 Agent ID');
              },
            ),
            if (agent.permissionLevel >= 3)
              _ActionRow(
                icon: Icons.power_settings_new_rounded,
                label: '重启 Agent 进程',
                sub: '需要 L3 · 危险操作',
                danger: true,
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _confirmRestart(context);
                  if (ok == true) {
                    if (onRestart != null) {
                      await onRestart();
                    } else {
                      _toast(context, '已发送重启命令');
                    }
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool?> _confirmRestart(BuildContext context) {
  final t = context.nano;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.card,
      title: Text('重启 Agent 进程？', style: TextStyle(color: t.fg)),
      content: Text(
        '将断开当前 SSH 会话与远程 Shell，指标采集会暂停约 30 秒。',
        style: TextStyle(color: t.fg2),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('取消', style: TextStyle(color: t.fg2)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('重启', style: TextStyle(color: t.crit)),
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
