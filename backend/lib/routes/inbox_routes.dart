import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/inbox_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Inbox routes:
///   GET  /api/inbox/conversations
///   POST /api/inbox/conversations            (ensure/create with parkingId+bookingId)
///   GET  /api/inbox/conversations/{id}/messages
///   POST /api/inbox/conversations/{id}/messages
class InboxRoutes {
  final InboxService _service = InboxService();

  Handler get handler {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('Inbox route not found.');
      },
    );

    router.get(
      '/conversations',
      authMiddleware()((Request req) async {
        final list = await _service.listFor(userIdOf(req));
        return ApiResponse.ok({'conversations': list}, 'Conversations loaded.');
      }),
    );

    router.post(
      '/conversations',
      authMiddleware()((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final payload = await _service.ensureConversation(
          requesterId: userIdOf(req),
          parkingId: body['parkingId']?.toString() ?? '',
          bookingId: body['bookingId']?.toString(),
        );
        return ApiResponse.created(payload, 'Conversation ready.');
      }),
    );

    router.get('/conversations/<conversationId>/messages', (
      Request req,
      String conversationId,
    ) async {
      final me = await requireUserId(req);
      final list = await _service.messages(conversationId, viewerId: me);
      return ApiResponse.ok({'messages': list}, 'Messages loaded.');
    });

    router.post('/conversations/<conversationId>/messages', (
      Request req,
      String conversationId,
    ) async {
      final me = await requireUserId(req);
      final body = await readJsonBody(req) ?? {};
      final payload = await _service.send(
        conversationId: conversationId,
        senderId: me,
        body: body['body']?.toString() ?? '',
      );
      return ApiResponse.created(payload, 'Message sent.');
    });

    return router.call;
  }
}
