import 'dart:async';
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
import '../widgets/nano/nano_primitives.dart';

/// How to connect a server: scan a QR (embeds the full token), redeem a 6-digit
/// pairing code via `/api/auth/pairing`, log in with an account, or enter a
/// server URL and device token manually.
enum ConnectionMethod { qrCode, account, pairing, manual }

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
  final _deviceName = TextEditingController();

  MobileScannerController? _scanner;
  bool _hasScanned = false;
  bool _torch = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  // QR recognized identity, shown briefly before navigating away.
  String? _qrServerName;
  String? _qrServerUrl;

  // Manual "Advanced" section (force TLS / ignore cert errors). Forwarded into
  // ServerConnection via AppProvider.addServer, which scopes them to that
  // connection's ServerService (no process-wide HttpOverrides).
  bool _advancedOpen = false;
  bool _forceTls = true;
  bool _ignoreCert = false;

  // ── Pairing numpad state ────────────────────────────────────────────────
  // The 6-digit code is entered via an on-screen numpad into [_pairingDigits],
  // auto-submitted at length 6. [_pairingState] drives the inline status row.
  String _pairingDigits = '';
  _PairingState _pairingState = _PairingState.input;
  Timer? _countdownTimer;
  int _pairingSeconds = 60;

  bool get _qrSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _token.dispose();
    _username.dispose();
    _password.dispose();
    _deviceName.dispose();
    _countdownTimer?.cancel();
    _scanner?.dispose();
    super.dispose();
  }

  void _select(ConnectionMethod m) {
    HapticFeedback.selectionClick();
    setState(() {
      _method = m;
      _error = null;
      _hasScanned = false;
      _qrServerName = null;
      _qrServerUrl = null;
    });
    if (m == ConnectionMethod.qrCode && _qrSupported) {
      _scanner = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
      );
    }
    if (m == ConnectionMethod.pairing) {
      _resetPairing();
      _startCountdown();
    } else {
      _countdownTimer?.cancel();
    }
  }

  void _back() {
    _countdownTimer?.cancel();
    if (_method != null) {
      _scanner?.dispose();
      _scanner = null;
      setState(() {
        _method = null;
        _error = null;
        _hasScanned = false;
        _qrServerName = null;
        _qrServerUrl = null;
      });
    } else {
      Navigator.pop(context);
    }
  }

  // ── Pairing numpad logic ────────────────────────────────────────────────
  void _resetPairing() {
    _pairingDigits = '';
    _pairingState = _PairingState.input;
    _error = null;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _pairingSeconds = 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_pairingSeconds > 0) _pairingSeconds--;
      });
      if (_pairingSeconds == 0) _countdownTimer?.cancel();
    });
  }

  void _onNumpadTap(String key) {
    if (_pairingState == _PairingState.verifying ||
        _pairingState == _PairingState.success) {
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      if (key == 'del') {
        if (_pairingDigits.isNotEmpty) {
          _pairingDigits =
              _pairingDigits.substring(0, _pairingDigits.length - 1);
        }
      } else if (_pairingDigits.length < 6) {
        _pairingDigits += key;
        _pairingState = _PairingState.input;
      }
    });
    if (_pairingDigits.length == 6) _verifyPairing();
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
      // Surface the recognized identity before we hand off / navigate.
      setState(() {
        _qrServerName = name;
        _qrServerUrl = serverUrl;
      });
      final ok = await provider.addServer(name: name, url: serverUrl, token: token);
      if (!mounted) return;
      if (ok) {
        HapticFeedback.heavyImpact();
        // Let the "✓ name · url" identity row register before navigating.
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        setState(() {
          _loading = false;
          _hasScanned = false;
          _qrServerName = null;
          _qrServerUrl = null;
          _error = 'addServer.connectionFailed'.tr();
        });
        _scanner?.start();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasScanned = false;
        _qrServerName = null;
        _qrServerUrl = null;
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
    // Optional device name overrides the server name we register the token
    // under; falls back to the server name when left blank.
    final deviceName = _deviceName.text.trim();
    final registerName =
        deviceName.isNotEmpty ? deviceName : _name.text.trim();
    // The force-TLS / ignore-cert advanced flags are forwarded into the
    // connection; ServerService scopes them to its own HTTP client (web no-op).
    final ok = await context.read<AppProvider>().addServer(
          name: registerName,
          url: _url.text.trim(),
          token: _token.text.trim().isEmpty ? null : _token.text.trim(),
          forceTls: _forceTls,
          ignoreCert: _ignoreCert,
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

  /// Redeem the 6-digit numpad code. Requires a valid server URL + name first;
  /// drives the inline verifying/invalid/success states.
  Future<void> _verifyPairing() async {
    final url = _url.text.trim();
    final name = _name.text.trim();
    // Both fields are required to redeem; surface a field error if missing.
    if (name.isEmpty || _urlValidator(url) != null) {
      _formKey.currentState?.validate();
      setState(() {
        _pairingState = _PairingState.invalid;
        _error = 'addServer.pairingNeedsServer'.tr();
      });
      return;
    }
    setState(() {
      _pairingState = _PairingState.verifying;
      _error = null;
    });
    HapticFeedback.selectionClick();
    final ok = await context.read<AppProvider>().addServerWithPairingCode(
          name: name,
          url: url,
          pairingCode: _pairingDigits,
        );
    if (!mounted) return;
    if (ok) {
      _countdownTimer?.cancel();
      setState(() => _pairingState = _PairingState.success);
      HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.pop(context, true);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _pairingState = _PairingState.invalid;
        _error = 'addServer.pairingFailed'.tr();
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
                      ConnectionMethod.pairing => _pairingForm(t),
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
            ConnectionMethod.pairing => 'addServer.headerPairing'.tr(),
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
        ConnectionMethod.pairing,
        Icons.pin_rounded,
        'addServer.methodPairing'.tr(),
        'addServer.methodPairingDesc'.tr()
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
              if (_qrServerName != null) ...[
                _qrIdentityRow(t, _qrServerName!, _qrServerUrl ?? ''),
                const SizedBox(height: 14),
              ] else if (_error != null) ...[
                _errorBanner(t, _error!),
                const SizedBox(height: 14),
              ],
              if (_qrServerName == null) ...[
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
            ],
          ),
        ),
      ],
    );
  }

  /// "✓ name · url" recognized-identity row shown right after a QR decode,
  /// while the connection is being saved (android-app.jsx MDAddQR success row).
  Widget _qrIdentityRow(NanoTokens t, String name, String url) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: t.ok.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_rounded, color: t.ok, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  url.isEmpty ? name : '$name · $url',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.ok,
                      fontFamilyFallback: kMonoFallback),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('addServer.qrSaving'.tr(),
              style: TextStyle(fontSize: 12.5, color: t.fg3)),
        ],
      ),
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
          _advancedSection(t),
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

  /// Expandable "Advanced" section: force-TLS / ignore-cert switches + optional
  /// device name (ios-app.jsx IOSAddManual L506-514, android-app.jsx MDAddManual
  /// L401-405). Flags are forwarded into the connection and scoped to its own
  /// ServerService HTTP client (no process-wide override).
  Widget _advancedSection(NanoTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _advancedOpen = !_advancedOpen);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Text('addServer.advanced'.tr(),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: t.accent)),
                const Spacer(),
                Icon(
                    _advancedOpen
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: t.accent,
                    size: 20),
              ],
            ),
          ),
        ),
        if (_advancedOpen) ...[
          const SizedBox(height: 4),
          _field(t,
              controller: _deviceName,
              label: 'addServer.deviceName'.tr(),
              hint: 'addServer.deviceNameHint'.tr()),
          _switchRow(t, 'addServer.forceTls'.tr(), _forceTls,
              (v) => setState(() => _forceTls = v)),
          const SizedBox(height: 8),
          _switchRow(t, 'addServer.ignoreCert'.tr(), _ignoreCert,
              (v) => setState(() => _ignoreCert = v)),
        ],
      ],
    );
  }

  Widget _switchRow(
      NanoTokens t, String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      decoration: BoxDecoration(
        color: t.card2,
        borderRadius: BorderRadius.circular(t.fieldRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 14.5, color: t.fg)),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: t.accent,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => _showInfoSnack('addServer.forgotPasswordHint'.tr()),
                  child: Text('addServer.forgotPassword'.tr(),
                      style: TextStyle(color: t.accent, fontSize: 13.5)),
                ),
                GestureDetector(
                  onTap: () => _showInfoSnack('addServer.ssoHint'.tr()),
                  child: Text('addServer.ssoLogin'.tr(),
                      style: TextStyle(color: t.accent, fontSize: 13.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoSnack(String message) {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _pairingForm(NanoTokens t) {
    final codeColor = switch (_pairingState) {
      _PairingState.invalid => t.crit,
      _PairingState.success => t.ok,
      _ => t.fg,
    };
    final digits = _pairingDigits.padRight(6, '·').split('');
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 18),
                  child: Text('addServer.pairingEnterHint'.tr(),
                      style:
                          TextStyle(fontSize: 13.5, color: t.fg3, height: 1.5)),
                ),
                // 6 digit boxes split 3 · 3.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _digitBox(t, digits[i],
                            active: _pairingDigits.length == i, color: codeColor),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text('·',
                          style: TextStyle(color: t.fg4, fontSize: 26)),
                    ),
                    for (var i = 3; i < 6; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _digitBox(t, digits[i],
                            active: _pairingDigits.length == i, color: codeColor),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _pairingStatusRow(t),
              ],
            ),
          ),
          // Fixed on-screen numpad (android-app.jsx MDNumPad).
          _numPad(t),
        ],
      ),
    );
  }

  /// Inline status row beneath the digit boxes: countdown while inputting,
  /// "verifying…", "invalid", or "✓ paired" (android-app.jsx L323-328).
  Widget _pairingStatusRow(NanoTokens t) {
    switch (_pairingState) {
      case _PairingState.verifying:
        return Center(
          child: Text('addServer.pairingVerifying'.tr(),
              style: TextStyle(fontSize: 13, color: t.accent)),
        );
      case _PairingState.success:
        return Center(
          child: Text('addServer.pairingPaired'.tr(),
              style: TextStyle(
                  fontSize: 13, color: t.ok, fontWeight: FontWeight.w600)),
        );
      case _PairingState.invalid:
        return Center(
          child: Text(_error ?? 'addServer.pairingInvalid'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.crit)),
        );
      case _PairingState.input:
        final m = _pairingSeconds ~/ 60;
        final s = (_pairingSeconds % 60).toString().padLeft(2, '0');
        final low = _pairingSeconds < 10;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$m:$s',
                style: TextStyle(
                    fontSize: 13,
                    color: low ? t.crit : t.fg3,
                    fontFamilyFallback: kMonoFallback)),
            Text(' · ', style: TextStyle(fontSize: 13, color: t.fg4)),
            Text('addServer.pairingValid60s'.tr(),
                style: TextStyle(fontSize: 13, color: t.fg3)),
          ],
        );
    }
  }

  Widget _digitBox(NanoTokens t, String d,
      {required bool active, required Color color}) {
    final empty = d == '·';
    return Container(
      width: 44,
      height: 56,
      decoration: BoxDecoration(
        color: t.card2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? t.accent : t.sep,
          width: active ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        d,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: empty ? t.fg5 : color,
          fontFamilyFallback: kMonoFallback,
        ),
      ),
    );
  }

  Widget _numPad(NanoTokens t) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  for (final k in row)
                    Expanded(
                      child: k.isEmpty
                          ? const SizedBox(height: 60)
                          : Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: _numKey(t, k),
                            ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _numKey(NanoTokens t, String k) {
    return Material(
      color: t.card3,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _onNumpadTap(k),
        child: SizedBox(
          height: 60,
          child: Center(
            child: k == 'del'
                ? Icon(Icons.backspace_outlined, size: 20, color: t.fg)
                : Text(k,
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: t.fg)),
          ),
        ),
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
              // iOS: filled grouped field, no border. Material (.md-input):
              // outlined surface-1 field with a 1px separator + 2px accent focus.
              filled: true,
              fillColor: t.isIOS ? t.card2 : t.bg2,
              isDense: true,
              suffixIcon: suffix,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.fieldRadius),
                borderSide: t.isIOS ? BorderSide.none : BorderSide(color: t.sep),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.fieldRadius),
                borderSide: t.isIOS ? BorderSide.none : BorderSide(color: t.sep),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(t.fieldRadius),
                borderSide: BorderSide(color: t.accent, width: 2),
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
    return NanoButton(
      label,
      onPressed: onPressed,
      fullWidth: true,
      loading: _loading,
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

/// Inline state of the pairing-code numpad entry.
enum _PairingState { input, verifying, success, invalid }
