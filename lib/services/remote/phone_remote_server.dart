import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../session/session_input_source.dart';
import '../session/session_models.dart';

/// Connection details displayed as a QR code and manual fallback on the PC.
class PhoneRemoteServerInfo {
  const PhoneRemoteServerInfo({
    required this.hosts,
    required this.port,
    required this.token,
  });

  final List<String> hosts;
  final int port;
  final String token;

  String get primaryHost => hosts.isNotEmpty ? hosts.first : '127.0.0.1';

  String pairingUri([String? hostOverride]) {
    final host = hostOverride ?? primaryHost;
    return 'pagelit://remote?host=$host&port=$port&token=$token';
  }
}

/// Local LAN WebSocket server implementing [SessionInputSource] so a mobile
/// Pagelit app on the same Wi-Fi can control the active PC presentation.
class PhoneRemoteServer implements SessionInputSource {
  PhoneRemoteServer._();

  static final PhoneRemoteServer instance = PhoneRemoteServer._();

  static const int preferredPort = 45678;

  @override
  String get id => 'phone_remote';

  @override
  String get displayName => 'Phone Remote';

  final ValueNotifier<PhoneRemoteServerInfo?> serverInfo = ValueNotifier(null);
  final ValueNotifier<int> connectedClients = ValueNotifier(0);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  SessionCommandSink? _sink;
  SessionStateSnapshot? _latestSnapshot;

  bool get isRunning => _server != null;

  @override
  void attach(SessionCommandSink onCommand) {
    _sink = onCommand;
  }

  @override
  void detach() {
    _sink = null;
  }

  /// Starts listening on all IPv4 interfaces if not already running.
  Future<PhoneRemoteServerInfo?> start() async {
    if (_server != null) return serverInfo.value;
    lastError.value = null;

    try {
      HttpServer server;
      try {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          preferredPort,
          shared: true,
        );
      } on SocketException {
        server = await HttpServer.bind(
          InternetAddress.anyIPv4,
          0,
          shared: true,
        );
      }

      _server = server;
      final token = _generatePin();
      final hosts = await _discoverLanIps();
      final info = PhoneRemoteServerInfo(
        hosts: hosts,
        port: server.port,
        token: token,
      );
      serverInfo.value = info;

      server.listen(
        (req) => _handleHttpRequest(req, token),
        onError: (Object err) {
          lastError.value = err.toString();
        },
        onDone: () {
          if (_server == server) {
            _cleanupServerState();
          }
        },
      );
      return info;
    } catch (e) {
      lastError.value = e.toString();
      return null;
    }
  }

  /// Pushes the latest [SessionStateSnapshot] to all connected phones.
  void broadcastState(SessionStateSnapshot snapshot) {
    _latestSnapshot = snapshot;
    if (_clients.isEmpty) return;
    final payload = snapshot.toJson();
    for (final ws in List<WebSocket>.from(_clients)) {
      if (ws.readyState == WebSocket.open) {
        try {
          ws.add(payload);
        } catch (_) {}
      }
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    for (final ws in List<WebSocket>.from(_clients)) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _clients.clear();
    connectedClients.value = 0;
    serverInfo.value = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() async {
    detach();
    await stop();
  }

  void _cleanupServerState() {
    _server = null;
    _clients.clear();
    connectedClients.value = 0;
    serverInfo.value = null;
  }

  Future<void> _handleHttpRequest(HttpRequest req, String expectedToken) async {
    if (req.uri.path == '/ping') {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('pagelit-remote')
        ..close();
      return;
    }

    if (req.uri.path != '/ws' || !WebSocketTransformer.isUpgradeRequest(req)) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found')
        ..close();
      return;
    }

    final token = req.uri.queryParameters['token'] ?? '';
    if (token != expectedToken) {
      req.response
        ..statusCode = HttpStatus.unauthorized
        ..write('Invalid pairing PIN')
        ..close();
      return;
    }

    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 10);
    _clients.add(ws);
    connectedClients.value = _clients.length;

    final latest = _latestSnapshot;
    if (latest != null) {
      try {
        ws.add(latest.toJson());
      } catch (_) {}
    }

    ws.listen(
      (dynamic data) {
        if (data is! String) return;
        final cmd = SessionCommand.fromJson(data);
        if (cmd == null) return;
        _sink?.call(_withPhoneSource(cmd));
      },
      onDone: () => _removeClient(ws),
      onError: (_) => _removeClient(ws),
      cancelOnError: true,
    );
  }

  void _removeClient(WebSocket ws) {
    if (_clients.remove(ws)) {
      connectedClients.value = _clients.length;
    }
  }

  static SessionCommand _withPhoneSource(SessionCommand cmd) {
    return switch (cmd) {
      NextStepCommand() => const NextStepCommand(sourceId: 'phone_remote'),
      PrevStepCommand() => const PrevStepCommand(sourceId: 'phone_remote'),
      NextItemCommand() => const NextItemCommand(sourceId: 'phone_remote'),
      PrevItemCommand() => const PrevItemCommand(sourceId: 'phone_remote'),
      JumpToIndexCommand(:final index) =>
        JumpToIndexCommand(index, sourceId: 'phone_remote'),
      ReplayAnimationsCommand() =>
        const ReplayAnimationsCommand(sourceId: 'phone_remote'),
      ToggleBlackoutCommand(:final mode) =>
        ToggleBlackoutCommand(mode, sourceId: 'phone_remote'),
      SetBlackoutCommand(:final mode) =>
        SetBlackoutCommand(mode, sourceId: 'phone_remote'),
      ToggleAutoPlayCommand() =>
        const ToggleAutoPlayCommand(sourceId: 'phone_remote'),
      ToggleTimerPauseCommand() =>
        const ToggleTimerPauseCommand(sourceId: 'phone_remote'),
      ResetTimerCommand() => const ResetTimerCommand(sourceId: 'phone_remote'),
    };
  }

  static String _generatePin() {
    final rng = Random.secure();
    final n = 1000 + rng.nextInt(9000);
    return n.toString();
  }

  static Future<List<String>> _discoverLanIps() async {
    final preferred = <String>[];
    final secondary = <String>[];

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        final nameLower = iface.name.toLowerCase();
        final isVirtual = nameLower.contains('vethernet') ||
            nameLower.contains('wsl') ||
            nameLower.contains('hyper-v') ||
            nameLower.contains('virtualbox') ||
            nameLower.contains('vmware') ||
            nameLower.contains('loopback');

        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('169.254.') || ip == '127.0.0.1') continue;
          if (!isVirtual &&
              (ip.startsWith('192.168.') ||
                  ip.startsWith('10.') ||
                  _isPrivate172(ip))) {
            preferred.add(ip);
          } else {
            secondary.add(ip);
          }
        }
      }
    } catch (_) {}

    final result = [...preferred, ...secondary];
    if (result.isEmpty) {
      result.add('127.0.0.1');
    }
    return result;
  }

  static bool _isPrivate172(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }
}
