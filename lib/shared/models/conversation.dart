/// Inbox domain models: conversations + messages.
class ConversationParty {
  final String id;
  final String name;
  final String role;
  const ConversationParty({
    required this.id,
    required this.name,
    this.role = '',
  });
}

class Conversation {
  final String id;
  final String userId;
  final String ownerId;
  final String? parkingId;
  final String? parkingName;
  final String? bookingId;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final ConversationParty? otherParty;
  final DateTime createdAt;

  const Conversation({
    required this.id,
    required this.userId,
    required this.ownerId,
    this.parkingId,
    this.parkingName,
    this.bookingId,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.otherParty,
    required this.createdAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final partyJson = json['otherParty'] as Map<String, dynamic>?;
    return Conversation(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      parkingId: json['parkingId']?.toString(),
      parkingName: json['parkingName']?.toString(),
      bookingId: json['bookingId']?.toString(),
      lastMessage: json['lastMessage']?.toString(),
      lastMessageAt: DateTime.tryParse(json['lastMessageAt']?.toString() ?? ''),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      otherParty: partyJson == null
          ? null
          : ConversationParty(
              id: partyJson['id']?.toString() ?? '',
              name: partyJson['name']?.toString() ?? '',
              role: partyJson['role']?.toString() ?? '',
            ),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime? readAt;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    this.readAt,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id']?.toString() ?? '',
    conversationId: json['conversationId']?.toString() ?? '',
    senderId: json['senderId']?.toString() ?? '',
    body: json['body']?.toString() ?? '',
    readAt: DateTime.tryParse(json['readAt']?.toString() ?? ''),
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
  );
}
