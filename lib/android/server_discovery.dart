import 'dart:async';
import 'dart:convert';
import 'dart:io';

const configuredWsHost = String.fromEnvironment(
  'CHAT_WS_HOST',
  defaultValue: '',
);
const discoveryPort = int.fromEnvironment(
  'CHAT_DISCOVERY_PORT',
  defaultValue: 10001,
);
const discoveryMagic = String.fromEnvironment(
  'CHAT_DISCOVERY_MAGIC',
  defaultValue: 'CHAT_SOCIAL_DISCOVER',
);

class ServerDiscovery {
  static String? _cachedWsHost;

  static Future<String?> discoverWsHost({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (configuredWsHost.isNotEmpty) {
      _cachedWsHost = configuredWsHost;
      return configuredWsHost;
    }
    if (_cachedWsHost != null && _cachedWsHost!.isNotEmpty) {
      return _cachedWsHost;
    }

    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? sub;
    final completer = Completer<String?>();

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      sub = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) {
          return;
        }
        final packet = socket?.receive();
        if (packet == null) return;
        try {
          final raw = utf8.decode(packet.data, allowMalformed: true);
          final payload = jsonDecode(raw);
          if (payload is! Map<String, dynamic>) return;
          final wsPort = (payload['ws_port'] as num?)?.toInt() ?? 10000;
          final senderIp = packet.address.address;

          String wsUrl = '';
          if (senderIp.isNotEmpty && !senderIp.contains(':')) {
            wsUrl = 'ws://$senderIp:$wsPort/ws';
          } else {
            wsUrl = (payload['ws_url'] as String?)?.trim() ?? '';
          }

          if (wsUrl.startsWith('ws://') || wsUrl.startsWith('wss://')) {
            _cachedWsHost = wsUrl;
            completer.complete(wsUrl);
          }
        } catch (_) {}
      });

      final request = jsonEncode({
        'type': 'discover_chat_social',
        'magic': discoveryMagic,
      });
      final bytes = utf8.encode(request);
      socket.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);

      final resolved = await completer.future.timeout(
        timeout,
        onTimeout: () => null,
      );
      return resolved;
    } catch (_) {
      return null;
    } finally {
      await sub?.cancel();
      socket?.close();
    }
  }
}
