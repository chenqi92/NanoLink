import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Terminal screen for remote shell access to agents.
/// Replaces the AI/MCP tab with practical terminal functionality.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  Agent? _selectedAgent;
  final _commandController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final List<_TerminalLine> _outputLines = [];
  bool _isExecuting = false;

  @override
  void dispose() {
    _commandController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectAgent(Agent agent) {
    setState(() {
      _selectedAgent = agent;
      _outputLines.clear();
      _outputLines.add(_TerminalLine(
        text: 'terminal.connected'.tr(args: [agent.hostname]),
        type: _LineType.system,
      ));
    });
    _focusNode.requestFocus();
  }

  Future<void> _executeCommand() async {
    final command = _commandController.text.trim();
    if (command.isEmpty || _selectedAgent == null || _isExecuting) return;

    setState(() {
      _outputLines.add(_TerminalLine(
        text: '\$ $command',
        type: _LineType.input,
      ));
      _isExecuting = true;
    });
    _commandController.clear();
    _scrollToBottom();

    // TODO: Implement actual command execution via WebSocket/API
    // For now, simulate a response
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;
    setState(() {
      _outputLines.add(_TerminalLine(
        text: 'terminal.notImplemented'.tr(),
        type: _LineType.error,
      ));
      _isExecuting = false;
    });
    _scrollToBottom();
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _insertTab() {
    final text = _commandController.text;
    final selection = _commandController.selection;
    final newText = text.replaceRange(selection.start, selection.end, '\t');
    _commandController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Column(
        children: [
          // Header with agent selector
          _buildHeader(context, theme, isDark),
          // Terminal output
          Expanded(
            child: _selectedAgent == null
                ? _buildAgentSelector(context, isDark)
                : _buildTerminalOutput(context, isDark),
          ),
          // Command input
          if (_selectedAgent != null) _buildCommandInput(context, isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          Icon(Icons.terminal_rounded, color: AppTheme.successGreen),
          const SizedBox(width: 12),
          Text(
            'terminal.title'.tr(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (_selectedAgent != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _selectedAgent = null;
                _outputLines.clear();
              }),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text('terminal.switchAgent'.tr()),
            ),
        ],
      ),
    );
  }

  Widget _buildAgentSelector(BuildContext context, bool isDark) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final onlineAgents = provider.allAgents.where((a) => a.isOnline).toList();

        if (onlineAgents.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 64,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'terminal.noOnlineAgents'.tr(),
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: onlineAgents.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final agent = onlineAgents[index];
            return _buildAgentTile(context, agent, isDark);
          },
        );
      },
    );
  }

  Widget _buildAgentTile(BuildContext context, Agent agent, bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: isDark
              ? AppTheme.darkCard.withValues(alpha: 0.5)
              : AppTheme.lightCard.withValues(alpha: 0.6),
          child: InkWell(
            onTap: () => _selectAgent(agent),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.terminal_rounded, color: AppTheme.successGreen),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          agent.hostname,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                        Text(
                          '${agent.os} • ${agent.arch}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalOutput(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          itemCount: _outputLines.length,
          itemBuilder: (context, index) {
            final line = _outputLines[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                line.text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: line.color,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCommandInput(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkCard.withValues(alpha: 0.8)
            : AppTheme.lightCard.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Prompt indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.successGreen.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '\$',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: AppTheme.successGreen,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Command input
            Expanded(
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.tab) {
                      _insertTab();
                    }
                  }
                },
                child: TextField(
                  controller: _commandController,
                  focusNode: _focusNode,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'terminal.enterCommand'.tr(),
                    hintStyle: TextStyle(
                      fontFamily: 'monospace',
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _executeCommand(),
                  textInputAction: TextInputAction.send,
                ),
              ),
            ),
            // Quick action buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQuickButton('Tab', () => _insertTab(), isDark),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isExecuting ? null : _executeCommand,
                  icon: _isExecuting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.successGreen,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  color: AppTheme.successGreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickButton(String label, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? AppTheme.darkBorder.withValues(alpha: 0.5)
              : AppTheme.lightBorder,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
          ),
        ),
      ),
    );
  }
}

/// Terminal line types for styling
enum _LineType { input, output, error, system }

/// Terminal output line
class _TerminalLine {
  final String text;
  final _LineType type;

  _TerminalLine({required this.text, required this.type});

  Color get color {
    switch (type) {
      case _LineType.input:
        return const Color(0xFF4FC3F7); // Cyan
      case _LineType.output:
        return const Color(0xFFE0E0E0); // White
      case _LineType.error:
        return const Color(0xFFEF5350); // Red
      case _LineType.system:
        return const Color(0xFFFFB74D); // Yellow
    }
  }
}
