import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

const String kDefaultApiBase = 'https://rs0hfx59-8003.asse.devtunnels.ms';

class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  String apiBase = kDefaultApiBase;
  String accessToken = '';
  String refreshToken = '';
  User? me;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    apiBase = prefs.getString('chat_api_base') ?? kDefaultApiBase;
    accessToken = prefs.getString('chat_access') ?? '';
    refreshToken = prefs.getString('chat_refresh') ?? '';
    final meStr = prefs.getString('chat_me');
    if (meStr != null) {
      try {
        me = User.fromJson(json.decode(meStr));
      } catch (_) {}
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_api_base', apiBase);
    await prefs.setString('chat_access', accessToken);
    await prefs.setString('chat_refresh', refreshToken);
    if (me != null) {
      await prefs.setString('chat_me', json.encode(me!.toJson()));
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    accessToken = '';
    refreshToken = '';
    me = null;
  }

  bool get isLoggedIn => accessToken.isNotEmpty && me != null;
}

class ApiService {
  final AuthService _auth = AuthService();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_auth.accessToken.isNotEmpty)
          'Authorization': 'Bearer ${_auth.accessToken}',
      };

  String _url(String path) => '${_auth.apiBase}$path';

  Future<dynamic> get(String path, {bool noAuth = false}) async {
    final headers = noAuth ? {'Content-Type': 'application/json'} : _headers;
    final res = await http.get(Uri.parse(_url(path)), headers: headers);
    return _handleResponse(res);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool noAuth = false}) async {
    final headers = noAuth ? {'Content-Type': 'application/json'} : _headers;
    final res = await http.post(Uri.parse(_url(path)),
        headers: headers, body: json.encode(body));
    return _handleResponse(res);
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final res = await http.patch(Uri.parse(_url(path)),
        headers: _headers, body: json.encode(body));
    return _handleResponse(res);
  }

  Future<dynamic> uploadFile(String path, List<int> fileBytes, String filename,
      String messageType) async {
    final uri = Uri.parse(_url(path));
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${_auth.accessToken}'
      ..fields['message_type'] = messageType
      ..files.add(
          http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _handleResponse(res);
  }

  dynamic _handleResponse(http.Response res) {
    dynamic data;
    try {
      data = json.decode(res.body);
    } catch (_) {
      data = {};
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    String msg = 'Request failed';
    if (data is Map) {
      if (data.containsKey('detail')) {
        msg = data['detail'].toString();
      } else if (data.containsKey('error')) {
        msg = data['error'].toString();
      } else if (data.containsKey('message')) {
        msg = data['message'].toString();
      } else if (data.isNotEmpty) {
        // Handle DRF validation errors (field-specific)
        final errors = <String>[];
        data.forEach((key, value) {
          if (value is List) {
            errors.add('$key: ${value.join(", ")}');
          } else {
            errors.add('$key: $value');
          }
        });
        msg = errors.join('\n');
      }
    }

    throw Exception(msg);
  }

  // Auth
  Future<void> login(String username, String password) async {
    final data = await post(
        '/api/auth/login/', {'username': username, 'password': password},
        noAuth: true);
    _auth.accessToken =
        (data['access'] ?? data['tokens']?['access'] ?? '') as String;
    _auth.refreshToken =
        (data['refresh'] ?? data['tokens']?['refresh'] ?? '') as String;
    final userData = data['user'] ?? data['data'];
    if (userData != null) {
      _auth.me = User.fromJson(userData as Map<String, dynamic>);
    }
    await _auth.save();
  }

  Future<void> register(
      String username, String email, String password, String password2) async {
    await post(
        '/api/auth/register/',
        {
          'username': username,
          'email': email,
          'password': password,
          'password2': password2
        },
        noAuth: true);
    await login(username, password);
  }

  Future<void> fetchMe() async {
    final data = await get('/api/auth/me/');
    _auth.me = User.fromJson((data['data'] ?? data) as Map<String, dynamic>);
    await _auth.save();
  }

  Future<void> updateProfile(
      {String? username,
      List<int>? avatarBytes,
      String? avatarFilename}) async {
    if (avatarBytes != null && avatarFilename != null) {
      // Upload with multipart form
      final uri = Uri.parse(_url('/api/auth/me/'));
      final request = http.MultipartRequest('PATCH', uri)
        ..headers['Authorization'] = 'Bearer ${_auth.accessToken}';

      if (username != null && username.isNotEmpty) {
        request.fields['username'] = username;
      }

      request.files.add(http.MultipartFile.fromBytes('avatar', avatarBytes,
          filename: avatarFilename));

      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      final data = _handleResponse(res);

      _auth.me = User.fromJson((data['data'] ?? data) as Map<String, dynamic>);
      await _auth.save();
    } else {
      // Simple JSON PATCH if only username
      final body = <String, dynamic>{};
      if (username != null && username.isNotEmpty) {
        body['username'] = username;
      }

      if (body.isEmpty) return;

      final data = await patch('/api/auth/me/', body);
      _auth.me = User.fromJson((data['data'] ?? data) as Map<String, dynamic>);
      await _auth.save();
    }
  }

  // Conversations
  Future<List<Conversation>> getConversations() async {
    final data = await get('/api/conversations/');
    final list = data is List ? data : (data['data'] as List? ?? []);
    return list
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Conversation> createConversation(int userId) async {
    final data = await post('/api/conversations/', {'user_id': userId});
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  // Messages
  Future<List<Message>> getMessages(int convId) async {
    final data = await get('/api/conversations/$convId/messages/');
    final list = data is List ? data : (data['data'] as List? ?? []);
    return list
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Message> editMessage(int convId, int msgId, String text) async {
    final data = await patch(
        '/api/conversations/$convId/messages/$msgId/edit/', {'text': text});
    return Message.fromJson(data as Map<String, dynamic>);
  }

  // Users
  Future<List<User>> getUsers() async {
    final data = await get('/api/users/');
    final list = data is List ? data : (data['data'] as List? ?? []);
    return list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setOnlineStatus(bool isOnline) async {
    if (!_auth.isLoggedIn) return;
    try {
      await patch('/api/auth/me/', {'is_online': isOnline});
      if (_auth.me != null) {
        _auth.me = User(
          id: _auth.me!.id,
          username: _auth.me!.username,
          fullName: _auth.me!.fullName,
          email: _auth.me!.email,
          avatar: _auth.me!.avatar,
          isOnline: isOnline,
        );
        await _auth.save();
      }
    } catch (_) {}
  }
}
