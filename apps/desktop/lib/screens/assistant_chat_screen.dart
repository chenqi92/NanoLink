import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/server_service.dart';

/// Conversational AI assistant backed by `POST /api/assistant/chat`.
///
/// Holds the running [ChatMessage] history and posts the whole transcript on
/// every turn via [ServerService.assistantChat]. Failure cases surfaced by
/// [AssistantChatResult] (not-configured 503, upstream 502, bad-request 400,
/// network) are rendered inline as assistant-side error bubbles so the user can
/// read the reason without leaving the thread.
class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({super.key});

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

/// One rendered row in the transcript. Mirrors a [ChatMessage] but adds an
/// [isError] flag so error replies can be styled distinctly from normal
/// assistant turns (and excluded from the history sent upstream).
class _Turn {
  final String role; // user | assistant
  final String content;
  final bool isError;
  const _Turn(this.role, this.content, {this.isError = false});

  bool get isUser => role == 'user';
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  final List<_Turn> _turns = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  ServerService? get _service {
    final provider = context.read<AppProvider>();
    final id = provider.activeServerId;
    return id == null ? null : provider.serviceForServer(id);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;

    final svc = _service;
    setState(() {
      _turns.add(_Turn('user', text));
      _input.clear();
      _sending = true;
    });
    _scrollToEnd();

    if (svc == null) {
      setState(() {
        _turns.add(_Turn('assistant', 'assistant.noServer'.tr(), isError: true));
        _sending = false;
      });
      _scrollToEnd();
      return;
    }

    // History sent upstream excludes inline error bubbles.
    final history = _turns
        .where((t) => !t.isError)
        .map((t) => ChatMessage(role: t.role, content: t.content))
        .toList();

    final result = await svc.assistantChat(history);
    if (!mounted) return;

    setState(() {
      _sending = false;
      if (result.ok) {
        _turns.add(_Turn('assistant', result.reply!.content));
      } else {
        _turns.add(_Turn('assistant', _errorText(result), isError: true));
      }
    });
    _scrollToEnd();
  }

  String _errorText(AssistantChatResult result) {
    switch (result.error) {
      case AssistantChatError.notConfigured:
        return 'assistant.errNotConfigured'.tr();
      case AssistantChatError.upstreamFailed:
        return 'assistant.errUpstream'.tr();
      case AssistantChatError.badRequest:
        return 'assistant.errBadRequest'.tr();
      case AssistantChatError.network:
        return 'assistant.errNetwork'.tr();
      case AssistantChatError.serverError:
      case null:
        return 'assistant.errServer'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [t.accent, t.tertiary]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.forum_rounded,
                  color: Colors.white, size: 15),
            ),
            const SizedBox(width: 10),
            Text('assistant.chatTitle'.tr(),
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: t.fg)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _turns.isEmpty
                  ? _empty(t)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      itemCount: _turns.length + (_sending ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= _turns.length) {
                          return _ThinkingBubble(key: const ValueKey('thinking'));
                        }
                        return _Bubble(turn: _turns[i]);
                      },
                    ),
            ),
            _composer(t),
          ],
        ),
      ),
    );
  }

  Widget _empty(NanoTokens t) {
    final suggestions = <String>[
      'assistant.suggestTopCpu'.tr(),
      'assistant.suggestDiskFull'.tr(),
      'assistant.suggestHealth'.tr(),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [t.accent, t.tertiary]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(height: 16),
        Text('assistant.greeting'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: t.fg)),
        const SizedBox(height: 8),
        Text('assistant.intro'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: t.fg3, height: 1.5)),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.bolt_rounded, size: 15, color: t.fg3),
            const SizedBox(width: 6),
            Text('assistant.tryThese'.tr(),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: t.fg2)),
          ],
        ),
        const SizedBox(height: 10),
        for (final s in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => _send(s),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(t.cardRadius),
                  border: Border.all(color: t.sep2, width: 0.5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(s,
                          style: TextStyle(fontSize: 13.5, color: t.fg2)),
                    ),
                    Icon(Icons.north_east_rounded, size: 15, color: t.fg4),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _composer(NanoTokens t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.sep2, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: t.card2,
                borderRadius: BorderRadius.circular(t.isIOS ? 20 : 22),
                border: Border.all(color: t.sep2, width: 0.5),
              ),
              child: TextField(
                controller: _input,
                focusNode: _focus,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                enabled: !_sending,
                onSubmitted: (_) => _send(),
                style: TextStyle(color: t.fg, fontSize: 15, height: 1.35),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'assistant.inputHint'.tr(),
                  hintStyle: TextStyle(color: t.fg4, fontSize: 15),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(
            sending: _sending,
            onTap: _send,
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool sending;
  final VoidCallback onTap;
  const _SendButton({required this.sending, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return GestureDetector(
      onTap: sending ? null : onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: sending
              ? null
              : LinearGradient(colors: [t.accent, t.tertiary]),
          color: sending ? t.card3 : null,
          shape: BoxShape.circle,
        ),
        child: sending
            ? Padding(
                padding: const EdgeInsets.all(11),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: t.fg4),
              )
            : Icon(Icons.arrow_upward_rounded,
                color: t.onAccent, size: 20),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Turn turn;
  const _Bubble({required this.turn});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final isUser = turn.isUser;
    final radius = t.isIOS ? 18.0 : 16.0;

    final Color bg;
    final Color fg;
    if (isUser) {
      bg = t.accent;
      fg = t.onAccent;
    } else if (turn.isError) {
      bg = t.crit.withValues(alpha: 0.14);
      fg = t.fg;
    } else {
      bg = t.card;
      fg = t.fg;
    }

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
          bottomLeft: Radius.circular(isUser ? radius : 5),
          bottomRight: Radius.circular(isUser ? 5 : radius),
        ),
        border: turn.isError
            ? Border.all(color: t.crit.withValues(alpha: 0.4), width: 0.5)
            : (isUser ? null : Border.all(color: t.sep2, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (turn.isError) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: t.crit),
                const SizedBox(width: 5),
                Text('assistant.errLabel'.tr(),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: t.crit)),
              ],
            ),
            const SizedBox(height: 5),
          ],
          SelectableText(
            turn.content,
            style: TextStyle(fontSize: 14.5, color: fg, height: 1.45),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [bubble],
      ),
    );
  }
}

/// Animated three-dot "thinking" indicator shown while a reply is awaited.
class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble({super.key});

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final radius = t.isIOS ? 18.0 : 16.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(radius),
                topRight: Radius.circular(radius),
                bottomLeft: const Radius.circular(5),
                bottomRight: Radius.circular(radius),
              ),
              border: Border.all(color: t.sep2, width: 0.5),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final phase = (_ctrl.value - i * 0.18) % 1.0;
                    final lift = (phase < 0.5)
                        ? (phase / 0.5)
                        : (1 - (phase - 0.5) / 0.5);
                    return Padding(
                      padding: EdgeInsets.only(right: i < 2 ? 5 : 0),
                      child: Opacity(
                        opacity: 0.35 + 0.55 * lift,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: t.fg3,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
