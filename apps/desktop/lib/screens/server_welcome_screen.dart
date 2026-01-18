import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_server_dialog.dart';

/// First-run screen for adding a server via QR code or manual entry.
class ServerWelcomeScreen extends StatelessWidget {
  const ServerWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width > 600;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.4),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.developer_board,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Title
                    Text(
                      'NanoLink',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'welcome.subtitle'.tr(),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    // Glass Card for options
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.darkCard.withValues(alpha: 0.6)
                                : AppTheme.lightCard.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? AppTheme.darkBorder.withValues(alpha: 0.3)
                                  : AppTheme.lightBorder.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            children: [
                              // QR Code Button (Mobile)
                              if (!isDesktop) ...[
                                _buildOptionButton(
                                  context,
                                  icon: Icons.qr_code_scanner_rounded,
                                  title: 'welcome.scanQr'.tr(),
                                  subtitle: 'welcome.scanQrDesc'.tr(),
                                  onTap: () => _showQrScanner(context),
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 16),
                              ],
                              // Pairing Code Button (Desktop)
                              if (isDesktop) ...[
                                _buildOptionButton(
                                  context,
                                  icon: Icons.pin_rounded,
                                  title: 'welcome.enterCode'.tr(),
                                  subtitle: 'welcome.enterCodeDesc'.tr(),
                                  onTap: () => _showPairingCodeDialog(context),
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 16),
                              ],
                              // Manual Entry Button
                              _buildOptionButton(
                                context,
                                icon: Icons.edit_rounded,
                                title: 'welcome.manualEntry'.tr(),
                                subtitle: 'welcome.manualEntryDesc'.tr(),
                                onTap: () => _showManualEntry(context),
                                isDark: isDark,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.darkSurface.withValues(alpha: 0.5)
                : AppTheme.lightSurface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? AppTheme.darkBorder.withValues(alpha: 0.2)
                  : AppTheme.lightBorder.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primaryBlue, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQrScanner(BuildContext context) {
    // TODO: Integrate mobile_scanner package
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('QR scanner coming soon...'.tr())),
    );
  }

  void _showPairingCodeDialog(BuildContext context) {
    // TODO: Implement pairing code dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pairing code entry coming soon...'.tr())),
    );
  }

  void _showManualEntry(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AddServerDialog(),
    );
  }
}
