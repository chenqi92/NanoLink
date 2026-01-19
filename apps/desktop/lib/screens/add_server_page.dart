import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

/// Authentication method for server connection
enum ConnectionMethod { qrCode, pairingCode, manual, account }

/// Premium full-screen add server page with Liquid Glass design
/// 
/// Features:
/// - Method selection cards with glassmorphic styling
/// - Animated transitions between steps
/// - QR code scanning integration (mobile)
/// - Pairing code entry with large digits
/// - Account login with smooth validation
class AddServerPage extends StatefulWidget {
  const AddServerPage({super.key});

  @override
  State<AddServerPage> createState() => _AddServerPageState();
}

class _AddServerPageState extends State<AddServerPage>
    with SingleTickerProviderStateMixin {
  ConnectionMethod? _selectedMethod;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pairingCodeController = TextEditingController();

  // QR Scanner
  MobileScannerController? _scannerController;
  bool _hasScanned = false;
  bool _torchEnabled = false;

  bool _isLoading = false;
  String? _error;
  bool _obscurePassword = true;

  /// Check if QR scanning is supported on current platform
  bool get _isQrScanningSupported => 
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pairingCodeController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  void _selectMethod(ConnectionMethod method) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedMethod = method;
      _error = null;
      _hasScanned = false;
    });
    
    // Initialize scanner when QR method is selected
    if (method == ConnectionMethod.qrCode && _isQrScanningSupported) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
    }
    
    _animController.reset();
    _animController.forward();
  }

  void _goBack() {
    if (_selectedMethod != null) {
      _scannerController?.dispose();
      _scannerController = null;
      setState(() {
        _selectedMethod = null;
        _error = null;
        _hasScanned = false;
      });
      _animController.reset();
      _animController.forward();
    } else {
      Navigator.pop(context);
    }
  }

  /// Process scanned QR code data
  Future<void> _processQrData(String rawData) async {
    if (_hasScanned) return; // Prevent multiple scans
    
    setState(() {
      _hasScanned = true;
      _isLoading = true;
      _error = null;
    });

    HapticFeedback.mediumImpact();

    try {
      // Try to decode base64 JSON first (NanoLink format)
      String jsonStr;
      try {
        jsonStr = utf8.decode(base64.decode(rawData));
      } catch (_) {
        // Maybe it's plain JSON
        jsonStr = rawData;
      }

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final version = json['v'] as int?;
      final serverUrl = json['s'] as String?;
      final token = json['t'] as String?;
      final serverName = json['n'] as String? ?? 'NanoLink Server';

      if (version != 1 || serverUrl == null || token == null) {
        throw FormatException('Invalid QR format');
      }

      // Stop the scanner
      _scannerController?.stop();

      // Auto-connect with scanned data
      final provider = context.read<AppProvider>();
      final success = await provider.addServer(
        name: serverName,
        url: serverUrl,
        token: token,
      );

      if (!mounted) return;

      if (success) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context, true);
      } else {
        setState(() {
          _isLoading = false;
          _hasScanned = false;
          _error = 'server.connectionFailed'.tr();
        });
        _scannerController?.start();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasScanned = false;
        _error = 'server.invalidQrCode'.tr();
      });
      _scannerController?.start();
    }
  }

  Future<void> _submitManual() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final provider = context.read<AppProvider>();
    final success = await provider.addServer(
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      token: _tokenController.text.trim().isEmpty
          ? null
          : _tokenController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context, true);
    } else {
      setState(() {
        _isLoading = false;
        _error = 'server.connectionFailed'.tr();
      });
    }
  }

  Future<void> _submitAccount() async {
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
      HapticFeedback.heavyImpact();
      Navigator.pop(context, true);
    } else {
      setState(() {
        _isLoading = false;
        _error = 'server.loginFailed'.tr();
      });
    }
  }

  Future<void> _processPairingCode() async {
    final code = _pairingCodeController.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'server.pairingCodeInvalid'.tr());
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // TODO: Implement pairing code validation against server
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _error = 'server.pairingCodeExpired'.tr();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final isCompact = mediaQuery.size.width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: _goBack,
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _selectedMethod != null ? Icons.arrow_back : Icons.close,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        title: Text(
          _selectedMethod == null
              ? 'server.addServer'.tr()
              : _getMethodTitle(_selectedMethod!),
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          // Torch toggle for QR scanner
          if (_selectedMethod == ConnectionMethod.qrCode && 
              _scannerController != null)
            IconButton(
              onPressed: () {
                _scannerController?.toggleTorch();
                setState(() => _torchEnabled = !_torchEnabled);
              },
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _torchEnabled
                      ? AppTheme.accentCyan.withValues(alpha: 0.3)
                      : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _torchEnabled ? Icons.flash_on : Icons.flash_off,
                  color: _torchEnabled
                      ? AppTheme.accentCyan
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _selectedMethod == null
                ? _buildMethodSelection(theme, isDark, isCompact)
                : _buildMethodForm(theme, isDark),
          ),
        ),
      ),
    );
  }

  String _getMethodTitle(ConnectionMethod method) {
    switch (method) {
      case ConnectionMethod.qrCode:
        return 'server.scanQrCode'.tr();
      case ConnectionMethod.pairingCode:
        return 'server.enterPairingCode'.tr();
      case ConnectionMethod.manual:
        return 'server.manualEntry'.tr();
      case ConnectionMethod.account:
        return 'server.accountLogin'.tr();
    }
  }

  Widget _buildMethodSelection(ThemeData theme, bool isDark, bool isCompact) {
    final methods = <_MethodOption>[
      // Only show QR code option on mobile platforms
      if (_isQrScanningSupported)
        _MethodOption(
          method: ConnectionMethod.qrCode,
          icon: Icons.qr_code_scanner_rounded,
          title: 'server.scanQrCode'.tr(),
          subtitle: 'server.scanQrCodeDesc'.tr(),
          gradient: const LinearGradient(
            colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
          ),
          isPrimary: true,
        ),
      _MethodOption(
        method: ConnectionMethod.pairingCode,
        icon: Icons.pin_rounded,
        title: 'server.enterPairingCode'.tr(),
        subtitle: 'server.pairingCodeDesc'.tr(),
        gradient: const LinearGradient(
          colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
        ),
        isPrimary: !_isQrScanningSupported, // Primary on desktop
      ),
      _MethodOption(
        method: ConnectionMethod.account,
        icon: Icons.person_rounded,
        title: 'server.accountLogin'.tr(),
        subtitle: 'server.accountLoginDesc'.tr(),
        gradient: const LinearGradient(
          colors: [Color(0xFF22C55E), Color(0xFF10B981)],
        ),
      ),
      _MethodOption(
        method: ConnectionMethod.manual,
        icon: Icons.edit_rounded,
        title: 'server.manualEntry'.tr(),
        subtitle: 'server.manualEntryDesc'.tr(),
        gradient: const LinearGradient(
          colors: [Color(0xFF6B7280), Color(0xFF4B5563)],
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header text
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'server.chooseMethod'.tr(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'server.chooseMethodDesc'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),

          // Method cards
          Expanded(
            child: ListView.separated(
              itemCount: methods.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final option = methods[index];
                return _buildMethodCard(option, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard(_MethodOption option, bool isDark) {
    return GestureDetector(
      onTap: () => _selectMethod(option.method),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: option.isPrimary
                  ? option.gradient
                  : LinearGradient(
                      colors: [
                        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                      ],
                    ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: option.isPrimary
                    ? Colors.white.withValues(alpha: 0.3)
                    : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: option.isPrimary
                        ? LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.3),
                              Colors.white.withValues(alpha: 0.1),
                            ],
                          )
                        : option.gradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    option.icon,
                    size: 28,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),

                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: option.isPrimary
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        option.subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: option.isPrimary
                              ? Colors.white70
                              : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),

                // Arrow
                Icon(
                  Icons.chevron_right_rounded,
                  color: option.isPrimary
                      ? Colors.white70
                      : (isDark ? Colors.white38 : Colors.black38),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMethodForm(ThemeData theme, bool isDark) {
    switch (_selectedMethod!) {
      case ConnectionMethod.qrCode:
        return _buildQrCodeScanner(theme, isDark);
      case ConnectionMethod.pairingCode:
        return _buildPairingCodeForm(theme, isDark);
      case ConnectionMethod.manual:
        return _buildManualForm(theme, isDark);
      case ConnectionMethod.account:
        return _buildAccountForm(theme, isDark);
    }
  }

  Widget _buildQrCodeScanner(ThemeData theme, bool isDark) {
    // Fallback for platforms without camera support
    if (!_isQrScanningSupported || _scannerController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.qr_code_scanner_rounded,
              size: 80,
              color: isDark ? Colors.white30 : Colors.black26,
            ),
            const SizedBox(height: 24),
            Text(
              'server.qrNotSupported'.tr(),
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _selectMethod(ConnectionMethod.pairingCode),
              icon: const Icon(Icons.pin_rounded),
              label: Text('server.usePairingCodeInstead'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Scanner area
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Camera preview
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: MobileScanner(
                  controller: _scannerController!,
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final rawValue = barcodes.first.rawValue;
                      if (rawValue != null && rawValue.isNotEmpty) {
                        _processQrData(rawValue);
                      }
                    }
                  },
                ),
              ),

              // Scan frame overlay
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isLoading
                        ? AppTheme.successGreen
                        : AppTheme.primaryBlue.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
                child: Stack(
                  children: [
                    _buildScanFrame(),
                    if (_isLoading)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Bottom section
        Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (_error != null) ...[
                _buildErrorBanner(_error!, isDark),
                const SizedBox(height: 16),
              ],
              Text(
                'server.positionQrCode'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => _selectMethod(ConnectionMethod.pairingCode),
                icon: const Icon(Icons.pin_rounded, size: 18),
                label: Text('server.usePairingCodeInstead'.tr()),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryBlue,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScanFrame() {
    const cornerSize = 30.0;
    const color = AppTheme.accentCyan;

    return Stack(
      children: [
        // Top-left
        Positioned(
          top: 20,
          left: 20,
          child: _buildCorner(color, cornerSize, topLeft: true),
        ),
        // Top-right
        Positioned(
          top: 20,
          right: 20,
          child: _buildCorner(color, cornerSize, topRight: true),
        ),
        // Bottom-left
        Positioned(
          bottom: 20,
          left: 20,
          child: _buildCorner(color, cornerSize, bottomLeft: true),
        ),
        // Bottom-right
        Positioned(
          bottom: 20,
          right: 20,
          child: _buildCorner(color, cornerSize, bottomRight: true),
        ),
      ],
    );
  }

  Widget _buildCorner(
    Color color,
    double size, {
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(
          color: color,
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight,
        ),
      ),
    );
  }

  Widget _buildPairingCodeForm(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          // Large pairing code icon
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.pin_rounded,
              size: 50,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 32),

          Text(
            'server.enterPairingCodeTitle'.tr(),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'server.enterPairingCodeHint'.tr(),
            style: TextStyle(
              color: isDark ? Colors.white60 : Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          // Pairing code input
          _buildGlassTextField(
            controller: _pairingCodeController,
            isDark: isDark,
            hintText: '000-000',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              LengthLimitingTextInputFormatter(7),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            _buildErrorBanner(_error!, isDark),
          ],

          const SizedBox(height: 32),

          _buildPrimaryButton(
            onPressed: _isLoading ? null : _processPairingCode,
            isLoading: _isLoading,
            label: 'server.verifyCode'.tr(),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildManualForm(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGlassTextField(
              controller: _nameController,
              isDark: isDark,
              label: 'server.serverName'.tr(),
              hintText: 'server.serverNameHint'.tr(),
              prefixIcon: Icons.label_outline,
              validator: (v) =>
                  v?.trim().isEmpty == true ? 'server.serverNameRequired'.tr() : null,
            ),
            const SizedBox(height: 16),

            _buildGlassTextField(
              controller: _urlController,
              isDark: isDark,
              label: 'server.serverUrl'.tr(),
              hintText: 'http://192.168.1.100:39100',
              prefixIcon: Icons.link_rounded,
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v?.trim().isEmpty == true) return 'server.serverUrlRequired'.tr();
                final uri = Uri.tryParse(v!.trim());
                if (uri == null || !uri.hasScheme) return 'server.serverUrlInvalid'.tr();
                return null;
              },
            ),
            const SizedBox(height: 16),

            _buildGlassTextField(
              controller: _tokenController,
              isDark: isDark,
              label: 'server.authToken'.tr(),
              hintText: 'server.authTokenHint'.tr(),
              prefixIcon: Icons.key_rounded,
              obscureText: true,
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              _buildErrorBanner(_error!, isDark),
            ],

            const SizedBox(height: 32),

            _buildPrimaryButton(
              onPressed: _isLoading ? null : _submitManual,
              isLoading: _isLoading,
              label: 'common.connect'.tr(),
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountForm(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account info banner
            _buildInfoBanner(
              'server.accountModeHint'.tr(),
              AppTheme.successGreen,
              isDark,
            ),
            const SizedBox(height: 24),

            _buildGlassTextField(
              controller: _nameController,
              isDark: isDark,
              label: 'server.serverName'.tr(),
              hintText: 'server.serverNameHint'.tr(),
              prefixIcon: Icons.label_outline,
              validator: (v) =>
                  v?.trim().isEmpty == true ? 'server.serverNameRequired'.tr() : null,
            ),
            const SizedBox(height: 16),

            _buildGlassTextField(
              controller: _urlController,
              isDark: isDark,
              label: 'server.serverUrl'.tr(),
              hintText: 'http://192.168.1.100:39100',
              prefixIcon: Icons.link_rounded,
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v?.trim().isEmpty == true) return 'server.serverUrlRequired'.tr();
                final uri = Uri.tryParse(v!.trim());
                if (uri == null || !uri.hasScheme) return 'server.serverUrlInvalid'.tr();
                return null;
              },
            ),
            const SizedBox(height: 16),

            _buildGlassTextField(
              controller: _usernameController,
              isDark: isDark,
              label: 'server.username'.tr(),
              hintText: 'admin',
              prefixIcon: Icons.person_outline,
              validator: (v) =>
                  v?.trim().isEmpty == true ? 'server.usernameRequired'.tr() : null,
            ),
            const SizedBox(height: 16),

            _buildGlassTextField(
              controller: _passwordController,
              isDark: isDark,
              label: 'server.password'.tr(),
              hintText: '••••••••',
              prefixIcon: Icons.lock_outline,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) =>
                  v?.isEmpty == true ? 'server.passwordRequired'.tr() : null,
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              _buildErrorBanner(_error!, isDark),
            ],

            const SizedBox(height: 32),

            _buildPrimaryButton(
              onPressed: _isLoading ? null : _submitAccount,
              isLoading: _isLoading,
              label: 'server.login'.tr(),
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required bool isDark,
    String? label,
    String? hintText,
    IconData? prefixIcon,
    Widget? suffixIcon,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextAlign textAlign = TextAlign.start,
    TextStyle? style,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: TextFormField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              textAlign: textAlign,
              style: style ?? TextStyle(
                color: isDark ? Colors.white : Colors.black87,
              ),
              inputFormatters: inputFormatters,
              validator: validator,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
                prefixIcon: prefixIcon != null
                    ? Icon(
                        prefixIcon,
                        color: isDark ? Colors.white38 : Colors.black38,
                        size: 20,
                      )
                    : null,
                suffixIcon: suffixIcon,
                filled: true,
                fillColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppTheme.primaryBlue,
                    width: 2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppTheme.errorRed),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBanner(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.errorRed.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.errorRed, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required String label,
    required bool isDark,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _MethodOption {
  final ConnectionMethod method;
  final IconData icon;
  final String title;
  final String subtitle;
  final LinearGradient gradient;
  final bool isPrimary;

  _MethodOption({
    required this.method,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    this.isPrimary = false,
  });
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;

  _CornerPainter({
    required this.color,
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    
    if (topLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (topRight) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (bottomLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else if (bottomRight) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
