import 'package:flutter/material.dart';
import '../models/models.dart';

/// Chip widget displaying server connection status
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF374151),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: server.isConnected 
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: server.isConnected ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            server.name,
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(width: 4),
          Text(
            '(${_extractHost(server.url)})',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 14, color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host + (uri.port != 80 && uri.port != 443 ? ':${uri.port}' : '');
    } catch (e) {
      return url;
    }
  }
}
