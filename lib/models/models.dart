class User {
  final int id;
  final String username;
  final String? fullName;
  final String? email;
  final String? avatar;
  final bool isOnline;

  User({
    required this.id,
    required this.username,
    this.fullName,
    this.email,
    this.avatar,
    this.isOnline = false,
  });

  String get displayName => fullName?.isNotEmpty == true ? fullName! : username;
  String get initials =>
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        fullName: json['full_name'] as String?,
        email: json['email'] as String?,
        avatar: json['avatar'] as String?,
        isOnline: json['is_online'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'email': email,
        'avatar': avatar,
        'is_online': isOnline,
      };
}

class Message {
  final int id;
  final int? senderId;
  final String? text;
  final String messageType; // text, image, voice
  final String? file;
  final String? localFile; // Path to local file for optimistic preview
  final DateTime? createdAt;
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
    this.createdAt,
    this.status = 'delivered',
    this.isEdited = false,
    this.reactions = const [],
    this.optimistic = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    try {
      final raw = json['created_at'] as String?;
      if (raw != null && raw.isNotEmpty) {
        dt = DateTime.parse(raw.endsWith('Z') ? raw : '${raw}Z').toLocal();
      } else {
        dt = null;
      }
    } catch (_) {
      dt = null;
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

class CallSession {
  final int id;
  final int conversationId;
  final User caller;
  final User receiver;
  final String callType; // voice, video
  final String status; // initiated, ongoing, ended, rejected, missed
  final DateTime? startTime;
  final DateTime? endTime;

  CallSession({
    required this.id,
    required this.conversationId,
    required this.caller,
    required this.receiver,
    required this.callType,
    required this.status,
    this.startTime,
    this.endTime,
  });

  factory CallSession.fromJson(Map<String, dynamic> json) {
    DateTime? st, et;
    try {
      if (json['start_time'] != null) st = DateTime.parse(json['start_time']);
      if (json['end_time'] != null) et = DateTime.parse(json['end_time']);
    } catch (_) {}

    final rawConv = json['conversation'];
    int convId = 0;
    if (rawConv is num) {
      convId = rawConv.toInt();
    } else if (rawConv is Map && rawConv.containsKey('id')) {
      convId = (rawConv['id'] as num?)?.toInt() ?? 0;
    }

    return CallSession(
      id: (json['id'] as num?)?.toInt() ?? 0,
      conversationId: convId,
      caller: User.fromJson(json['caller'] as Map<String, dynamic>? ?? {}),
      receiver: User.fromJson(json['receiver'] as Map<String, dynamic>? ?? {}),
      callType: json['call_type'] as String? ?? 'voice',
      status: json['status'] as String? ?? 'initiated',
      startTime: st,
      endTime: et,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation': conversationId,
      'caller': caller.toJson(),
      'receiver': receiver.toJson(),
      'call_type': callType,
      'status': status,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
    };
  }
}
