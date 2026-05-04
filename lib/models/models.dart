class User {
  final int id;
  final String username;
  final String? fullName;
  final String? email;
  final String? avatar;

  User(
      {required this.id,
      required this.username,
      this.fullName,
      this.email,
      this.avatar});

  String get displayName => fullName?.isNotEmpty == true ? fullName! : username;
  String get initials =>
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        username: json['username'] as String? ?? '',
        fullName: json['full_name'] as String?,
        email: json['email'] as String?,
        avatar: json['avatar'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'email': email,
        'avatar': avatar,
      };
}

class Message {
  final int id;
  final int? senderId;
  final String? text;
  final String messageType; // text, image, voice
  final String? file;
  final String? localFile; // Path to local file for optimistic preview
  final DateTime createdAt;
  String status; // sending, delivered, seen
  final bool isEdited;
  List<Reaction> reactions;
  bool optimistic;

  Message({
    required this.id,
    this.senderId,
    this.text,
    this.messageType = 'text',
    this.file,
    this.localFile,
    required this.createdAt,
    this.status = 'delivered',
    this.isEdited = false,
    this.reactions = const [],
    this.optimistic = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    DateTime dt;
    try {
      final raw = json['created_at'] as String? ?? '';
      dt = DateTime.parse(raw.endsWith('Z') ? raw : '${raw}Z').toLocal();
    } catch (_) {
      dt = DateTime.now();
    }
    final rawType = (json['message_type'] as String? ?? 'text').toLowerCase();
    final normalizedType =
        (rawType == 'audio' || rawType == 'voice_note') ? 'voice' : rawType;

    return Message(
      id: (json['id'] as num?)?.toInt() ?? 0,
      senderId: (json['sender_id'] as num?)?.toInt() ??
          (json['sender'] is Map
              ? (json['sender']['id'] as num?)?.toInt()
              : null),
      text: json['text'] as String?,
      messageType: normalizedType,
      file: json['file'] as String?,
      createdAt: dt,
      status: json['status'] as String? ?? 'delivered',
      isEdited: json['is_edited'] as bool? ?? false,
      reactions: (json['reactions'] as List<dynamic>? ?? [])
          .map((r) => Reaction.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

class Reaction {
  final String emoji;
  final dynamic userId;

  Reaction({required this.emoji, this.userId});

  factory Reaction.fromJson(Map<String, dynamic> json) => Reaction(
        emoji: json['emoji'] as String? ?? '',
        userId: json['user_id'] ?? json['user'],
      );
}

class Conversation {
  final int id;
  final User otherUser;
  final Message? lastMessage;
  int unreadCount;

  Conversation({
    required this.id,
    required this.otherUser,
    this.lastMessage,
    this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final otherUserJson = json['other_user'] as Map<String, dynamic>?;
    final lastMsgJson = json['last_message'] as Map<String, dynamic>?;
    return Conversation(
      id: (json['id'] as num).toInt(),
      otherUser: User.fromJson(otherUserJson ?? {}),
      lastMessage: lastMsgJson != null ? Message.fromJson(lastMsgJson) : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}
