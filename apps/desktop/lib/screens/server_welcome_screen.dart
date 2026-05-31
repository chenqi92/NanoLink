import 'package:flutter/material.dart';
import '../design/nano_tokens.dart';
import '../widgets/nano/nano_card.dart';
import 'add_server_page.dart';

/// First-run screen: brand intro + feature highlights + "add server" CTA.
class ServerWelcomeScreen extends StatelessWidget {
  const ServerWelcomeScreen({super.key});

  static const _features = [
    [Icons.dashboard_rounded, '实时指标 + 历史图表', 'CPU、内存、磁盘、网络、GPU、NPU'],
    [Icons.terminal_rounded, '权限分级的远程终端', 'L0 只读 → L3 系统管理'],
    [Icons.notifications_active_rounded, '告警 · 审计 · 设备配对', '所有命令可追溯'],
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient:
                                LinearGradient(colors: [t.accent, t.tertiary]),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.hub_rounded,
                              color: Colors.white, size: 34),
                        ),
                        const SizedBox(height: 26),
                        Text('NanoLink',
                            style: TextStyle(
                                fontSize: 36,
                                fontWeight: t.displayWeight,
                                letterSpacing: t.displayTracking,
                                height: 1.1,
                                color: t.fg)),
                        const SizedBox(height: 10),
                        Text('为运维而生的服务器监控与远程管理。',
                            style: TextStyle(
                                fontSize: 15.5, color: t.fg3, height: 1.5)),
                        const SizedBox(height: 28),
                        for (final f in _features)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: NanoCard(
                              outlined: true,
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  NanoIconBox(f[0] as IconData,
                                      size: 40, iconSize: 20, fg: t.accent),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(f[1] as String,
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: t.fg)),
                                        const SizedBox(height: 2),
                                        Text(f[2] as String,
                                            style: TextStyle(
                                                fontSize: 13, color: t.fg3)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddServerPage()),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 22),
                      label: const Text('添加服务器',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: t.onAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(t.buttonRadius),
                        ),
                      ),
                    ),
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
