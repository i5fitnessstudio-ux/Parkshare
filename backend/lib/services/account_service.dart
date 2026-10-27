import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/user.dart';
import 'package:parkshare_backend/storage/media_storage.dart';
import 'package:postgres/postgres.dart';

/// Self-service account deletion (vehicle user OR parking owner).
///
/// The flow is a single PostgreSQL transaction:
///   1. lock the `users` row `FOR UPDATE`;
///   2. re-authenticate the caller with the supplied password (bcrypt);
///   3. cancel active/future bookings on BOTH sides (the deleting account is
///      either the vehicle user or the parking owner of each booking);
///   4. delete the account's vehicles (the new `ON DELETE SET NULL` FK keeps
///      booking history intact) and collect their photo URLs for disk cleanup;
///   5. owner: hard-delete listings that have NO bookings (their media,
///      amenities and spaces cascade) and soft-delete + anonymize listings
///      that DO have bookings so history stays renderable;
///   6. delete conversations, refresh tokens and password-reset OTPs;
///   7. owner: scrub the UPI address from financial records
///      (`payments.upi_id`, `bookings.owner_upi_id_snapshot`);
///   8. anonymize the `users` row: name → "Deleted Vehicle User" /
///      "Deleted Parking Owner", email → `deleted+<id>@deleted.invalid`,
///      phone/upi → NULL, a FRESH random bcrypt hash, `is_active = FALSE`,
///      `deleted_at = NOW()`.
///
/// The row is never physically deleted, so every foreign key (bookings,
/// payments, history, conversations) stays valid: financial and booking
/// records are preserved for integrity while all personally identifiable
/// data is scrubbed.
///
/// Media files referenced by removed vehicles / hard-deleted listings are
/// deleted from disk AFTER the transaction commits, best effort.
class AccountService {
  AccountService({MediaStorage? mediaStorage})
    : _mediaStorage = mediaStorage ?? LocalMediaStorage();

  final MediaStorage _mediaStorage;

  /// Shown to the client after a successful deletion.
  static const String successMessage =
      'Your ParkShare account has been deleted successfully.';

  static final Random _random = Random.secure();

  /// Deletes the authenticated account.
  ///
  /// [userId] comes from the JWT (set by auth middleware), NEVER from the
  /// request body, and [password] re-authenticates the account. An account
  /// that is already deleted returns without error (idempotent).
  ///
  /// Throws [ApiError.forbidden] with a safe message when the password is
  /// wrong. SQL errors are never surfaced to the caller.
  Future<void> deleteAccount({
    required String userId,
    required String password,
  }) async {
    final mediaUrls = <String>[];

    await Db.pool.withConnection((conn) async {
      await conn.runTx((tx) async {
        final locked = await tx.execute(
          Sql.named('''
          SELECT id, name, role, password_hash, is_active, deleted_at
          FROM users
          WHERE id = @uid
          FOR UPDATE
          '''),
          parameters: {'uid': userId},
        );
        if (locked.isEmpty) return; // account does not exist -> already gone
        final row = locked.first.toColumnMap();
        if (row['deleted_at'] != null) {
          return; // already deleted -> idempotent success
        }

        final passwordHash = row['password_hash'] as String?;
        if (passwordHash == null ||
            !BCrypt.checkpw(password, passwordHash)) {
          throw ApiError.forbidden('Incorrect password. Please try again.');
        }

        final role = row['role'].toString();
        final isUser = role == UserRole.user;

        // ---- 1. Cancel active / future bookings on both sides ------------
        // REQUESTED / ACCEPTED / PAYMENT_PENDING / COD_PENDING / CONFIRMED /
        // ACTIVE -> CANCELLED. The slot is released (parking_space_id = NULL)
        // so cancelled bookings never block capacity; COMPLETED / REJECTED /
        // CANCELLED bookings are left untouched as historical records.
        final cancelled = await tx.execute(
          Sql.named('''
          UPDATE bookings
          SET status = 'CANCELLED', parking_space_id = NULL, updated_at = NOW()
          WHERE (user_id = @uid OR owner_id = @uid)
            AND status IN (
              'REQUESTED', 'ACCEPTED', 'PAYMENT_PENDING', 'COD_PENDING',
              'CONFIRMED', 'ACTIVE'
            )
          RETURNING id
          '''),
          parameters: {'uid': userId},
        );
        for (final r in cancelled) {
          await tx.execute(
            Sql.named('''
            INSERT INTO booking_status_history (booking_id, status)
            VALUES (@bookingId, 'CANCELLED')
            '''),
            parameters: {'bookingId': r.toColumnMap()['id'].toString()},
          );
        }

        // ---- 2. Collect media URLs (inside the tx, before rows vanish) ----
        if (isUser) {
          final photos = await tx.execute(
            Sql.named('''
            SELECT photo_url FROM vehicles WHERE user_id = @uid
            '''),
            parameters: {'uid': userId},
          );
          for (final r in photos) {
            final url = r.toColumnMap()['photo_url']?.toString();
            if (url != null && url.isNotEmpty) mediaUrls.add(url);
          }
        } else {
          // Only media of ZERO-booking listings (which get hard-deleted) is
          // removed. Soft-deleted listings keep their photos on disk so
          // historical bookings still render them.
          final media = await tx.execute(
            Sql.named('''
            SELECT pm.url
            FROM parking_media pm
            JOIN parking_listings pl ON pl.id = pm.parking_id
            WHERE pl.owner_id = @uid
              AND pl.deleted_at IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM bookings b WHERE b.parking_id = pl.id
              )
            '''),
            parameters: {'uid': userId},
          );
          for (final r in media) {
            mediaUrls.add(r.toColumnMap()['url'].toString());
          }
        }

        // ---- 3. Vehicle user: delete their vehicles -----------------------
        // bookings.vehicle_id references vehicles ON DELETE SET NULL
        // (migration 007), so history and statuses survive the deletion.
        if (isUser) {
          await tx.execute(
            Sql.named('DELETE FROM vehicles WHERE user_id = @uid'),
            parameters: {'uid': userId},
          );
        }

        // ---- 4. Owner: listings -------------------------------------------
        if (!isUser) {
          // Hard-delete listings that never had a booking (media, amenities
          // and spaces cascade). A listing with ANY booking row is kept.
          await tx.execute(
            Sql.named('''
            DELETE FROM parking_listings
            WHERE owner_id = @uid
              AND deleted_at IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM bookings b WHERE b.parking_id = parking_listings.id
              )
            '''),
            parameters: {'uid': userId},
          );
          // Soft-delete + anonymize listings that have booking history.
          await tx.execute(
            Sql.named('''
            UPDATE parking_listings
            SET parking_name = 'Deleted Parking Listing',
                address = '',
                city = NULL, state = NULL, pincode = NULL, landmark = NULL,
                description = '', conditions = '',
                available = FALSE,
                deleted_at = NOW(),
                updated_at = NOW()
            WHERE owner_id = @uid
              AND deleted_at IS NULL
              AND EXISTS (
                SELECT 1 FROM bookings b WHERE b.parking_id = parking_listings.id
              )
            '''),
            parameters: {'uid': userId},
          );
        }

        // ---- 5. Conversations, sessions, recovery material ----------------
        await tx.execute(
          Sql.named(
            'DELETE FROM conversations WHERE user_id = @uid OR owner_id = @uid',
          ),
          parameters: {'uid': userId},
        );
        await tx.execute(
          Sql.named('DELETE FROM refresh_tokens WHERE user_id = @uid'),
          parameters: {'uid': userId},
        );
        await tx.execute(
          Sql.named('DELETE FROM password_reset_otps WHERE user_id = @uid'),
          parameters: {'uid': userId},
        );

        // ---- 6. Owner: scrub UPI address from financial records -----------
        if (!isUser) {
          await tx.execute(
            Sql.named(
              'UPDATE payments SET upi_id = NULL WHERE owner_id = @uid',
            ),
            parameters: {'uid': userId},
          );
          await tx.execute(
            Sql.named(
              'UPDATE bookings SET owner_upi_id_snapshot = NULL WHERE owner_id = @uid',
            ),
            parameters: {'uid': userId},
          );
        }

        // ---- 7. Anonymize the users row -----------------------------------
        final deletedName = isUser
            ? 'Deleted Vehicle User'
            : 'Deleted Parking Owner';
        final deletedEmail = 'deleted+$userId@deleted.invalid';
        final randomHash = BCrypt.hashpw(_randomNonce(), BCrypt.gensalt());
        await tx.execute(
          Sql.named('''
          UPDATE users
          SET name = @name,
              email = @email,
              phone = NULL,
              upi_id = NULL,
              password_hash = @hash,
              is_active = FALSE,
              deleted_at = NOW(),
              updated_at = NOW()
          WHERE id = @uid
          '''),
          parameters: {
            'name': deletedName,
            'email': deletedEmail,
            'hash': randomHash,
            'uid': userId,
          },
        );
      });
    });

    // After the transaction committed: best-effort disk cleanup. A failure
    // here must never fail the request — the data is already gone from the
    // database and a stale file is a harmless orphan.
    for (final url in mediaUrls) {
      await _mediaStorage.delete(url);
    }
  }

  /// A random, never-stored value hashed into the account's new
  /// `password_hash`, guaranteeing the old password can never authenticate
  /// against a deleted account.
  String _randomNonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}