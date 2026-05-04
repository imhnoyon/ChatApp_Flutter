import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../theme.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  final VoidCallback? onBack;

  const ChatScreen({super.key, required this.conversation, this.onBack});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ApiService();
  final _auth = AuthService();
  final _socket = SocketService();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _recorder = AudioRecorder();
  final _focusNode = FocusNode();

  List<Message> _messages = [];
  bool _loading = true;
  bool _stickToBottom = true;
  bool _isTyping = false;
  bool _isRecording = false;
  Timer? _typingTimer;
  Timer? _remoteTypingTimer;
  Timer? _recordTimer;
  Duration _recordDuration = Duration.zero;
  bool _recordStartInProgress = false;
  bool _recordStopInProgress = false;
  String? _recordPath;
  bool _isOnline = false;
  Message? _editingMessage;

  late Conversation _conv;

  @override
  void initState() {
    super.initState();
    _conv = widget.conversation;
    _loadMessages();
    _scrollCtrl.addListener(_onScroll);
  }

// Local URL resolvers removed in favor of ApiService.resolveMediaUrl

  @override
  void dispose() {
    _typingTimer?.cancel();
    _remoteTypingTimer?.cancel();
    _recordTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _recorder.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollCtrl.position;
    _stickToBottom = (pos.maxScrollExtent - pos.pixels) < 80;
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await _api.getMessages(_conv.id);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _loading = false;
        });
        _scrollToBottom(immediate: true);
        _connectSocket();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _connectSocket() {
    _socket.connect(
      _conv.id,
      callback: _handleSocketPayload,
      onConnected: () {
        _socket.send({'action': 'mark_read'});
        _socket.send({'action': 'presence_ping'});
      },
    );
  }

  void _handleSocketPayload(Map<String, dynamic> p) {
    if (!mounted) return;
    final type = (p['type'] as String? ?? '').toLowerCase();
    final action = (p['action'] as String? ?? '').toLowerCase();

    // Broaden the check for message-related events
    if (type == 'message' ||
        type == 'new_message' ||
        type == 'created' ||
        type == 'chat_message' ||
        action == 'message' ||
        p['message'] != null ||
        (p.containsKey('id') &&
            (p.containsKey('text') || p.containsKey('file')))) {
      // Normalize message payload
      final rawMsg = p['message'] is Map<String, dynamic>
          ? p['message'] as Map<String, dynamic>
          : p;

      final serverMsg = Message.fromJson(rawMsg.cast<String, dynamic>());
      debugPrint(
          'Socket message received: ID=${serverMsg.id}, Type=${serverMsg.messageType}');

      if (serverMsg.id == 0 &&
          serverMsg.text == null &&
          serverMsg.file == null) {
        debugPrint('Discarding invalid socket message');
        return;
      }

      setState(() {
        // 1. Check if this message is already in our list (by ID)
        final existingIdx =
            _messages.indexWhere((m) => m.id != 0 && m.id == serverMsg.id);

        if (existingIdx != -1) {
          // Update existing message (e.g. status change)
          final oldLocalFile = _messages[existingIdx].localFile;
          _messages[existingIdx] = Message(
            id: serverMsg.id,
            senderId: serverMsg.senderId,
            text: serverMsg.text,
            messageType: serverMsg.messageType,
            file: serverMsg.file,
            localFile: oldLocalFile ?? serverMsg.localFile,
            createdAt: serverMsg.createdAt,
            status: serverMsg.status,
            isEdited: serverMsg.isEdited,
            reactions: serverMsg.reactions,
            optimistic: false,
          );
        } else {
          // 2. If not in list, try to replace a recent optimistic message
          final optIdx = _messages.lastIndexWhere((m) =>
              m.optimistic &&
              m.messageType == serverMsg.messageType &&
              (serverMsg.text == null || m.text == serverMsg.text));

          if (optIdx != -1) {
            final oldMsg = _messages[optIdx];
            _messages[optIdx] = Message(
              id: serverMsg.id,
              senderId: serverMsg.senderId,
              text: serverMsg.text,
              messageType: serverMsg.messageType,
              file: serverMsg.file,
              localFile: oldMsg.localFile,
              createdAt: serverMsg.createdAt,
              status: serverMsg.status,
              isEdited: serverMsg.isEdited,
              reactions: serverMsg.reactions,
              optimistic: false,
            );
          } else {
            // 3. Just add it as a new message
            _messages.add(serverMsg);

            // Background "Warm up": Pre-fetch images as soon as they arrive via socket
            if (serverMsg.messageType == 'image' && serverMsg.file != null) {
              final url = _api.resolveMediaUrl(serverMsg.file);
              if (url.isNotEmpty) {
                precacheImage(CachedNetworkImageProvider(url), context)
                    .catchError((_) {});
              }
            }
          }
        }
      });

      if (_stickToBottom) _scrollToBottom();

      final senderId = serverMsg.senderId;
      if (senderId != null && senderId != _auth.me?.id) {
        _socket.send({'action': 'seen', 'message_id': serverMsg.id});
        _socket.send({'action': 'mark_read'});
      }
    } else if (type == 'typing' ||
        type == 'is_typing' ||
        type == 'typing_status') {
      // Support multiple payload shapes and ignore typing events from self.
      final rawVal =
          p['is_typing'] ?? p['isTyping'] ?? p['typing'] ?? p['value'];
      bool isTyping = false;
      if (rawVal is bool) {
        isTyping = rawVal;
      } else if (rawVal is num) {
        isTyping = rawVal != 0;
      } else if (rawVal != null) {
        final s = rawVal.toString().toLowerCase();
        isTyping = s == 'true' || s == '1';
      }

      final senderRaw =
          p['user_id'] ?? p['sender_id'] ?? p['user'] ?? p['from'];
      int? senderId;
      if (senderRaw is num) senderId = senderRaw.toInt();
      if (senderRaw is String) senderId = int.tryParse(senderRaw);

      // Ignore typing events originating from ourselves
      if (senderId != null && senderId == _auth.me?.id) {
        return;
      }

      if (!mounted) return;
      setState(() => _isTyping = isTyping);

      // If someone started typing, auto-clear after 3 seconds of inactivity.
      _remoteTypingTimer?.cancel();
      if (isTyping) {
        _remoteTypingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _isTyping = false);
        });
      }
    } else if (type == 'seen') {
      final mid = (p['message_id'] as num?)?.toInt();
      if (mid != null) {
        setState(() {
          for (final m in _messages) {
            if (m.id == mid) m.status = 'seen';
          }
        });
      }
    } else if (type == 'reaction' || type == 'message_reaction') {
      final mid = (p['message_id'] as num?)?.toInt() ??
          (p['id'] as num?)?.toInt() ??
          (p['message'] is Map
              ? ((p['message']['id'] as num?)?.toInt())
              : null);
      final rawReactions = p['reactions'];
      List<Reaction> reactions = [];
      if (rawReactions is List) {
        reactions = rawReactions
            .whereType<Map<String, dynamic>>()
            .map(Reaction.fromJson)
            .toList();
      } else if (p['emoji'] is String) {
        reactions = [
          Reaction(
              emoji: p['emoji'] as String, userId: p['user_id'] ?? p['user'])
        ];
      }
      if (mid != null) {
        setState(() {
          for (final m in _messages) {
            if (m.id == mid) m.reactions = reactions;
          }
        });
      }
    } else if (type == 'status') {
      final userId = (p['user_id'] as num?)?.toInt();
      if (userId != _auth.me?.id) {
        setState(() => _isOnline = p['status'] == 'online');
      }
    } else if (type == 'presence_query') {
      _socket.send({'action': 'presence_pong'});
    } else if (type == 'message_status') {
      final mid = (p['message_id'] as num?)?.toInt();
      final status = p['status'] as String?;
      if (mid != null && status != null) {
        setState(() {
          for (final m in _messages) {
            if (m.id == mid) m.status = status;
          }
        });
      }
    }
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: immediate
              ? const Duration(milliseconds: 1)
              : const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingMessage = null;
      _msgCtrl.clear();
    });
  }

  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    if (_editingMessage != null) {
      if (text != _editingMessage!.text) {
        _editMessage(_editingMessage!, text);
      }
      _cancelEditing();
      return;
    }

    _msgCtrl.clear();
    final tempId = DateTime.now().millisecondsSinceEpoch;
    final tempMsg = Message(
      id: tempId,
      senderId: _auth.me?.id,
      text: text,
      messageType: 'text',
      createdAt: DateTime.now(),
      status: 'sending',
      optimistic: true,
    );
    setState(() => _messages.add(tempMsg));
    _scrollToBottom();
    final sent = _socket.send({'action': 'send_message', 'text': text});
    if (!sent) {
      setState(() {
        final idx = _messages
            .indexWhere((m) => m.optimistic && m.messageType == 'text');
        if (idx != -1) _messages[idx].status = 'failed';
      });
      _showSnack('Message could not be sent. Check connection.');
      return;
    }

    // Some backends don't emit immediate ack events for text messages.
    // Prevent the UI from staying in `sending` forever.
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == tempId && m.optimistic);
        if (idx != -1 && _messages[idx].status == 'sending') {
          _messages[idx].status = 'delivered';
        }
      });
    });
  }

  void _onTypingInput(String _) {
    _socket.send({'action': 'typing', 'is_typing': true});
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1500), () {
      _socket.send({'action': 'typing', 'is_typing': false});
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 90,
    );
    if (picked == null) return;

    // Show image instantly in chat UI before doing heavy lifting
    _sendOptimisticMedia('image', localPath: picked.path);

    final bytes = await picked.readAsBytes();
    final name = picked.name;
    try {
      final data = await _api.uploadFile(
          '/api/conversations/${_conv.id}/upload/', bytes, name, 'image');
      if (data is Map<String, dynamic>) {
        final serverMsg = Message.fromJson(data.cast<String, dynamic>());
        setState(() {
          final idx = _messages
              .lastIndexWhere((m) => m.optimistic && m.messageType == 'image');
          if (idx != -1) {
            final oldMsg = _messages[idx];
            _messages[idx] = Message(
              id: serverMsg.id,
              senderId: serverMsg.senderId,
              text: serverMsg.text,
              messageType: serverMsg.messageType,
              file: serverMsg.file,
              localFile: oldMsg.localFile, // Keep local preview
              createdAt: serverMsg.createdAt,
              status: serverMsg.status,
              isEdited: serverMsg.isEdited,
              reactions: serverMsg.reactions,
              optimistic: false,
            );
          }
        });
      }
    } catch (e) {
      _showSnack(e.toString());
      setState(() => _messages
          .removeWhere((m) => m.optimistic && m.messageType == 'image'));
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _recordStartInProgress) return;
    _recordStartInProgress = true;
    final hasPerms = await _recorder.hasPermission();
    if (!hasPerms) {
      _recordStartInProgress = false;
      _showSnack('Microphone permission denied');
      return;
    }
    final dir = await getTemporaryDirectory();
    _recordPath =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    setState(() {
      _isRecording = true;
      _recordDuration = Duration.zero;
    });
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isRecording) return;
      setState(() => _recordDuration += const Duration(seconds: 1));
    });
    try {
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: _recordPath!);
    } catch (_) {
      _recordTimer?.cancel();
      if (mounted) {
        setState(() => _isRecording = false);
      }
      _showSnack('Could not start recording');
    } finally {
      _recordStartInProgress = false;
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _recordStopInProgress) return;
    _recordStopInProgress = true;
    _recordTimer?.cancel();
    String? stoppedPath;
    try {
      stoppedPath = await _recorder.stop();
    } catch (_) {
      // Fallback to force-stop recorder if normal stop fails.
      try {
        await _recorder.cancel();
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _isRecording = false);
      }
      _recordStopInProgress = false;
    }
    final path = stoppedPath ?? _recordPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    _sendOptimisticMedia('voice', localPath: path);
    try {
      final data = await _api.uploadFile(
          '/api/conversations/${_conv.id}/upload/',
          bytes,
          'voice.m4a',
          'voice');
      if (data is Map<String, dynamic>) {
        final serverMsg = Message.fromJson(data.cast<String, dynamic>());
        setState(() {
          final idx = _messages
              .lastIndexWhere((m) => m.optimistic && m.messageType == 'voice');
          if (idx != -1) {
            final oldMsg = _messages[idx];
            _messages[idx] = Message(
              id: serverMsg.id,
              senderId: serverMsg.senderId,
              text: serverMsg.text,
              messageType: serverMsg.messageType,
              file: serverMsg.file,
              localFile: oldMsg.localFile, // Keep local preview
              createdAt: serverMsg.createdAt,
              status: serverMsg.status,
              isEdited: serverMsg.isEdited,
              reactions: serverMsg.reactions,
              optimistic: false,
            );
          }
        });
        return;
      }
    } catch (e) {
      try {
        final data = await _api.uploadFile(
            '/api/conversations/${_conv.id}/upload/',
            bytes,
            'voice.m4a',
            'audio');
        if (data is Map<String, dynamic>) {
          final serverMsg = Message.fromJson(data.cast<String, dynamic>());
          setState(() {
            final idx = _messages.lastIndexWhere(
                (m) => m.optimistic && m.messageType == 'voice');
            if (idx != -1) {
              final oldMsg = _messages[idx];
              _messages[idx] = Message(
                id: serverMsg.id,
                senderId: serverMsg.senderId,
                text: serverMsg.text,
                messageType: serverMsg.messageType,
                file: serverMsg.file,
                localFile: oldMsg.localFile, // Keep local preview
                createdAt: serverMsg.createdAt,
                status: serverMsg.status,
                isEdited: serverMsg.isEdited,
                reactions: serverMsg.reactions,
                optimistic: false,
              );
            }
          });
          return;
        }
      } catch (_) {}
      _showSnack(e.toString());
      setState(() => _messages
          .removeWhere((m) => m.optimistic && m.messageType == 'voice'));
    }
  }

  String _formatRecordDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _sendOptimisticMedia(String type, {String? localPath}) {
    setState(() {
      _messages.add(Message(
        id: DateTime.now().millisecondsSinceEpoch,
        senderId: _auth.me?.id,
        messageType: type,
        file: localPath,
        localFile: localPath, // Set localFile here too!
        createdAt: DateTime.now(),
        status: 'sending',
        optimistic: true,
      ));
    });
    _scrollToBottom();
  }

  void _sendReaction(int msgId, String emoji) {
    final myId = _auth.me?.id;
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx == -1) return;
      final msg = _messages[idx];
      final next = [...msg.reactions];
      final mine = next.any((r) => r.emoji == emoji && r.userId == myId);
      next.removeWhere((r) => r.userId == myId);
      if (!mine) {
        next.add(Reaction(emoji: emoji, userId: myId));
      }
      msg.reactions = next;
    });

    final sent = _socket.send(
      {'action': 'react', 'message_id': msgId, 'emoji': emoji},
    );
    if (!sent) {
      _showSnack('Connection issue. Please wait a moment and try again.');
    }
  }

  Future<void> _editMessage(Message msg, String newText) async {
    try {
      final updated = await _api.editMessage(_conv.id, msg.id, newText);
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        if (idx != -1) {
          _messages[idx] = Message(
            id: updated.id,
            senderId: updated.senderId ?? msg.senderId,
            text: updated.text,
            messageType: updated.messageType,
            file: updated.file,
            createdAt: updated.createdAt,
            status: msg.status,
            isEdited: true,
            reactions: msg.reactions,
          );
        }
      });
      _showSnack('Message updated');
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? kDarkBg : const Color(0xFFEFE5DD);
    final headerColor = isDark ? kDarkSurface : kBrandGreen;
    final textColor = isDark ? kDarkText : Colors.white;
    final subColor = isDark ? kDarkSubText : Colors.white70;
    final inputTextColor = isDark ? kDarkText : kLightText;
    final footerBg = isDark ? kDarkSurface : kLightSurface;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // Header
          Container(
            color: headerColor,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: textColor),
                      onPressed: () {
                        widget.onBack?.call();
                        Navigator.of(context).pop();
                      },
                    ),
                    _api.resolveMediaUrl(_conv.otherUser.avatar).isNotEmpty
                        ? CircleAvatar(
                            radius: 18,
                            backgroundImage: CachedNetworkImageProvider(
                                _api.resolveMediaUrl(_conv.otherUser.avatar)),
                          )
                        : CircleAvatar(
                            radius: 18,
                            backgroundColor: isDark ? kBrandGreen : Colors.white24,
                            child: Text(
                              _conv.otherUser.initials,
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                          ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _conv.otherUser.displayName,
                            style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 15),
                          ),
                          Text(
                            _isOnline ? 'online' : 'offline',
                            style: TextStyle(
                                color:
                                    _isOnline ? Colors.greenAccent : subColor,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.call_outlined, color: textColor),
                      onPressed: () =>
                          _showSnack('🎙️ Voice call — Coming soon!'),
                    ),
                    IconButton(
                      icon: Icon(Icons.videocam_outlined, color: textColor),
                      onPressed: () =>
                          _showSnack('📹 Video call — Coming soon!'),
                    ),
                    IconButton(
                      icon: Icon(Icons.more_vert, color: textColor),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Messages
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: kBrandGreen))
                : GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: RefreshIndicator(
                      onRefresh: _loadMessages,
                      color: kBrandGreen,
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final msg = _messages[i];
                          return MessageBubble(
                            message: msg,
                            isMine: msg.senderId == _auth.me?.id,
                            apiBase: _auth.apiBase,
                            onReact: (emoji) => _sendReaction(msg.id, emoji),
                            onEdit: msg.senderId == _auth.me?.id &&
                                    msg.messageType == 'text' &&
                                    !msg.optimistic
                                ? () {
                                    setState(() {
                                      _editingMessage = msg;
                                      _msgCtrl.text = msg.text ?? '';
                                    });
                                    _focusNode.requestFocus();
                                  }
                                : null,
                            myUserId: _auth.me?.id,
                          );
                        },
                      ),
                    ),
                  ),
          ),

          // Typing indicator
          if (_isTyping)
            Container(
              color: bgColor,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              alignment: Alignment.centerLeft,
              child: Text('typing...',
                  style: TextStyle(
                      color: isDark ? kDarkSubText : kLightSubText,
                      fontSize: 12,
                      fontStyle: FontStyle.italic)),
            ),

          if (_isRecording)
            Container(
              color: footerBg,
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? kDarkInput : const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mic_rounded,
                        color: Colors.redAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Recording ${_formatRecordDuration(_recordDuration)}',
                      style: TextStyle(
                        color: isDark ? kDarkText : kLightText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Editing Indicator
          if (_editingMessage != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              color: isDark ? kDarkSurface : const Color(0xFFEBEBEB),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: kBrandGreen, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Editing message',
                          style: TextStyle(
                              color: kBrandGreen,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _editingMessage!.text ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: isDark ? kDarkSubText : kLightSubText,
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelEditing,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          color: isDark ? kDarkSubText : kLightSubText,
                          size: 20),
                    ),
                  ),
                ],
              ),
            ),

          // Footer
          Container(
            color: footerBg,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Attach menu
                  _AttachButton(onPickImage: _pickImage),

                  // Input
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? kDarkInput : const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _msgCtrl,
                        focusNode: _focusNode,
                        style: TextStyle(color: inputTextColor, fontSize: 14),
                        onChanged: _onTypingInput,
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: 'Type a message…',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          hintStyle: TextStyle(
                              color: isDark ? kDarkSubText : kLightSubText),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 6),

                  // Send / Record button
                  ListenableBuilder(
                    listenable: _msgCtrl,
                    builder: (_, __) {
                      final hasText = _msgCtrl.text.trim().isNotEmpty;
                      return GestureDetector(
                        onLongPressStart:
                            hasText ? null : (_) => _startRecording(),
                        onLongPressUp: hasText ? null : () => _stopRecording(),
                        onLongPressEnd:
                            hasText ? null : (_) => _stopRecording(),
                        onLongPressCancel:
                            hasText ? null : () => _stopRecording(),
                        child: InkWell(
                          onTap: _isRecording
                              ? null
                              : hasText
                                  ? _sendMessage
                                  : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44,
                            height: 44,
                            decoration: const BoxDecoration(
                              color: kBrandGreen,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isRecording
                                  ? Icons.stop_rounded
                                  : hasText
                                      ? Icons.send_rounded
                                      : Icons.mic_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachButton extends StatefulWidget {
  final VoidCallback onPickImage;
  const _AttachButton({required this.onPickImage});

  @override
  State<_AttachButton> createState() => _AttachButtonState();
}

class _AttachButtonState extends State<_AttachButton> {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.attach_file, color: kDarkSubText),
      onSelected: (v) {
        if (v == 'image') widget.onPickImage();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'image',
          child: Row(children: [
            Icon(Icons.image_outlined, color: kBrandGreen),
            SizedBox(width: 8),
            Text('Photo'),
          ]),
        ),
      ],
    );
  }
}
