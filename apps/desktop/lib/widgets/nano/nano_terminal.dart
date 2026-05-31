import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../design/nano_tokens.dart';
import '../../models/models.dart';
import '../../providers/app_provider.dart';
import '../../services/shell_session.dart';
import 'nano_primitives.dart';

/// Live remote-shell console for an agent, backed by `/ws/shell/:id`.
///
/// Renders the connection status, a scrolling output area, a command input and
/// a horizontally-scrolling key row (esc / tab / ^C / arrows / common chars).
/// The backend executes one full command per line and streams the result back.
class NanoTerminalView extends StatefulWidget {
  final Agent agent;
  const NanoTerminalView({super.key, required this.agent});

  @override
  State<NanoTerminalView> createState() => _NanoTerminalViewState();
}

// Console palette (fixed dark scheme regardless of app theme — a terminal).
const _termBg = Color(0xFF060A04);
const _termPrompt = Color(0xFF4ADE80);
const _termOut = Color(0xFF86EFAC);
const _termInput = Color(0xFFE5E5E5);
const _termSys = Color(0x7386EFAC);
const _termErr = Color(0xFFF87171);

class _NanoTerminalViewState extends State<NanoTerminalView> {
  ShellSession? _session;
  final List<ShellLine> _lines = [];
  ShellStatus _status = ShellStatus.connecting;

  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  final List<String> _history = [];
  int _historyIndex = -1; // -1 = editing fresh line

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    final provider = context.read<AppProvider>();
    final service = provider.serviceForAgent(widget.agent.id);
    if (service == null) {
      setState(() {
        _status = ShellStatus.error;
        _lines.add(ShellLine(
            ShellLineKind.error, 'terminal.consoleNoServer'.tr()));
      });
      return;
    }
    final session = service.openShell(widget.agent.id);
    _session = session;
    _lines.add(ShellLine(ShellLineKind.sys,
        'terminal.consoleConnecting'.tr(namedArgs: {'url': session.displayUrl})));

    session.lines.listen((line) {
      if (!mounted) return;
      setState(() => _lines.add(line));
      _scrollToBottom();
    });
    session.statusStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _status = s;
        if (s == ShellStatus.connected) {
          _lines.add(ShellLine(
              ShellLineKind.sys,
              'terminal.consoleAuthenticated'.tr(
                  namedArgs: {'level': '${widget.agent.permissionLevel}'})));
        }
      });
      _scrollToBottom();
    });
    session.connect();
  }

  @override
  void dispose() {
    _session?.close();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final cmd = _input.text.trim();
    if (cmd.isEmpty) return;
    if (_status != ShellStatus.connected) return;

    if (cmd == 'clear' || cmd == 'cls') {
      setState(() {
        _lines.clear();
        _input.clear();
        _historyIndex = -1;
      });
      return;
    }

    setState(() {
      _lines.add(ShellLine(ShellLineKind.input, cmd));
      _history.add(cmd);
      _historyIndex = -1;
    });
    _session?.sendInput(cmd);
    _input.clear();
    _scrollToBottom();
    _focus.requestFocus();
  }

  void _reconnect() {
    _session?.close();
    setState(() {
      _lines.clear();
      _status = ShellStatus.connecting;
    });
    _start();
  }

  // ── key-row actions ─────────────────────────────────────────────────────
  void _insert(String s) {
    final sel = _input.selection;
    final base = sel.isValid ? sel.start : _input.text.length;
    final end = sel.isValid ? sel.end : _input.text.length;
    final text = _input.text.replaceRange(base, end, s);
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: base + s.length),
    );
    _focus.requestFocus();
  }

  void _moveCursor(int delta) {
    final sel = _input.selection;
    final pos = (sel.isValid ? sel.baseOffset : _input.text.length) + delta;
    final clamped = pos.clamp(0, _input.text.length);
    _input.selection = TextSelection.collapsed(offset: clamped);
    _focus.requestFocus();
  }

  void _historyPrev() {
    if (_history.isEmpty) return;
    final next = _historyIndex == -1 ? _history.length - 1 : _historyIndex - 1;
    if (next < 0) return;
    setState(() => _historyIndex = next);
    _setLine(_history[next]);
  }

  void _historyNext() {
    if (_historyIndex == -1) return;
    final next = _historyIndex + 1;
    if (next >= _history.length) {
      setState(() => _historyIndex = -1);
      _setLine('');
      return;
    }
    setState(() => _historyIndex = next);
    _setLine(_history[next]);
  }

  void _setLine(String text) {
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  void _onKey(String key) {
    switch (key) {
      case 'esc':
        _setLine('');
      case 'tab':
        _insert('\t');
      case '^C':
        _session?.sendInput('');
        _setLine('');
      case '↑':
        _historyPrev();
      case '↓':
        _historyNext();
      case '←':
        _moveCursor(-1);
      case '→':
        _moveCursor(1);
      default:
        _insert(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    if (widget.agent.permissionLevel == 0) {
      return _locked(t);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        children: [
          _statusBar(t),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _termBg,
                borderRadius: BorderRadius.circular(t.cardRadius),
                border: Border.all(color: t.sep2, width: 0.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(child: _console()),
                  _inputRow(t),
                  _keyRow(),
                ],
              ),
            ),
          ),
          SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 8),
        ],
      ),
    );
  }

  Widget _statusBar(NanoTokens t) {
    late Color dot;
    late String label;
    switch (_status) {
      case ShellStatus.connected:
        dot = t.ok;
        label = 'status.connected'.tr();
      case ShellStatus.connecting:
        dot = t.warn;
        label = 'status.connecting'.tr();
      case ShellStatus.error:
        dot = t.crit;
        label = 'status.error'.tr();
      case ShellStatus.closed:
        dot = t.fg4;
        label = 'status.closed'.tr();
    }
    final url = _session?.displayUrl ?? '/ws/shell';
    return Row(
      children: [
        NanoStatusDot(color: dot, pulse: _status == ShellStatus.connected),
        const SizedBox(width: 8),
        Expanded(
          child: NanoMono(url, size: 11.5, color: t.fg3,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        if (_status == ShellStatus.error || _status == ShellStatus.closed)
          GestureDetector(
            onTap: _reconnect,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Icon(Icons.refresh_rounded, size: 14, color: t.accent),
                  const SizedBox(width: 3),
                  Text('status.reconnect'.tr(),
                      style: TextStyle(
                          fontSize: 12,
                          color: t.accent,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        NanoBadge(label,
            color: _status == ShellStatus.connected
                ? t.ok
                : _status == ShellStatus.connecting
                    ? t.warn
                    : t.crit),
      ],
    );
  }

  Widget _console() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      itemCount: _lines.length,
      itemBuilder: (context, i) {
        final l = _lines[i];
        switch (l.kind) {
          case ShellLineKind.sys:
            return _line(l.text,
                color: _termSys, italic: true);
          case ShellLineKind.input:
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontFamilyFallback: kMonoFallback,
                      fontSize: 12.5,
                      height: 1.5),
                  children: [
                    const TextSpan(
                        text: '\$ ',
                        style: TextStyle(color: _termPrompt)),
                    TextSpan(
                        text: l.text,
                        style: const TextStyle(color: _termInput)),
                  ],
                ),
              ),
            );
          case ShellLineKind.output:
            return _line(l.text, color: _termOut);
          case ShellLineKind.error:
            return _line(l.text, color: _termErr);
        }
      },
    );
  }

  Widget _line(String text, {required Color color, bool italic = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamilyFallback: kMonoFallback,
          fontSize: 12.5,
          height: 1.5,
          color: color,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }

  Widget _inputRow(NanoTokens t) {
    final enabled = _status == ShellStatus.connected;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: const BoxDecoration(
        color: Color(0x4D000000),
        border: Border(top: BorderSide(color: Color(0x14FFFFFF), width: 0.5)),
      ),
      child: Row(
        children: [
          const Text('\$',
              style: TextStyle(
                  color: Color(0xFFA3A3A3),
                  fontFamilyFallback: kMonoFallback,
                  fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              enabled: enabled,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(
                  color: _termInput,
                  fontFamilyFallback: kMonoFallback,
                  fontSize: 13),
              cursorColor: _termOut,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: enabled
                    ? 'terminal.inputHint'.tr()
                    : 'terminal.inputHintWaiting'.tr(),
                hintStyle: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontFamilyFallback: kMonoFallback,
                    fontSize: 13),
              ),
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: enabled ? _send : null,
            icon: Icon(Icons.send_rounded,
                size: 18, color: enabled ? _termOut : const Color(0xFF4B5563)),
          ),
        ],
      ),
    );
  }

  Widget _keyRow() {
    const keys = ['esc', 'tab', '^C', '↑', '↓', '←', '→', '/', '|', '-', '~'];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: const BoxDecoration(
        color: Color(0x59000000),
        border: Border(top: BorderSide(color: Color(0x0FFFFFFF), width: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final k in keys)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: GestureDetector(
                  onTap: () => _onKey(k),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 32),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x14FFFFFF),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    alignment: Alignment.center,
                    child: Text(k,
                        style: const TextStyle(
                            color: Color(0xFFD4D4D4),
                            fontFamilyFallback: kMonoFallback,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _locked(NanoTokens t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 32, color: t.fg4),
            const SizedBox(height: 10),
            Text('terminal.lockedTitle'.tr(),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: t.fg)),
            const SizedBox(height: 6),
            Text('terminal.lockedDesc'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: t.fg3, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
