import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../design/nano_tokens.dart';
import '../providers/app_provider.dart';
import '../widgets/nano/nano_card.dart';

/// How to connect a server. The 6-digit pairing code is intentionally omitted:
/// the backend issues codes but has no redemption endpoint, so only QR (which
/// embeds the full token), account login and manual entry actually work.
enum ConnectionMethod { qrCode, account, manual }

/// Full-screen "add server" flow styled with the NanoLink design tokens.
class AddServerPage extends StatefulWidget {
  const AddServerPage({super.key});

  @override
  State<AddServerPage> createState() => _AddServerPageState();
}

class _AddServerPageState extends State<AddServerPage> {
  ConnectionMethod? _method;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _token = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  MobileScannerController? _scanner;
  bool _hasScanned = false;
  bool _torch = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  bool get _qrSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    _username.dispose();
    _password.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  void _select(ConnectionMethod m) {
    HapticFeedback.selectionClick();
    setState(() {
      _method = m;
      _error = null;
      _hasScanned = false;
    });
    if (m == ConnectionMethod.qrCode && _qrSupported) {
      _scanner = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
      );
    }
  }

  void _back() {
    if (_method != null) {
      _scanner?.dispose();
      _scanner = null;
      setState(() {
        _method = null;
        _error = null;
        _hasScanned = false;
      });
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _processQr(String raw) async {
    if (_hasScanned) return;
    final provider = context.read<AppProvider>();
    setState(() {
      _hasScanned = true;
      _loading = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();
    try {
      String jsonStr;
      try {
        jsonStr = utf8.decode(base64.decode(raw));
      } catch (_) {
        jsonStr = raw;
      }
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final version = json['v'] as int?;
      final serverUrl = json['s'] as String?;
      final token = json['t'] as String?;
      final name = json['n'] as String? ?? 'addServer.defaultServerName'.tr();
      if (version != 1 || serverUrl == null || token == null) {
        throw const FormatException('invalid');
      }
      await _scanner?.stop();
      final ok = await provider.addServer(name: name, url: serverUrl, token: token);
      if (!mounted) return;
      if (ok) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context, true);
      } else {
        setState(() {
          _loading = false;
          _hasScanned = false;
          _error = 'addServer.connectionFailed'.tr();
        });
        _scanner?.start();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasScanned = false;
        _error = 'addServer.qrInvalid'.tr();
      });
      _scanner?.start();
    }
  }

  Future<void> _submitManual() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await context.read<AppProvider>().addServer(
          name: _name.text.trim(),
          url: _url.text.trim(),
          token: _token.text.trim().isEmpty ? null : _token.text.trim(),
        );
    if (!mounted) return;
    if (ok) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context, true);
    } else {
      setState(() {
        _loading = false;
        _error = 'addServer.connectionFailed'.tr();
      });
    }
  }

  Future<void> _submitAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await context.read<AppProvider>().addServerWithCredentials(
          name: _name.text.trim(),
          url: _url.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
        );
    if (!mounted) return;
    if (ok) {
      HapticFeedback.heavyImpact();
      Navigator.pop(context, true);
    } else {
      setState(() {
        _loading = false;
        _error = 'addServer.loginFailed'.tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(t),
            Expanded(
              child: _method == null
                  ? _methodSelection(t)
                  : switch (_method!) {
                      ConnectionMethod.qrCode => _qrScanner(t),
                      ConnectionMethod.account => _accountForm(t),
                      ConnectionMethod.manual => _manualForm(t),
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(NanoTokens t) {
    final title = _method == null
        ? 'addServer.title'.tr()
        : switch (_method!) {
            ConnectionMethod.qrCode => 'addServer.headerScanQr'.tr(),
            ConnectionMethod.account => 'addServer.headerAccount'.tr(),
            ConnectionMethod.manual => 'addServer.headerManual'.tr(),
          };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: _back,
            icon: Icon(_method != null ? Icons.arrow_back_rounded : Icons.close_rounded,
                color: t.fg),
          ),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: t.fg)),
          ),
          if (_method == ConnectionMethod.qrCode && _scanner != null)
            IconButton(
              onPressed: () {
                _scanner?.toggleTorch();
                setState(() => _torch = !_torch);
              },
              icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: _torch ? t.accent : t.fg3),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _methodSelection(NanoTokens t) {
    final methods = <List<dynamic>>[
      if (_qrSupported)
        [
          ConnectionMethod.qrCode,
          Icons.qr_code_scanner_rounded,
          'addServer.methodScanQr'.tr(),
          'addServer.methodScanQrDesc'.tr()
        ],
      [
        ConnectionMethod.account,
        Icons.shield_outlined,
        'addServer.methodAccount'.tr(),
        'addServer.methodAccountDesc'.tr()
      ],
      [
        ConnectionMethod.manual,
        Icons.link_rounded,
        'addServer.methodManual'.tr(),
        'addServer.methodManualDesc'.tr()
      ],
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text('addServer.chooseMethodHint'.tr(),
              style: TextStyle(fontSize: 14, color: t.fg3, height: 1.5)),
        ),
        NanoCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < methods.length; i++)
                NanoListRow(
                  divider: i < methods.length - 1,
                  onTap: () => _select(methods[i][0] as ConnectionMethod),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  leading: NanoIconBox(methods[i][1] as IconData,
                      size: 44, iconSize: 22, fg: t.accent),
                  trailing: Icon(Icons.chevron_right_rounded, color: t.fg4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(methods[i][2] as String,
                          style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                              color: t.fg)),
                      const SizedBox(height: 2),
                      Text(methods[i][3] as String,
                          style: TextStyle(fontSize: 13, color: t.fg3)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _qrScanner(NanoTokens t) {
    if (!_qrSupported || _scanner == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_scanner_rounded, size: 60, color: t.fg4),
              const SizedBox(height: 20),
              Text('addServer.qrUnsupported'.tr(),
                  style: TextStyle(fontSize: 15, color: t.fg2)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _select(ConnectionMethod.manual),
                child: Text('addServer.useManualInstead'.tr(),
                    style: TextStyle(color: t.accent)),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(t.cardRadius),
                  child: MobileScanner(
                    controller: _scanner!,
                    onDetect: (capture) {
                      final raw = capture.barcodes.isNotEmpty
                          ? capture.barcodes.first.rawValue
                          : null;
                      if (raw != null && raw.isNotEmpty) _processQr(raw);
                    },
                  ),
                ),
                SizedBox(
                  width: 260,
                  height: 260,
                  child: CustomPaint(
                    painter: _ScanFramePainter(
                        color: _loading ? t.ok : t.accent),
                    child: _loading
                        ? Center(
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 3),
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            children: [
              if (_error != null) ...[
                _errorBanner(t, _error!),
                const SizedBox(height: 14),
              ],
              Text('addServer.qrHint'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: t.fg3)),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => _select(ConnectionMethod.manual),
                child: Text('addServer.useManualInstead'.tr(),
                    style: TextStyle(color: t.accent)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _manualForm(NanoTokens t) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _field(t,
              controller: _name,
              label: 'addServer.serverName'.tr(),
              hint: 'addServer.serverNameHint'.tr(),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'addServer.nameRequired'.tr()
                  : null),
          _field(t,
              controller: _url,
              label: 'addServer.serverUrl'.tr(),
              hint: 'http://192.168.1.100:39100',
              keyboardType: TextInputType.url,
              validator: _urlValidator),
          _field(t,
              controller: _token,
              label: 'addServer.deviceTokenOptional'.tr(),
              hint: 'addServer.deviceTokenHint'.tr(),
              obscure: true),
          if (_error != null) ...[
            const SizedBox(height: 4),
            _errorBanner(t, _error!),
          ],
          const SizedBox(height: 24),
          _primary(t, 'addServer.connect'.tr(), _submitManual),
        ],
      ),
    );
  }

  Widget _accountForm(NanoTokens t) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.ok.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: t.ok, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('addServer.accountNotice'.tr(),
                      style: TextStyle(fontSize: 13, color: t.fg2)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _field(t,
              controller: _name,
              label: 'addServer.serverName'.tr(),
              hint: 'addServer.serverNameHint'.tr(),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'addServer.nameRequired'.tr()
                  : null),
          _field(t,
              controller: _url,
              label: 'addServer.serverUrl'.tr(),
              hint: 'http://192.168.1.100:39100',
              keyboardType: TextInputType.url,
              validator: _urlValidator),
          _field(t,
              controller: _username,
              label: 'addServer.username'.tr(),
              hint: 'admin',
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'addServer.usernameRequired'.tr()
                  : null),
          _field(t,
              controller: _password,
              label: 'addServer.password'.tr(),
              hint: '••••••••',
              obscure: _obscure,
              suffix: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    color: t.fg4, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              validator: (v) => v == null || v.isEmpty
                  ? 'addServer.passwordRequired'.tr()
                  : null),
          if (_error != null) ...[
            const SizedBox(height: 4),
            _errorBanner(t, _error!),
          ],
          const SizedBox(height: 24),
          _primary(t, 'addServer.login'.tr(), _submitAccount),
        ],
      ),
    );
  }

  String? _urlValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'addServer.urlRequired'.tr();
    final uri = Uri.tryParse(v.trim());
    if (uri == null || !uri.hasScheme) return 'addServer.urlInvalid'.tr();
    return null;
  }

  Widget _field(
    NanoTokens t, {
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: t.fg2)),
          ),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: t.fg, fontSize: 15),
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: t.fg4),
              filled: true,
              fillColor: t.card2,
              isDense: true,
              suffixIcon: suffix,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.fieldRadius),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.fieldRadius),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.fieldRadius),
                borderSide: BorderSide(color: t.accent, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(NanoTokens t, String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.crit.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: t.crit, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: t.crit, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _primary(NanoTokens t, String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.buttonRadius),
          ),
        ),
        child: _loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: t.onAccent),
              )
            : Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  final Color color;
  _ScanFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const c = 28.0;
    final w = size.width, h = size.height;
    // top-left
    canvas.drawPath(
        Path()
          ..moveTo(0, c)
          ..lineTo(0, 0)
          ..lineTo(c, 0),
        paint);
    // top-right
    canvas.drawPath(
        Path()
          ..moveTo(w - c, 0)
          ..lineTo(w, 0)
          ..lineTo(w, c),
        paint);
    // bottom-left
    canvas.drawPath(
        Path()
          ..moveTo(0, h - c)
          ..lineTo(0, h)
          ..lineTo(c, h),
        paint);
    // bottom-right
    canvas.drawPath(
        Path()
          ..moveTo(w - c, h)
          ..lineTo(w, h)
          ..lineTo(w, h - c),
        paint);
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter old) => old.color != color;
}
