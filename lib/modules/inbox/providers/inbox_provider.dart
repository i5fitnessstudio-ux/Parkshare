import 'package:flutter/foundation.dart';

import '../../../core/services/inbox_service.dart';
import '../../../shared/models/conversation.dart';

/// Inbox state: conversation list + the open chat thread.
class InboxProvider extends ChangeNotifier {
  final InboxService _service;

  List<Conversation> _conversations = [];
  List<ChatMessage> _messages = [];
  Conversation? _active;
  bool _loading = false;
  bool _sending = false;
  String? _error;

  InboxProvider({InboxService? service}) : _service = service ?? InboxService();

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  Conversation? get active => _active;
  bool get loading => _loading;
  bool get sending => _sending;
  String? get error => _error;

  int get totalUnread =>
      _conversations.fold(0, (sum, c) => sum + c.unreadCount);

  Future<void> loadConversations(String token) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _conversations = await _service.listConversations(token);
      _conversations.sort((a, b) {
        final ta = a.lastMessageAt ?? a.createdAt;
        final tb = b.lastMessageAt ?? b.createdAt;
        return tb.compareTo(ta);
      });
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Conversation> ensureConversation({
    required String token,
    required String parkingId,
    String? bookingId,
  }) async {
    final c = await _service.ensureConversation(
      token: token,
      parkingId: parkingId,
      bookingId: bookingId,
    );
    await loadConversations(token);
    return c;
  }

  Future<void> open({
    required String conversationId,
    required String token,
  }) async {
    _active = _find(conversationId);
    if (_active == null) {
      try {
        await loadConversations(token);
        _active = _find(conversationId);
      } catch (_) {}
    }
    _messages = [];
    notifyListeners();
    try {
      _messages = await _service.messages(conversationId, token: token);
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Conversation? _find(String id) {
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<ChatMessage?> send({
    required String conversationId,
    required String token,
    required String body,
  }) async {
    _sending = true;
    notifyListeners();
    try {
      final msg = await _service.sendMessage(
        conversationId: conversationId,
        token: token,
        body: body,
      );
      _messages = [..._messages, msg];
      _sending = false;
      notifyListeners();
      await loadConversations(token);
      return msg;
    } catch (e) {
      _error = e.toString();
      _sending = false;
      notifyListeners();
      return null;
    }
  }

  void clearThread() {
    _active = null;
    _messages = [];
    notifyListeners();
  }
}
