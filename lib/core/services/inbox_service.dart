import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/conversation.dart';

/// Inbox API: conversations + messages (owner & vehicle user).
class InboxService {
  final ApiClient _client;

  InboxService({ApiClient? client}) : _client = client ?? ApiClient();

  /// Creates (or reuses) a conversation for a booking.
  Future<Conversation> ensureConversation({
    required String token,
    required String parkingId,
    String? bookingId,
  }) async {
    final data = await _client.post(
      ApiConstants.conversations,
      body: {'parkingId': parkingId, 'bookingId': bookingId},
      token: token,
    ) as Map<String, dynamic>;
    return Conversation.fromJson(data);
  }

  Future<List<Conversation>> listConversations(String token) async {
    final data = await _client.get(
      ApiConstants.conversations,
      token: token,
    ) as Map<String, dynamic>;
    final raw = data['conversations'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(Conversation.fromJson)
        .toList();
  }

  Future<List<ChatMessage>> messages(
    String conversationId, {
    required String token,
  }) async {
    final data = await _client.get(
      ApiConstants.conversationMessages(conversationId),
      token: token,
    ) as Map<String, dynamic>;
    final raw = data['messages'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String token,
    required String body,
  }) async {
    final data = await _client.post(
      ApiConstants.conversationMessages(conversationId),
      body: {'body': body},
      token: token,
    ) as Map<String, dynamic>;
    return ChatMessage.fromJson(data);
  }
}
