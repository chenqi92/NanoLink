import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../providers/app_provider.dart';
import '../screens/add_server_page.dart';
import 'nano/nano_card.dart';
import 'nano/nano_primitives.dart';

/// Bottom sheet to switch the active server (and jump to add-server).
Future<void> showServerSwitchSheet(BuildContext context) {
  final t = context.nano;
  return showModalBottomSheet(
    context: context,
    backgroundColor: t.card,
    showDragHandle: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(t.isIOS ? 16 : 28)),
    ),
    builder: (ctx) {
      final provider = ctx.watch<AppProvider>();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('serverSwitch.title'.tr(),
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600, color: t.fg)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in provider.servers)
                      () {
                        final active = s.id == provider.activeServerId;
                        return NanoListRow(
                          onTap: () {
                            provider.setActiveServer(s.id);
                            Navigator.pop(ctx);
                          },
                          leading: NanoIconBox(
                            Icons.dns_rounded,
                            bg: active
                                ? t.accent.withValues(alpha: 0.16)
                                : t.card2,
                            fg: active ? t.accent : t.fg3,
                          ),
                          // Active row shows a check; non-active rows keep a
                          // live connection status dot (design adds the dot for
                          // at-a-glance reachability).
                          trailing: active
                              ? Icon(Icons.check_rounded,
                                  color: t.accent, size: 20)
                              : NanoStatusDot(
                                  color: s.isConnected ? t.ok : t.crit,
                                  pulse: s.isConnected),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: active ? t.accent : t.fg)),
                              NanoMono(s.url, size: 12, color: t.fg4),
                            ],
                          ),
                        );
                      }(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const AddServerPage()));
                    },
                    icon: Icon(Icons.add_rounded, color: t.accent),
                    label: Text('serverSwitch.addServer'.tr(),
                        style: TextStyle(color: t.accent)),
                    style: TextButton.styleFrom(
                      backgroundColor: t.card2,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(t.fieldRadius)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
