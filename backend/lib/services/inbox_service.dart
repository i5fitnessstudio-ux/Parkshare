import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/conversation.dart';
import 'package:postgres/postgres.dart';

/// Inbox domain service: conversations + messages between owners and
/// vehicle users, always tied to a real booking.
class InboxService {
  /// Creates (or returns existing) conversation for a booking.
  /// Callers: owner "Message" or user "Message" on a booking.
  Future<Map<String, dynamic>> ensureConversation({
    required String requesterId,
    required String parkingId,
    String? bookingId,
  }) async {
    final parkingRow = await _parkingRow(parkingId);
    if (parkingRow == null) {
      throw ApiError.notFound('Parking listing not found.');
    }
    var ownerId = parkingRow['owner_id'].toString();

    // bookingId optional: without it the user may not have a booking yet;
    // still allow a conversation for an interested user.
    var userId = requesterId;
    if (bookingId != null && bookingId.isNotEmpty) {
      final b = await _bookingRow(bookingId);
      if (b == null) throw ApiError.notFound('Booking not found.');
      if (b['user_id'].toString() != requesterId &&
          b['owner_id'].toString() != requesterId) {
        throw ApiError.forbidden('You are not part of this booking.');
      }
      userId = b['user_id'].toString();
      ownerId = b['owner_id'].toString();
    } else {
      if (requesterId == ownerId) {
        throw ApiError.validation(
          'A booking reference is required to start a conversation.',
        );
      }
    }

    await Db.pool.withConnection((conn) async {
      // Upsert: unique (user_id, owner_id, booking_id).
      await conn.execute(
        Sql.named('''
        INSERT INTO conversations (user_id, owner_id, parking_id, booking_id)
        VALUES (@userId, @ownerId, @parkingId, @bookingId)
        ON CONFLICT (user_id, owner_id, booking_id) DO NOTHING
        '''),
        parameters: {
          'userId': userId,
          'ownerId': ownerId,
          'parkingId': parkingId,
          'bookingId': bookingId,
        },
      );
    });

    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT id FROM conversations
        WHERE user_id = @userId AND owner_id = @ownerId
          AND (booking_id = @bookingId OR booking_id IS NULL)
        ORDER BY created_at DESC LIMIT 1
        '''),
        parameters: {
          'userId': userId,
          'ownerId': ownerId,
          'bookingId': bookingId,
        },
      );
    });
    if (res.isEmpty) {
      throw ApiError.server('Conversation could not be created.');
    }
    return {'id': res.first.toColumnMap()['id'].toString()};
  }

  Future<List<Map<String, dynamic>>> listFor(String userId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT
          c.*,
          u.id AS other_id, u.name AS other_name, u.role AS other_role,
          COALESCE(p.parking_name, '') AS parking_name,
          lm.body AS last_body, lm.created_at AS last_at,
          (SELECT COUNT(*) FROM messages m
            WHERE m.conversation_id = c.id
              AND m.sender_id <> @me AND m.read_at IS NULL) AS unread
        FROM conversations c
        JOIN users u
          ON u.id = (CASE WHEN c.user_id = @me THEN c.owner_id ELSE c.user_id END)
        LEFT JOIN parking_listings p ON p.id = c.parking_id
        LEFT JOIN LATERAL (
          SELECT body, created_at FROM messages
          WHERE conversation_id = c.id
          ORDER BY created_at DESC LIMIT 1
        ) lm ON TRUE
        WHERE c.user_id = @me OR c.owner_id = @me
        ORDER BY c.last_message_at DESC
        '''),
        parameters: {'me': userId},
      );
    });

    return res.map((r) {
      final row = r.toColumnMap();
      final other = {
        'id': row['other_id']?.toString() ?? '',
        'name': row['other_name']?.toString() ?? '',
        'role': row['other_role']?.toString() ?? '',
      };
      return conversationRowToJson(
        row,
        otherPartyRow: other,
        parkingName: row['parking_name']?.toString(),
        lastMessage: row['last_body']?.toString(),
        lastMessageAt: row['last_at'] as DateTime?,
        unreadCount: (row['unread'] as int?) ?? 0,
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> messages(
    String conversationId, {
    required String viewerId,
  }) async {
    await _assertParticipant(conversationId, viewerId);
    // Mark messages from the other party as read.
    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('''
        UPDATE messages SET read_at = NOW()
        WHERE conversation_id = @cid AND sender_id <> @me AND read_at IS NULL
        '''),
        parameters: {'cid': conversationId, 'me': viewerId},
      );
    });
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT * FROM messages WHERE conversation_id = @cid
        ORDER BY created_at ASC
        '''),
        parameters: {'cid': conversationId},
      );
    });
    return res.map((r) => messageRowToJson(r.toColumnMap())).toList();
  }

  Future<Map<String, dynamic>> send({
    required String conversationId,
    required String senderId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) throw ApiError.validation('Message cannot be empty.');
    if (trimmed.length > 2000) {
      throw ApiError.validation('Message is too long (max 2000 characters).');
    }
    await _assertParticipant(conversationId, senderId);
    final row = await Db.pool.withConnection((conn) async {
      final res = await conn.execute(
        Sql.named('''
        INSERT INTO messages (conversation_id, sender_id, body)
        VALUES (@cid, @sender, @body)
        RETURNING *
        '''),
        parameters: {
          'cid': conversationId,
          'sender': senderId,
          'body': trimmed,
        },
      );
      await conn.execute(
        Sql.named('''
        UPDATE conversations SET last_message_at = NOW() WHERE id = @cid
        '''),
        parameters: {'cid': conversationId},
      );
      return res.first.toColumnMap();
    });
    return messageRowToJson(row);
  }

  // ---------------------------------------------------------------------
  Future<void> _assertParticipant(String conversationId, String userId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT id FROM conversations
        WHERE id = @cid AND (user_id = @me OR owner_id = @me)
        '''),
        parameters: {'cid': conversationId, 'me': userId},
      );
    });
    if (res.isEmpty) {
      throw ApiError.forbidden('You are not part of this conversation.');
    }
  }

  Future<Map<String, dynamic>?> _parkingRow(String id) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT * FROM parking_listings WHERE id = @id'),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  Future<Map<String, dynamic>?> _bookingRow(String id) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT * FROM bookings WHERE id = @id'),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }
}
