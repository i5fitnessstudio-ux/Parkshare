/// Inbox domain row -> JSON mapping (backend).
Map<String, dynamic> conversationRowToJson(
  Map<String, dynamic> row, {
  required Map<String, dynamic>? otherPartyRow,
  String? parkingName,
  String? lastMessage,
  int unreadCount = 0,
  DateTime? lastMessageAt,
}) {
  return {
    'id': row['id']?.toString() ?? '',
    'userId': row['user_id']?.toString() ?? '',
    'ownerId': row['owner_id']?.toString() ?? '',
    'parkingId': row['parking_id']?.toString(),
    'parkingName': parkingName,
    'bookingId': row['booking_id']?.toString(),
    'lastMessage': lastMessage,
    'lastMessageAt': lastMessageAt?.toIso8601String(),
    'unreadCount': unreadCount,
    'otherParty': otherPartyRow == null
        ? null
        : {
            'id': otherPartyRow['id']?.toString() ?? '',
            'name': otherPartyRow['name']?.toString() ?? '',
            'role': otherPartyRow['role']?.toString() ?? '',
          },
    'createdAt': (row['created_at'] as DateTime?)?.toIso8601String() ?? '',
  };
}

Map<String, dynamic> messageRowToJson(Map<String, dynamic> row) {
  return {
    'id': row['id']?.toString() ?? '',
    'conversationId': row['conversation_id']?.toString() ?? '',
    'senderId': row['sender_id']?.toString() ?? '',
    'body': row['body']?.toString() ?? '',
    'readAt': (row['read_at'] as DateTime?)?.toIso8601String(),
    'createdAt': (row['created_at'] as DateTime?)?.toIso8601String() ?? '',
  };
}
