import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../design/nano_tokens.dart';
import '../widgets/nano/nano_card.dart';

/// AI operations assistant (MCP). Placeholder shell wired to the design; the
/// chat backend is connected in a later milestone.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text('assistant.title'.tr(),
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: t.fg)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      t.accent.withValues(alpha: 0.18),
                      t.tertiary.withValues(alpha: 0.12),
                    ]),
                    borderRadius: BorderRadius.circular(t.cardRadius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('assistant.greeting'.tr(),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: t.fg)),
                      const SizedBox(height: 6),
                      Text(
                        'assistant.intro'.tr(),
                        style: TextStyle(fontSize: 13, color: t.fg2, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('assistant.tryThese'.tr(),
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: t.fg2)),
                const SizedBox(height: 8),
                for (final s in [
                  'assistant.suggestTopCpu'.tr(),
                  'assistant.suggestDiskFull'.tr(),
                  'assistant.suggestHealth'.tr(),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NanoCard(
                      onTap: () => _controller.text = s,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.bolt_rounded, size: 16, color: t.accent),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(s,
                                    style: TextStyle(fontSize: 14, color: t.fg))),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(color: t.fg),
                      decoration: InputDecoration(
                        hintText: 'assistant.inputHint'.tr(),
                        hintStyle: TextStyle(color: t.fg4),
                        filled: true,
                        fillColor: t.card2,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: t.accent,
                    child: IconButton(
                      icon: Icon(Icons.arrow_upward_rounded, color: t.onAccent),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('assistant.comingSoon'.tr())),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
