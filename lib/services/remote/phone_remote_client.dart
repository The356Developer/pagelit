import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../session/session_models.dart';

enum RemoteConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Parsed pairing parameters from a PC QR code (`pagelit://remote?...`).
class RemotePairingTarget {
  const RemotePairingTarget({
    required this.host,
    required this.port,
    required this.token,
  });

  final String host;
  final int port;
  final String token;

  static RemotePairingTarget? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    if (uri.scheme == 'pagelit' && uri.host == 'remote') {
      final host = uri.queryParameters['host']?.trim() ?? '';
      final port = int.tryParse(uri.queryParameters['port'] ?? '') ?? 0;
      final token = uri.queryParameters['token']?.trim() ?? '';
      if (host.isNotEmpty && port > 0 && token.isNotEmpty) {
        return RemotePairingTarget(host: host, port: port, token: token);
      }
    }

    return null;
  }
}

/// WebSocket client running on the mobile Pagelit app to control a PC session.
class PhoneRemoteClient {
  PhoneRemoteClient();

  final ValueNotifier<RemoteConnectionStatus> status =
      ValueNotifier(RemoteConnectionStatus.disconnected);
  final ValueNotifier<SessionStateSnapshot?> snapshot = ValueNotifier(null);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);
  final ValueNotifier<RemotePairingTarget?> activeTarget = ValueNotifier(null);

  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;

  Future<bool> connect(RemotePairingTarget target) async {
    if (_disposed) return false;
    await disconnect();

    status.value = RemoteConnectionStatus.connecting;
    errorMessage.value = null;
    activeTarget.value = target;

    final wsUrl =
        'ws://${target.host}:${target.port}/ws?token=${Uri.encodeQueryComponent(target.token)}';

    try {
      final ws = await WebSocket.connect(wsUrl)
          .timeout(const Duration(seconds: 6));
      if (_disposed) {
        await ws.close();
        return false;
      }

      ws.pingInterval = const Duration(seconds: 10);
      _socket = ws;
      status.value = RemoteConnectionStatus.connected;

      _sub = ws.listen(
        (dynamic data) {
          if (data is! String) return;
          try {
            snapshot.value = SessionStateSnapshot.fromJson(data);
          } catch (_) {}
        },
        onDone: () {
          if (!_disposed && _socket == ws) {
            _socket = null;
            status.value = RemoteConnectionStatus.disconnected;
          }
        },
        onError: (Object err) {
          if (!_disposed && _socket == ws) {
            _socket = null;
            errorMessage.value = err.toString();
            status.value = RemoteConnectionStatus.error;
          }
        },
        cancelOnError: true,
      );
      return true;
    } catch (e) {
      if (!_disposed) {
        errorMessage.value = e.toString();
        status.value = RemoteConnectionStatus.error;
      }
      return false;
    }
  }

  void sendCommand(SessionCommand command) {
    final ws = _socket;
    if (ws == null || ws.readyState != WebSocket.open) return;
    try {
      ws.add(command.toJson());
    } catch (_) {}
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    final ws = _socket;
    _socket = null;
    if (ws != null) {
      try {
        await ws.close();
      } catch (_) {}
    }
    if (!_disposed) {
      snapshot.value = null;
      status.value = RemoteConnectionStatus.disconnected;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    status.dispose();
    snapshot.dispose();
    errorMessage.dispose();
    activeTarget.dispose();
  }
}
