import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

typedef SocketPayloadCallback = void Function(Map<String, dynamic> payload);

class SocketService {
  static final SocketService _instance = SocketService._();
  factory SocketService() => _instance;
  SocketService._();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  int? _convId;
  bool _manualClose = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  SocketPayloadCallback? onPayload;
  VoidCallback? onOpen;

  bool get isOpen => _channel != null;

  void connect(int convId,
      {SocketPayloadCallback? callback, VoidCallback? onConnected}) {
    if (_channel != null && _convId == convId) {
      // Important: when reopening the same conversation, refresh callbacks
      // so new screen instance receives realtime payloads.
      onPayload = callback;
      onOpen = onConnected;
      send({'action': 'mark_read'});
      onConnected?.call();
      return;
    }
    disconnect(manual: true);
    _convId = convId;
    _manualClose = false;
    onPayload = callback;
    onOpen = onConnected;
    _doConnect(convId);
  }

  void _doConnect(int convId) {
    final auth = AuthService();
    final base = auth.apiBase;
    final token = auth.accessToken;
    final wsBase = base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final uri = Uri.parse(
        '$wsBase/ws/chat/$convId/?token=${Uri.encodeComponent(token)}');

    try {
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        (data) {
          try {
            final payload = json.decode(data as String) as Map<String, dynamic>;
            onPayload?.call(payload);
          } catch (_) {}
        },
        onDone: () {
          _channel = null;
          if (!_manualClose) _scheduleReconnect(convId);
        },
        onError: (_) {
          _channel = null;
          if (!_manualClose) _scheduleReconnect(convId);
        },
      );
      // Slight delay before sending init actions
      Future.delayed(const Duration(milliseconds: 300), () {
        send({'action': 'mark_read'});
        send({'action': 'presence_ping'});
        _reconnectAttempts = 0;
        onOpen?.call();
      });
    } catch (_) {
      if (!_manualClose) _scheduleReconnect(convId);
    }
  }

  void _scheduleReconnect(int convId) {
    final delay = Duration(
        milliseconds: (3000 * (_reconnectAttempts + 1)).clamp(0, 30000));
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      _doConnect(convId);
    });
  }

  bool send(Map<String, dynamic> data) {
    try {
      final ch = _channel;
      if (ch == null) return false;
      ch.sink.add(json.encode(data));
      return true;
    } catch (_) {
      return false;
    }
  }

  void disconnect({bool manual = true}) {
    _manualClose = manual;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _sub = null;
  }
}

typedef VoidCallback = void Function();
