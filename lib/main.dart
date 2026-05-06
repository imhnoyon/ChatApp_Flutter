import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/api_service.dart';
import 'screens/auth_screen.dart';
import 'screens/conversations_screen.dart';
import 'screens/call_screen.dart';
import 'services/socket_service.dart';
import 'models/models.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  await AuthService().load();
  runApp(const ChatApp());
}

class ChatApp extends StatefulWidget {
  const ChatApp({super.key});

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> with WidgetsBindingObserver {
  final _auth = AuthService();
  bool _isDark = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _loggedIn = _auth.isLoggedIn;
    WidgetsBinding.instance.addObserver(this);
    if (_loggedIn) {
      _connectPresenceAndNotifications();
    }
  }

  void _connectPresenceAndNotifications() {
    ApiService().setOnlineStatus(true);
    SocketService().connectNotifications(
        callback: _handleNotification,
        onConnected: () {
          debugPrint('🔔 Notifications socket active (main)');
        });
  }

  void _handleNotification(Map<String, dynamic> p) {
    try {
      final type =
          (p['type'] as String? ?? p['action'] as String? ?? '').toLowerCase();
      if (type == 'incoming_call' ||
          type == 'call_event' ||
          type == 'call_update') {
        final rawCall = p['call'] ?? p;
        final session = CallSession.fromJson(rawCall as Map<String, dynamic>);
        // If the call was initiated by someone else, show incoming call screen
        if (session.status == 'initiated' &&
            session.caller.id != _auth.me?.id) {
          navigatorKey.currentState?.push(MaterialPageRoute(
            builder: (_) => CallScreen(session: session, isIncoming: true),
          ));
        }
      }
    } catch (e) {
      debugPrint('🔔 Notification handler error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_loggedIn) return;
    if (state == AppLifecycleState.resumed) {
      ApiService().setOnlineStatus(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ApiService().setOnlineStatus(false);
    }
  }

  void _onLogin() {
    setState(() => _loggedIn = true);
    _connectPresenceAndNotifications();
  }

  void _onLogout() async {
    await ApiService().setOnlineStatus(false);
    await _auth.clear();
    // Disconnect notifications socket
    SocketService().disconnectNotifications(manual: true);
    setState(() => _loggedIn = false);
  }

  void _toggleTheme() => setState(() => _isDark = !_isDark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'ChatApp',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: _loggedIn
          ? ConversationsScreen(
              onLogout: _onLogout,
              onToggleTheme: _toggleTheme,
            )
          : AuthScreen(onLogin: _onLogin),
    );
  }
}
