import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

/// Authentication mode for server connection
enum AuthMode { deviceToken, userCredential }

/// Dialog for adding a new server connection
/// Supports three methods:
/// 1. QR Code scanning (mobile only)
/// 2. Pairing code entry (desktop)
/// 3. Username/password login
class AddServerDialog extends StatefulWidget {
  /// Initial auth mode to show
  final AuthMode initialMode;

  const AddServerDialog({
    super.key,
    this.initialMode = AuthMode.deviceToken,
  });

  @override
  State<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<AddServerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // Token auth fields
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();

  // User credential fields
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialMode == AuthMode.deviceToken ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Submit with device token
  Future<void> _submitWithToken() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final provider = context.read<AppProvider>();
    final success = await provider.addServer(
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      token:
          _tokenController.text.trim().isEmpty
              ? null
              : _tokenController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _isLoading = false;
        _error = 'server.connectionFailed'.tr();
      });
    }
  }

  /// Submit with username/password
  Future<void> _submitWithCredentials() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final provider = context.read<AppProvider>();
    final success = await provider.addServerWithCredentials(
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _isLoading = false;
        _error = 'server.loginFailed'.tr();
      });
    }
  }

  /// Parse QR code data and connect
  Future<void> processQrData(String qrData) async {
    try {
      final decoded = utf8.decode(base64.decode(qrData));
      final json = jsonDecode(decoded) as Map<String, dynamic>;

      final version = json['v'] as int?;
      final serverUrl = json['s'] as String?;
      final token = json['t'] as String?;
      final serverName = json['n'] as String?;

      if (version != 1 || serverUrl == null || token == null) {
        setState(() => _error = 'server.invalidQrCode'.tr());
        return;
      }

      setState(() {
        _nameController.text = serverName ?? 'NanoLink Server';
        _urlController.text = serverUrl;
        _tokenController.text = token;
        _isLoading = true;
        _error = null;
      });

      // Automatically submit
      await _submitWithToken();
    } catch (e) {
      setState(() => _error = 'server.invalidQrCode'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.dns, color: AppTheme.primaryBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Text('server.addServer'.tr()),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tab bar
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  text: 'server.deviceToken'.tr(),
                ),
                Tab(
                  icon: const Icon(Icons.person, size: 18),
                  text: 'server.accountLogin'.tr(),
                ),
              ],
              labelColor: AppTheme.primaryBlue,
              unselectedLabelColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.6,
              ),
              indicatorColor: AppTheme.primaryBlue,
            ),
            const SizedBox(height: 16),

            // Tab content
            SizedBox(
              height: 320,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTokenForm(theme),
                  _buildCredentialForm(theme),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        ElevatedButton(
          onPressed:
              _isLoading
                  ? null
                  : () {
                    if (_tabController.index == 0) {
                      _submitWithToken();
                    } else {
                      _submitWithCredentials();
                    }
                  },
          child:
              _isLoading
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                  : Text('common.connect'.tr()),
        ),
      ],
    );
  }

  /// Token-based authentication form
  Widget _buildTokenForm(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.infoCyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.infoCyan, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'server.tokenModeHint'.tr(),
                        style: TextStyle(color: AppTheme.infoCyan, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Name field
              _buildLabel('server.serverName'.tr(), theme),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'server.serverNameHint'.tr(),
                  prefixIcon: const Icon(Icons.label_outline, size: 20),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'server.serverNameRequired'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // URL field
              _buildLabel('server.serverUrl'.tr(), theme),
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  hintText: 'server.serverUrlHint'.tr(),
                  prefixIcon: const Icon(Icons.link, size: 20),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'server.serverUrlRequired'.tr();
                  }
                  final uri = Uri.tryParse(value.trim());
                  if (uri == null || !uri.hasScheme) {
                    return 'server.serverUrlInvalid'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Token field
              _buildLabel('server.authToken'.tr(), theme),
              TextFormField(
                controller: _tokenController,
                decoration: InputDecoration(
                  hintText: 'server.authTokenHint'.tr(),
                  prefixIcon: const Icon(Icons.key_outlined, size: 20),
                ),
                obscureText: true,
              ),

              _buildError(),
            ],
          ),
        ),
      ),
    );
  }

  /// Username/password authentication form
  Widget _buildCredentialForm(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user,
                      color: AppTheme.successGreen,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'server.accountModeHint'.tr(),
                        style: TextStyle(
                          color: AppTheme.successGreen,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Name field
              _buildLabel('server.serverName'.tr(), theme),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'server.serverNameHint'.tr(),
                  prefixIcon: const Icon(Icons.label_outline, size: 20),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'server.serverNameRequired'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // URL field
              _buildLabel('server.serverUrl'.tr(), theme),
              TextFormField(
                controller: _urlController,
                decoration: InputDecoration(
                  hintText: 'server.serverUrlHint'.tr(),
                  prefixIcon: const Icon(Icons.link, size: 20),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'server.serverUrlRequired'.tr();
                  }
                  final uri = Uri.tryParse(value.trim());
                  if (uri == null || !uri.hasScheme) {
                    return 'server.serverUrlInvalid'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Username field
              _buildLabel('server.username'.tr(), theme),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  hintText: 'server.usernameHint'.tr(),
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'server.usernameRequired'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Password field
              _buildLabel('server.password'.tr(), theme),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  hintText: 'server.passwordHint'.tr(),
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 20,
                    ),
                    onPressed:
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  ),
                ),
                obscureText: _obscurePassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'server.passwordRequired'.tr();
                  }
                  return null;
                },
              ),

              _buildError(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildError() {
    if (_error == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.errorRed.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: AppTheme.errorRed, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(color: AppTheme.errorRed, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
