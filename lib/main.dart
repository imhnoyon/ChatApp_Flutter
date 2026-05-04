import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/api_service.dart';
import 'screens/auth_screen.dart';
import 'screens/conversations_screen.dart';
import 'theme.dart';

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
      ApiService().setOnlineStatus(true);
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
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      ApiService().setOnlineStatus(false);
    }
  }

  void _onLogin() {
    setState(() => _loggedIn = true);
    ApiService().setOnlineStatus(true);
  }

  void _onLogout() async {
    await ApiService().setOnlineStatus(false);
    await _auth.clear();
    setState(() => _loggedIn = false);
  }

  void _toggleTheme() => setState(() => _isDark = !_isDark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
