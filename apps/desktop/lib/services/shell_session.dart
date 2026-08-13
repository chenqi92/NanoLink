import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'ws_channel.dart';

/// Connection state of a remote shell session.
enum ShellStatus { connecting, connected, error, closed }

/// A single rendered line in the terminal console.
enum ShellLineKind { sys, input, output, error }

class ShellLine {
  final ShellLineKind kind;
  final String text;
  const ShellLine(this.kind, this.text);
}

/// A remote shell session over `wss://host/ws/shell/:id`.
///
/// The backend is command-oriented rather than a raw PTY: each `input` message
/// carries a full command line that the agent executes (SHELL_EXECUTE), and the
/// result comes back as one or more `output` messages. `error` messages surface
/// auth / "shell disabled" / dispatch failures. `resize` is advisory.
class ShellSession {
  final Uri uri;
  final String? token;
  final bool ignoreCert;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  ShellStatus _status = ShellStatus.connecting;

  final StreamController<ShellLine> _lines =
      StreamController<ShellLine>.broadcast();
  final StreamController<ShellStatus> _statusCtl =
      StreamController<ShellStatus>.broadcast();

  ShellSession({required this.uri, this.token, this.ignoreCert = false});

  Stream<ShellLine> get lines => _lines.stream;
  Stream<ShellStatus> get statusStream => _statusCtl.stream;
  ShellStatus get status => _status;

  /// Display form of the endpoint with the auth token stripped.
  String get displayUrl {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}';
  }

  Future<void> connect() async {
    _setStatus(ShellStatus.connecting);
    final WebSocketChannel ch;
    try {
      ch = connectAuthedWs(uri,
          token: token,
          pingInterval: const Duration(seconds: 30),
          ignoreCert: ignoreCert);
    } catch (e) {
      _emit(ShellLine(ShellLineKind.error,
          'terminal.connectError'.tr(namedArgs: {'err': e.toString()})));
      _setStatus(ShellStatus.error);
      return;
    }
    _channel = ch;
    _sub = ch.stream.listen(_onData, onError: _onError, onDone: _onDone);

    try {
      await ch.ready;
      _setStatus(ShellStatus.connected);
    } catch (e) {
      // ready failing means the upgrade was rejected (auth/permission) or the
      // host is unreachable; onError/onDone also fire, but surface it here too.
      _emit(ShellLine(ShellLineKind.error, 'terminal.sessionUnavailable'.tr()));
      _setStatus(ShellStatus.error);
    }
  }

  /// Send a full command line to the agent.
  void sendInput(String data) {
    final ch = _channel;
    if (ch == null || _status != ShellStatus.connected) return;
    try {
      ch.sink.add(jsonEncode({'type': 'input', 'data': data}));
    } catch (e) {
      debugPrint('[Shell] send error: $e');
    }
  }

  /// Advise the server of the terminal viewport size.
  void resize(int cols, int rows) {
    final ch = _channel;
    if (ch == null || _status != ShellStatus.connected) return;
    try {
      ch.sink.add(jsonEncode({'type': 'resize', 'cols': cols, 'rows': rows}));
    } catch (_) {}
  }

  void _onData(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      final data = (msg['data'] as String?) ?? '';
      switch (type) {
        case 'output':
          // The backend annotates each output frame with the command's exit
          // status; a non-zero exit (success == false) renders as an error line.
          final success = msg['success'] as bool?;
          if (data.isNotEmpty) {
            _emit(ShellLine(
              success == false ? ShellLineKind.error : ShellLineKind.output,
              data,
            ));
          }
        case 'error':
          _emit(ShellLine(ShellLineKind.error, data));
        default:
          break;
      }
    } catch (e) {
      debugPrint('[Shell] parse error: $e');
    }
  }

  void _onError(Object error) {
    _emit(ShellLine(ShellLineKind.error,
        'terminal.connectError'.tr(namedArgs: {'err': error.toString()})));
    _setStatus(ShellStatus.error);
  }

  void _onDone() {
    if (_status != ShellStatus.error) {
      _emit(ShellLine(ShellLineKind.sys, 'terminal.sessionEnded'.tr()));
      _setStatus(ShellStatus.closed);
    }
  }

  void _emit(ShellLine line) {
    if (!_lines.isClosed) _lines.add(line);
  }

  void _setStatus(ShellStatus s) {
    _status = s;
    if (!_statusCtl.isClosed) _statusCtl.add(s);
  }

  void close() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    if (!_lines.isClosed) _lines.close();
    if (!_statusCtl.isClosed) _statusCtl.close();
  }
}
