import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../design/nano_tokens.dart';
import '../providers/app_provider.dart';
import '../services/server_service.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';

/// Generate a pairing QR + 6-digit code so another device can join a server.
///
/// Requires an account-authenticated connection (the `/devices/token` endpoint
/// needs a JWT; device-token-only connections can't generate codes).
class DevicePairingScreen extends StatefulWidget {
  final String serverId;
  const DevicePairingScreen({super.key, required this.serverId});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  Future<DeviceTokenResult?>? _future;

  /// Client-side fallback TTL, used only when the server's response carries no
  /// real `expiresAt` (mirrors device_service.go `pairingCodeTTL`).
  static const _ttl = Duration(minutes: 15);

  /// Permission level the freshly-generated device token grants, taken from the
  /// /devices/token response's `permissionLevel`. Defaults to read-only (the
  /// server's least-privilege default) until the request resolves.
  int _grantedLevel = 0;

  Timer? _countdown;
  int _remaining = 0; // seconds until the current code expires

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  void _generate() {
    final provider = context.read<AppProvider>();
    final svc = provider.serviceForServer(widget.serverId);
    final name = provider.getServerName(widget.serverId);
    final future =
        svc == null ? Future<DeviceTokenResult?>.value(null) : svc.generateDeviceToken(serverName: name);
    setState(() {
      _future = future;
      _grantedLevel = 0;
    });
    // Start the client-estimated countdown immediately; once the response
    // resolves, re-seed it from the real expiry / permission level.
    _startCountdown();
    future.then((r) {
      if (!mounted || r == null) return;
      setState(() => _grantedLevel = r.permissionLevel);
      if (r.expiresAt != null) _startCountdown(until: r.expiresAt);
    });
  }

  /// (Re)start the expiry countdown. When [until] is supplied the remaining
  /// time is derived from the server's real expiry; otherwise it falls back to
  /// the client-side [_ttl] estimate.
  void _startCountdown({DateTime? until}) {
    _countdown?.cancel();
    _remaining = until != null
        ? until.difference(DateTime.now()).inSeconds.clamp(0, _ttl.inSeconds * 4)
        : _ttl.inSeconds;
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remaining > 0) _remaining--;
      });
      if (_remaining == 0) _countdown?.cancel();
    });
  }

  String _fmtRemaining() {
    final m = _remaining ~/ 60;
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final serverName = context.read<AppProvider>().getServerName(widget.serverId);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.fg),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('pairing.title'.tr(),
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, color: t.fg)),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<DeviceTokenResult?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final r = snap.data;
            if (r == null) {
              return _error(t);
            }
            return _content(t, r, serverName);
          },
        ),
      ),
    );
  }

  Widget _content(NanoTokens t, DeviceTokenResult r, String serverName) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('pairing.intro'.tr(namedArgs: {'name': serverName}),
            style: TextStyle(fontSize: 14, color: t.fg3, height: 1.5)),
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: r.qrData,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0A0A0A),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0A0A0A),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        NanoSectionLabel('pairing.pairingCode'.tr(), grouped: true),
        NanoCard(
          child: NanoListRow(
            divider: false,
            trailing: IconButton(
              icon: Icon(Icons.copy_rounded, color: t.accent, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: r.pairingCode));
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('pairing.codeCopied'.tr())));
              },
            ),
            child: Text(_fmtCode(r.pairingCode),
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    color: t.fg,
                    fontFamilyFallback: kMonoFallback)),
          ),
        ),
        const SizedBox(height: 12),
        _metaRow(t),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.warn.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, color: t.warn, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    'pairing.securityNote'.tr(),
                    style: TextStyle(fontSize: 12.5, color: t.fg2, height: 1.45)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _generate,
            icon: Icon(Icons.refresh_rounded, size: 18, color: t.accent),
            label: Text('pairing.regenerate'.tr(), style: TextStyle(color: t.accent)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: t.sep),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(t.buttonRadius),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Expiry countdown for the 15-minute code TTL + the permission level the
  /// paired device will be granted.
  Widget _metaRow(NanoTokens t) {
    final expired = _remaining == 0;
    final low = _remaining > 0 && _remaining < 60;
    final expColor = expired
        ? t.crit
        : low
            ? t.warn
            : t.fg2;
    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 16, color: expColor),
        const SizedBox(width: 6),
        Text(
          expired
              ? 'pairing.expired'.tr()
              : 'pairing.expiresIn'
                  .tr(namedArgs: {'time': _fmtRemaining()}),
          style: TextStyle(
              fontSize: 13,
              color: expColor,
              fontFamilyFallback: kMonoFallback),
        ),
        const Spacer(),
        Text('pairing.grants'.tr(),
            style: TextStyle(fontSize: 12.5, color: t.fg3)),
        const SizedBox(width: 8),
        NanoPermPill(level: _grantedLevel),
      ],
    );
  }

  Widget _error(NanoTokens t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2_rounded, size: 36, color: t.fg4),
            const SizedBox(height: 12),
            Text('pairing.errorTitle'.tr(),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: t.fg)),
            const SizedBox(height: 6),
            Text('pairing.errorDesc'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: t.fg3, height: 1.45)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _generate,
              icon: Icon(Icons.refresh_rounded, size: 16, color: t.accent),
              label: Text('common.retry'.tr(), style: TextStyle(color: t.accent)),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtCode(String code) {
    if (code.length == 6) return '${code.substring(0, 3)} ${code.substring(3)}';
    return code;
  }
}
