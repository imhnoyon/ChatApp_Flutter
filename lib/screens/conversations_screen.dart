import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

class ConversationsScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onToggleTheme;

  const ConversationsScreen({
    super.key,
    required this.onLogout,
    required this.onToggleTheme,
  });

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final _api = ApiService();
  final _auth = AuthService();
  List<Conversation> _conversations = [];
  List<User> _allUsers = [];
  bool _showingUsers = false;
  bool _loading = true;
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  String? _resolveAvatarUrl(String? avatar) {
    if (avatar == null || avatar.isEmpty) return null;
    
    // Fix backend returning absolute localhost URLs
    if (avatar.startsWith('http://localhost') || avatar.startsWith('http://127.0.0.1')) {
      try {
        final uri = Uri.parse(avatar);
        return _auth.apiBase + uri.path;
      } catch (_) {}
    }
    
    if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
      return avatar;
    }
    return '${_auth.apiBase}${avatar.startsWith('/') ? '' : '/'}$avatar';
  }

  Future<void> _loadConversations() async {
    try {
      final convs = await _api.getConversations();
      if (mounted) {
        setState(() {
          _conversations = convs;
          _loading = false;
          if (convs.isEmpty) _loadUsers();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _api.getUsers();
      if (mounted) {
        setState(() {
          _allUsers = users.where((u) => u.id != _auth.me?.id).toList();
          _showingUsers = true;
        });
      }
    } catch (_) {}
  }

  void _toggleNewChat() {
    if (_showingUsers) {
      setState(() => _showingUsers = false);
    } else {
      _loadUsers();
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          onProfileUpdated: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _openUserChat(User user) async {
    setState(() => _showingUsers = false);
    final existing = _conversations.where((c) => c.otherUser.id == user.id);
    if (existing.isNotEmpty) {
      _openConversation(existing.first);
      return;
    }
    try {
      final conv = await _api.createConversation(user.id);
      _openConversation(conv);
      _loadConversations();
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  void _openConversation(Conversation conv) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversation: conv,
          onBack: _loadConversations,
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  List<Conversation> get _filtered => _conversations.where((c) {
        final name = c.otherUser.displayName.toLowerCase();
        return name.contains(_searchTerm.toLowerCase());
      }).toList();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? kDarkSurface : kLightSurface;
    final textColor = isDark ? kDarkText : kLightText;
    final subColor = isDark ? kDarkSubText : kLightSubText;
    final bgColor = isDark ? kDarkBg : kLightBg;
    final dividerColor = isDark ? kDarkDivider : const Color(0xFFE9EDEF);

    final me = _auth.me;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // Header
          Container(
            color: surfaceColor,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    // Avatar - Clickable for profile
                    GestureDetector(
                      onTap: _openProfile,
                      child: _resolveAvatarUrl(me?.avatar) != null
                          ? CircleAvatar(
                              radius: 18,
                              backgroundImage: CachedNetworkImageProvider(
                                  _resolveAvatarUrl(me?.avatar)!),
                            )
                          : CircleAvatar(
                              radius: 18,
                              backgroundColor: kBrandGreen,
                              child: Text(
                                me?.initials ?? '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: _openProfile,
                        child: Text(
                          me?.displayName ?? '',
                          style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                          _showingUsers ? Icons.close : Icons.edit_outlined,
                          color: subColor),
                      onPressed: _toggleNewChat,
                      tooltip: 'New chat',
                    ),
                    IconButton(
                      icon: Icon(
                        isDark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        color: subColor,
                      ),
                      onPressed: widget.onToggleTheme,
                      tooltip: 'Toggle theme',
                    ),
                    IconButton(
                      icon: Icon(Icons.logout_rounded, color: subColor),
                      onPressed: widget.onLogout,
                      tooltip: 'Logout',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Search bar
          Container(
            color: surfaceColor,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _searchTerm = v),
              style: TextStyle(color: textColor, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search conversations…',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),

          Divider(height: 1, color: dividerColor),

          // List
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: kBrandGreen))
                : _showingUsers
                    ? _buildUsersList(textColor, subColor, dividerColor)
                    : _buildConvList(textColor, subColor, dividerColor),
          ),
        ],
      ),
    );
  }

  Widget _buildConvList(Color textColor, Color subColor, Color dividerColor) {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: subColor),
            const SizedBox(height: 16),
            Text('No conversations yet', style: TextStyle(color: subColor)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadUsers,
              icon: const Icon(Icons.person_add_outlined, color: kBrandGreen),
              label: const Text('Start a new chat',
                  style: TextStyle(color: kBrandGreen)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadConversations,
      color: kBrandGreen,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, indent: 72, color: dividerColor),
        itemBuilder: (_, i) => _ConvTile(
          conv: items[i],
          textColor: textColor,
          subColor: subColor,
          avatarUrl: _resolveAvatarUrl(items[i].otherUser.avatar),
          onTap: () => _openConversation(items[i]),
        ),
      ),
    );
  }

  Widget _buildUsersList(Color textColor, Color subColor, Color dividerColor) {
    if (_allUsers.isEmpty) {
      return Center(
          child: Text('No users found', style: TextStyle(color: subColor)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('All Users',
              style: TextStyle(
                  color: kBrandGreen,
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: _allUsers.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, indent: 72, color: dividerColor),
            itemBuilder: (_, i) {
              final user = _allUsers[i];
              final avatarUrl = _resolveAvatarUrl(user.avatar);
              return ListTile(
                leading: avatarUrl != null
                    ? CircleAvatar(
                        backgroundImage: CachedNetworkImageProvider(avatarUrl),
                      )
                    : CircleAvatar(
                        backgroundColor: kBrandGreen,
                        child: Text(user.initials,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                title: Text(user.displayName,
                    style: TextStyle(
                        color: textColor, fontWeight: FontWeight.w500)),
                subtitle: Text('Tap to start chatting',
                    style: TextStyle(color: subColor, fontSize: 12)),
                trailing: const Icon(Icons.play_arrow_rounded,
                    color: kBrandGreen, size: 20),
                onTap: () => _openUserChat(user),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConvTile extends StatelessWidget {
  final Conversation conv;
  final Color textColor, subColor;
  final VoidCallback onTap;
  final String? avatarUrl;

  const _ConvTile({
    required this.conv,
    required this.textColor,
    required this.subColor,
    required this.onTap,
    this.avatarUrl,
  });

  String _lastMsgPreview() {
    final m = conv.lastMessage;
    if (m == null) return 'No messages yet';
    if (m.messageType == 'image') return '📷 Photo';
    if (m.messageType == 'voice') return '🎤 Voice message';
    return m.text ?? '';
  }

  String _time() {
    final m = conv.lastMessage;
    if (m == null) return '';
    final t = m.createdAt;
    final now = DateTime.now();
    if (now.difference(t).inDays == 0) {
      final h = t.hour;
      final min = t.minute.toString().padLeft(2, '0');
      final ampm = h >= 12 ? 'PM' : 'AM';
      final hh = (h % 12 == 0 ? 12 : h % 12);
      return '$hh:$min $ampm';
    }
    return '${t.day}/${t.month}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            avatarUrl != null
                ? CircleAvatar(
                    radius: 24,
                    backgroundImage: CachedNetworkImageProvider(avatarUrl!),
                  )
                : CircleAvatar(
                    radius: 24,
                    backgroundColor: kBrandGreen,
                    child: Text(
                      conv.otherUser.initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    ),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.otherUser.displayName,
                          style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(_time(),
                          style: TextStyle(
                              color:
                                  conv.unreadCount > 0 ? kBrandGreen : subColor,
                              fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _lastMsgPreview(),
                          style: TextStyle(
                              color:
                                  conv.unreadCount > 0 ? textColor : subColor,
                              fontSize: 13,
                              fontWeight: conv.unreadCount > 0
                                  ? FontWeight.w500
                                  : FontWeight.normal),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (conv.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: kBrandGreen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${conv.unreadCount}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
