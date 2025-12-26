import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Chip widget displaying a server connection status
class ServerChip extends StatelessWidget {
  final ServerConnection server;
  final VoidCallback? onDelete;

  const ServerChip({
    super.key,
    required this.server,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = server.isConnected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected 
              ? AppTheme.successGreen.withValues(alpha: 0.5)
              : (theme.dividerTheme.color ?? Colors.grey),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Connection status indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? AppTheme.successGreen : AppTheme.errorRed,
              boxShadow: isConnected
                  ? [
                      BoxShadow(
                        color: AppTheme.successGreen.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          
          // Server name
          Text(
            server.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          
          // Delete button
          if (onDelete != null)
            IconButton(
              icon: Icon(
                Icons.close,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              padding: EdgeInsets.zero,
              onPressed: onDelete,
              tooltip: 'server.removeServer'.tr(),
            ),
        ],
      ),
    );
  }
}
