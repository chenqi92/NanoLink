import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/format.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';

/// Full audit log of the active server's recent command activity.
///
/// Wires the real `GET /api/audit/recent` feed through
/// [AppProvider.fetchRecentActivity]; rows mirror the "最近活动" list in the
/// Android drawer/dashboard mockup (typed icon, mono command type, relative
/// time, params, user) but render the complete list with pull-to-refresh.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final provider = context.read<AppProvider>();
    await provider.fetchRecentActivity(limit: 200);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final provider = context.watch<AppProvider>();
    final entries = provider.recentActivity();

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _AuditHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: t.accent,
                backgroundColor: t.card,
                child: _loading && entries.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: CircularProgressIndicator(
                                color: t.accent, strokeWidth: 2.5),
                          ),
                        ],
                      )
                    : entries.isEmpty
                        ? _Empty()
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                            children: [
                              NanoSectionLabel(
                                'audit.entriesCount'.tr(
                                    namedArgs: {'n': '${entries.length}'}),
                              ),
                              NanoCard(
                                child: Column(
                                  children: [
                                    for (var i = 0; i < entries.length; i++)
                                      _AuditRow(
                                        entry: entries[i],
                                        divider: i < entries.length - 1,
                                      ),
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
    );
  }
}

class _AuditHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, t.isIOS ? 12 : 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
                t.isIOS
                    ? Icons.arrow_back_ios_new_rounded
                    : Icons.arrow_back_rounded,
                color: t.isIOS ? t.accent : t.fg,
                size: t.isIOS ? 20 : 24),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text('audit.title'.tr(),
                style: TextStyle(
                    fontSize: t.isIOS ? 22 : 22,
                    fontWeight: t.isIOS ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: t.displayTracking,
                    color: t.fg)),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
      children: [
        Icon(Icons.history_rounded, color: t.fg4, size: 34),
        const SizedBox(height: 12),
        Center(
          child: Text('audit.empty'.tr(),
              style: TextStyle(
                  color: t.fg2, fontSize: 15, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('audit.emptySub'.tr(),
              style: TextStyle(color: t.fg4, fontSize: 12.5)),
        ),
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  final AuditEntry entry;
  final bool divider;
  const _AuditRow({required this.entry, required this.divider});

  IconData get _icon {
    switch (entry.type) {
      case 'shell.exec':
        return Icons.terminal_rounded;
      case 'service.restart':
      case 'docker.restart':
        return Icons.refresh_rounded;
      case 'system.reboot':
        return Icons.power_settings_new_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final tone = entry.ok ? t.ok : t.crit;
    // Prefer the typed params summary; fall back to target / hostname.
    final pm = entry.paramsMap;
    final detail = pm.isNotEmpty
        ? pm.entries.map((e) => '${e.key}=${e.value}').join(' ')
        : (entry.target.isNotEmpty ? entry.target : entry.agentHostname);

    return NanoListRow(
      divider: divider,
      crossAxis: CrossAxisAlignment.start,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(_icon, color: tone, size: 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: NanoMono(entry.type,
                    size: 13,
                    weight: FontWeight.w500,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              Text(Fmt.ago(entry.at),
                  style: TextStyle(fontSize: 11, color: t.fg4)),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 2),
            NanoMono(detail,
                size: 11.5, color: t.fg3, overflow: TextOverflow.ellipsis),
          ],
          if (entry.error.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(entry.error,
                style: TextStyle(fontSize: 11.5, color: t.crit, height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              if (entry.user.isNotEmpty)
                NanoBadge(entry.user, icon: Icons.person_outline_rounded),
              if (entry.user.isNotEmpty && entry.agentHostname.isNotEmpty)
                const SizedBox(width: 6),
              if (entry.agentHostname.isNotEmpty)
                NanoBadge(entry.agentHostname, mono: true),
              const Spacer(),
              if (entry.durationMs > 0)
                Text('${entry.durationMs}ms',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: t.fg4,
                        fontFamilyFallback: kMonoFallback)),
            ],
          ),
        ],
      ),
    );
  }
}
