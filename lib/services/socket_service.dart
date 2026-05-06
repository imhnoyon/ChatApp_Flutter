import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

typedef SocketPayloadCallback = void Function(Map<String, dynamic> payload);

class SocketService {
  static final SocketService _instance = SocketService._();
  factory SocketService() => _instance;
  SocketService._();

  // Conversation socket
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  int? _convId;

  // Call socket
  WebSocketChannel? _callChannel;
  StreamSubscription? _callSub;
  int? _callId;

  // Notifications socket (global user-level notifications)
  WebSocketChannel? _notifChannel;
  StreamSubscription? _notifSub;

  bool _manualClose = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  SocketPayloadCallback? onPayload;
  SocketPayloadCallback? onCallPayload;
  SocketPayloadCallback? onNotifPayload;
  VoidCallback? onOpen;

  bool get isOpen => _channel != null;

  bool get isCallOpen => _callChannel != null;

  void connectCall(int callId,
      {SocketPayloadCallback? callback, VoidCallback? onConnected}) {
    if (_callChannel != null && _callId == callId) {
      onCallPayload = callback;
      onConnected?.call();
      return;
    }
    disconnectCall(manual: true);
    _callId = callId;
    onCallPayload = callback;
    _doConnectCall(callId, onConnected);
  }

  void _doConnectCall(int callId, VoidCallback? onConnected) {
    final auth = AuthService();
    final base = auth.apiBase;
    final token = auth.accessToken;
    final wsBase = base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final uri = Uri.parse(
        '$wsBase/ws/call/$callId/?token=${Uri.encodeComponent(token)}');

    debugPrint('☎️ Connecting to call WebSocket: $uri');
    try {
      _callChannel = WebSocketChannel.connect(uri);
      _callSub = _callChannel!.stream.listen(
        (data) {
          try {
            debugPrint('☎️ Raw WebSocket data: $data');
            final payload = json.decode(data as String) as Map<String, dynamic>;
            debugPrint('☎️ Parsed WebSocket payload: $payload');
            onCallPayload?.call(payload);
          } catch (e) {
            debugPrint('☎️ Payload parse error: $e');
          }
        },
        onDone: () {
          debugPrint('☎️ Call WebSocket closed');
          _callChannel = null;
          if (!_manualClose) _scheduleReconnectCall(callId, onConnected);
        },
        onError: (e) {
          debugPrint('☎️ Call WebSocket error: $e');
          _callChannel = null;
          if (!_manualClose) _scheduleReconnectCall(callId, onConnected);
        },
      );
      Future.delayed(const Duration(milliseconds: 300), () {
        _reconnectAttempts = 0;
        debugPrint('☎️ Call WebSocket connected successfully');
        onConnected?.call();
      });
    } catch (e) {
      debugPrint('☎️ Call WebSocket connection error: $e');
      if (!_manualClose) _scheduleReconnectCall(callId, onConnected);
    }
  }

  void _scheduleReconnectCall(int callId, VoidCallback? onConnected) {
    final delay = Duration(
        milliseconds: (3000 * (_reconnectAttempts + 1)).clamp(0, 30000));
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      _doConnectCall(callId, onConnected);
    });
  }

  void connectNotifications(
      {SocketPayloadCallback? callback, VoidCallback? onConnected}) {
    if (_notifChannel != null) {
      // refresh callback
      onNotifPayload = callback;
      onConnected?.call();
      return;
    }
    disconnectNotifications(manual: true);
    onNotifPayload = callback;
    _doConnectNotifications(onConnected);
  }

  void _doConnectNotifications(VoidCallback? onConnected) {
    final auth = AuthService();
    final base = auth.apiBase;
    final token = auth.accessToken;
    final wsBase = base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final uri = Uri.parse(
        '$wsBase/ws/notifications/?token=${Uri.encodeComponent(token)}');
    debugPrint('🔔 Connecting to notifications WebSocket: $uri');
    try {
      _notifChannel = WebSocketChannel.connect(uri);
      _notifSub = _notifChannel!.stream.listen((data) {
        try {
          debugPrint('🔔 Raw notif data: $data');
          final payload = json.decode(data as String) as Map<String, dynamic>;
          onNotifPayload?.call(payload);
        } catch (e) {
          debugPrint('🔔 notif parse error: $e');
        }
      }, onDone: () {
        debugPrint('🔔 Notifications socket closed');
        _notifChannel = null;
        if (!_manualClose) _scheduleReconnectNotif(onConnected);
      }, onError: (e) {
        debugPrint('🔔 Notifications socket error: $e');
        _notifChannel = null;
        if (!_manualClose) _scheduleReconnectNotif(onConnected);
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        _reconnectAttempts = 0;
        debugPrint('🔔 Notifications socket connected');
        onConnected?.call();
      });
    } catch (e) {
      debugPrint('🔔 Notifications connect error: $e');
      if (!_manualClose) _scheduleReconnectNotif(onConnected);
    }
  }

  void _scheduleReconnectNotif(VoidCallback? onConnected) {
    final delay = Duration(
        milliseconds: (3000 * (_reconnectAttempts + 1)).clamp(0, 30000));
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      _doConnectNotifications(onConnected);
    });
  }

  void disconnectNotifications({bool manual = true}) {
    _manualClose = manual;
    _reconnectTimer?.cancel();
    _notifSub?.cancel();
    _notifChannel?.sink.close();
    _notifChannel = null;
    _notifSub = null;
  }

  void disconnectCall({bool manual = true}) {
    _manualClose = manual;
    _reconnectTimer?.cancel();
    _callSub?.cancel();
    _callChannel?.sink.close();
    _callChannel = null;
    _callSub = null;
  }

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
    debugPrint('💬 Connecting to conversation WebSocket: $uri');

    try {
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        (data) {
          try {
            debugPrint('💬 Raw WebSocket data: $data');
            final payload = json.decode(data as String) as Map<String, dynamic>;
            debugPrint('💬 Parsed WebSocket payload: $payload');
            onPayload?.call(payload);
          } catch (e) {
            debugPrint('💬 Payload parse error: $e');
          }
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
      debugPrint('💬 Sending on conversation socket: $data');
      if (ch == null) {
        debugPrint('💬 Send failed: conversation socket not connected');
        return false;
      }
      ch.sink.add(json.encode(data));
      return true;
    } catch (_) {
      debugPrint('💬 Send error: $_');
      return false;
    }
  }

  bool sendCall(Map<String, dynamic> data) {
    try {
      final ch = _callChannel;
      debugPrint('☎️ Sending on call socket: $data');
      if (ch == null) {
        debugPrint('☎️ SendCall failed: call socket not connected');
        return false;
      }
      ch.sink.add(json.encode(data));
      return true;
    } catch (_) {
      debugPrint('☎️ SendCall error: $_');
      return false;
    }
  }

  bool sendNotification(Map<String, dynamic> data) {
    try {
      final ch = _notifChannel;
      debugPrint('🔔 Sending on notifications socket: $data');
      if (ch == null) {
        debugPrint(
            '🔔 SendNotification failed: notifications socket not connected');
        return false;
      }
      ch.sink.add(json.encode(data));
      return true;
    } catch (_) {
      debugPrint('🔔 SendNotification error: $_');
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
