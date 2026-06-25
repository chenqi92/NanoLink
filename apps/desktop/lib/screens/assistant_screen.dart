import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../providers/app_provider.dart';
import '../services/server_service.dart';
import '../widgets/nano/nano_card.dart';
import 'agent_detail_screen.dart';
import 'assistant_chat_screen.dart';

/// AI operations assistant: metric-derived auto-diagnosis findings from
/// `/assistant/findings`. The backend produces findings (not a conversational
/// LLM), so this screen surfaces them as an actionable feed.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  Future<List<AssistantFinding>?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final provider = context.read<AppProvider>();
    final id = provider.activeServerId;
    final svc = id == null ? null : provider.serviceForServer(id);
    setState(() {
      _future = svc == null
          ? Future.value(null)
          : svc.fetchAssistantFindings();
    });
  }

  void _openChat() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const AssistantChatScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [t.accent, t.tertiary]),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text('assistant.title'.tr(),
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: t.fg)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'assistant.chatTitle'.tr(),
            icon: Icon(Icons.forum_outlined, color: t.accent),
            onPressed: _openChat,
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: t.accent),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<AssistantFinding>?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final findings = snap.data;
            if (findings == null) {
              return _error(t);
            }
            return RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _intro(t, findings),
                  const SizedBox(height: 14),
                  for (final f in findings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FindingCard(finding: f),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _intro(NanoTokens t, List<AssistantFinding> findings) {
    final actionable =
        findings.where((f) => f.kind != 'ok').length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          t.accent.withValues(alpha: 0.16),
          t.tertiary.withValues(alpha: 0.10),
        ]),
        borderRadius: BorderRadius.circular(t.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 16, color: t.fg),
              const SizedBox(width: 8),
              Text('assistant.autoDiagnosis'.tr(),
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: t.fg)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            actionable == 0
                ? 'assistant.allHealthy'.tr()
                : 'assistant.findingsCount'.tr(namedArgs: {'n': '$actionable'}),
            style: TextStyle(fontSize: 13, color: t.fg2, height: 1.5),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _openChat,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [t.accent, t.tertiary]),
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forum_rounded, size: 16, color: t.onAccent),
                  const SizedBox(width: 8),
                  Text('assistant.askAssistant'.tr(),
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: t.onAccent)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _error(NanoTokens t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 34, color: t.fg4),
            const SizedBox(height: 12),
            Text('assistant.loadError'.tr(),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: t.fg)),
            const SizedBox(height: 6),
            Text('assistant.loadErrorDesc'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: t.fg3, height: 1.45)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _load,
              icon: Icon(Icons.refresh_rounded, size: 16, color: t.accent),
              label: Text('common.retry'.tr(), style: TextStyle(color: t.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FindingCard extends StatelessWidget {
  final AssistantFinding finding;
  const _FindingCard({required this.finding});

  ({Color color, IconData icon}) _tone(NanoTokens t) {
    switch (finding.kind) {
      case 'anomaly':
        return (color: t.crit, icon: Icons.bolt_rounded);
      case 'warn':
        return (color: t.warn, icon: Icons.warning_amber_rounded);
      case 'ok':
        return (color: t.ok, icon: Icons.check_circle_rounded);
      default:
        return (color: t.info, icon: Icons.info_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final tone = _tone(t);
    final provider = context.read<AppProvider>();
    final agent =
        finding.agentId == null ? null : provider.agentById(finding.agentId!);

    return NanoCard(
      padding: const EdgeInsets.all(14),
      onTap: agent == null
          ? null
          : () => _open(context, agent, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(tone.icon, size: 18, color: tone.color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(finding.title,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: t.fg,
                            height: 1.3)),
                    const SizedBox(height: 4),
                    Text(finding.detail,
                        style:
                            TextStyle(fontSize: 12.5, color: t.fg3, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
          if (finding.actions.isNotEmpty && agent != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in finding.actions)
                  _chip(context, t, a, agent),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, NanoTokens t, String action, agent) {
    return GestureDetector(
      onTap: () => _open(context, agent, _tabFor(action)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: t.card2,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: t.sep2, width: 0.5),
        ),
        child: Text(_label(action),
            style: TextStyle(
                fontSize: 12.5, color: t.fg2, fontWeight: FontWeight.w500)),
      ),
    );
  }

  void _open(BuildContext context, agent, int tab) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AgentDetailScreen(agent: agent, initialTab: tab),
    ));
  }

  int _tabFor(String action) {
    final a = action.toLowerCase();
    if (a.contains('history')) return 1;
    if (a.contains('shell') || a.contains('terminal')) return 2;
    return 0;
  }

  String _label(String action) {
    final a = action.toLowerCase();
    if (a.contains('history')) return 'assistant.actHistory'.tr();
    if (a.contains('shell') || a.contains('terminal')) {
      return 'assistant.actShell'.tr();
    }
    if (a.contains('process')) return 'assistant.actProcesses'.tr();
    return action;
  }
}
