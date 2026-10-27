import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/parking_service.dart';
import 'package:parkshare_backend/services/payout_details_cipher.dart';
import 'package:postgres/postgres.dart';

/// Settlement states for one owner earning (`payment_transfers`).
class SettlementStatus {
  SettlementStatus._();
  static const String pending = 'PENDING';
  static const String settled = 'SETTLED';

  /// Only an order created with live Razorpay keys may be paid out. `test`,
  /// null (legacy/unrecorded) and any unknown value are audit-only.
  static bool isLiveRazorpayMode(String? mode) =>
      (mode ?? '').trim().toLowerCase() == 'live';

  /// True when a status means "already paid out to the owner".
  static bool isSettled(String? status) =>
      (status ?? '').trim().toUpperCase() == settled;
}

/// Manual (out-of-band) owner settlement.
///
/// Razorpay Route is NOT activated, so ParkShare cannot move an owner's share
/// through Razorpay. Until Route is live an administrator pays the owner
/// outside Razorpay and records that payout here.
///
/// This service ONLY flips the already-existing `payment_transfers` ledger row
/// from PENDING to SETTLED (plus audit fields). It is a hard boundary:
///   * it never calls Razorpay and never enables Route;
///   * it never writes `razorpay_transfer_id` (that column stays NULL for a
///     manual payout — a manual payout is NOT a Razorpay transfer);
///   * it determines the owner from the ledger row itself, never from input;
///   * it is idempotent — one earning can be settled at most once, and a
///     repeat call returns the existing record without changing anything.
class AdminSettlementService {
  /// Lists owner earnings that are eligible for a real payout.
  ///
  /// This is the missing back-office half of manual settlement: without it an
  /// administrator had no server-provided queue of what to pay or which owner
  /// it belongs to. It deliberately returns only masked bank metadata; the
  /// full destination is exposed by [getPayoutDestination] for the single row
  /// being paid.
  ///
  /// Test-mode Razorpay rows are excluded here exactly as they are rejected by
  /// [markSettled], so the queue can never invite a payout that settlement will
  /// later refuse.
  Future<List<Map<String, dynamic>>> listPending({int limit = 100}) async {
    final safeLimit = limit.clamp(1, 500);
    final rows = await Db.pool.withConnection((conn) async {
      final res = await conn.execute(
        Sql.named('''
        SELECT pt.id, pt.owner_id, pt.booking_id, pt.owner_amount_paise,
               pt.currency, pt.created_at,
               p.payment_method, p.razorpay_mode,
               u.name AS owner_name, u.phone AS owner_phone,
               u.email AS owner_email,
               opa.legal_name, opa.account_holder_name, opa.bank_last4,
               opa.razorpay_settlement_enabled,
               (opa.payout_account_number_encrypted IS NOT NULL
                 AND opa.payout_ifsc_encrypted IS NOT NULL)
                 AS payout_details_available,
               opa.payout_details_updated_at
        FROM payment_transfers pt
        JOIN payments p ON p.id = pt.payment_id
        JOIN users u ON u.id = pt.owner_id
        LEFT JOIN owner_payment_accounts opa ON opa.owner_id = pt.owner_id
        WHERE pt.settlement_status = 'PENDING'
          AND (
            p.payment_method <> 'RAZORPAY'
            OR LOWER(COALESCE(p.razorpay_mode, '')) = 'live'
          )
        ORDER BY pt.created_at ASC
        LIMIT @limit
        '''),
        parameters: {'limit': safeLimit},
      );
      return res.map((r) => r.toColumnMap()).toList();
    });

    return [
      for (final row in rows)
        {
          'paymentTransferId': row['id'].toString(),
          'ownerId': row['owner_id']?.toString(),
          'ownerName': row['owner_name']?.toString() ?? '',
          'ownerPhone': row['owner_phone']?.toString() ?? '',
          'ownerEmail': row['owner_email']?.toString() ?? '',
          'bookingId': row['booking_id']?.toString(),
          'ownerAmountPaise': _intOr(row['owner_amount_paise'], 0),
          'currency': row['currency']?.toString() ?? 'INR',
          'paymentMethod': row['payment_method']?.toString() ?? '',
          'razorpayMode': row['razorpay_mode']?.toString(),
          'createdAt': row['created_at']?.toString(),
          'legalName': row['legal_name']?.toString() ?? '',
          'accountHolderName': row['account_holder_name']?.toString() ?? '',
          'bankLast4': row['bank_last4']?.toString() ?? '',
          'payoutDetailsAvailable': row['payout_details_available'] == true,
          'payoutDetailsUpdatedAt': row['payout_details_updated_at']
              ?.toString(),
          'razorpaySettlementEnabled':
              row['razorpay_settlement_enabled'] == true,
        },
    ];
  }

  /// Returns the full payout destination for ONE pending earning.
  ///
  /// SECURITY: this is the only code that decrypts an owner's bank account and
  /// IFSC. It is reachable only behind the ADMIN role. The response must never
  /// be logged, cached, stored in analytics or sent to the owner app. It exists
  /// so the administrator can execute the actual NEFT/IMPS/UPI payout before
  /// recording the reference with [markSettled].
  ///
  /// Returns a conflict when the owner has not re-submitted the setup required
  /// by migration 012 (older rows stored only last-4) or when decryption fails.
  Future<Map<String, dynamic>> getPayoutDestination({
    required String transferId,
    required String adminUserId,
  }) async {
    if (!ParkingService.isUuid(transferId)) {
      throw ApiError.validation('A valid settlement id is required.');
    }
    if (!ParkingService.isUuid(adminUserId)) {
      throw ApiError.unauthorized('A valid admin identity is required.');
    }

    final row = await Db.pool.withConnection((conn) async {
      final res = await conn.execute(
        Sql.named('''
        SELECT pt.id, pt.owner_id, pt.booking_id, pt.owner_amount_paise,
               pt.settlement_status,
               p.payment_method, p.razorpay_mode,
               u.name AS owner_name, u.phone AS owner_phone,
               u.email AS owner_email,
               opa.legal_name, opa.account_type, opa.account_holder_name,
               opa.bank_last4, opa.payout_account_number_encrypted,
               opa.payout_ifsc_encrypted, opa.payout_details_updated_at
        FROM payment_transfers pt
        JOIN payments p ON p.id = pt.payment_id
        JOIN users u ON u.id = pt.owner_id
        LEFT JOIN owner_payment_accounts opa ON opa.owner_id = pt.owner_id
        WHERE pt.id = @id
        '''),
        parameters: {'id': transferId},
      );
      return res.isEmpty ? null : res.first.toColumnMap();
    });
    if (row == null) {
      throw ApiError.notFound('Settlement record not found.');
    }
    if (SettlementStatus.isSettled(row['settlement_status']?.toString())) {
      throw ApiError.conflict('This earning has already been settled.');
    }

    final paymentMethod = (row['payment_method']?.toString() ?? '')
        .toUpperCase();
    if (paymentMethod == 'RAZORPAY' &&
        !SettlementStatus.isLiveRazorpayMode(
          row['razorpay_mode']?.toString(),
        )) {
      throw ApiError.conflict(
        'Test-mode earnings are audit-only and have no payout destination.',
      );
    }

    final encryptedAccount =
        row['payout_account_number_encrypted']?.toString() ?? '';
    final encryptedIfsc = row['payout_ifsc_encrypted']?.toString() ?? '';
    if (encryptedAccount.isEmpty || encryptedIfsc.isEmpty) {
      throw ApiError.conflict(
        'The owner has not re-submitted full payout details. Ask the owner to '
        'open Payments > Settlement setup and save the bank account again.',
      );
    }

    final String accountNumber;
    final String ifsc;
    try {
      accountNumber = PayoutDetailsCipher.decrypt(encryptedAccount);
      ifsc = PayoutDetailsCipher.decrypt(encryptedIfsc);
    } on PayoutDetailsCipherException {
      throw ApiError.conflict(
        'Stored payout details could not be decrypted. Ask the owner to '
        're-submit the settlement setup before paying.',
      );
    }

    return {
      'paymentTransferId': row['id'].toString(),
      'ownerId': row['owner_id']?.toString(),
      'ownerName': row['owner_name']?.toString() ?? '',
      'ownerPhone': row['owner_phone']?.toString() ?? '',
      'ownerEmail': row['owner_email']?.toString() ?? '',
      'bookingId': row['booking_id']?.toString(),
      'ownerAmountPaise': _intOr(row['owner_amount_paise'], 0),
      'legalName': row['legal_name']?.toString() ?? '',
      'accountType': row['account_type']?.toString() ?? '',
      'accountHolderName': row['account_holder_name']?.toString() ?? '',
      'bankLast4': row['bank_last4']?.toString() ?? '',
      'bankAccountNumber': accountNumber,
      'ifscCode': ifsc,
      'detailsUpdatedAt': row['payout_details_updated_at']?.toString(),
    };
  }

  /// Marks one owner earning as settled.
  ///
  /// [transferId] is the `payment_transfers.id`. [adminUserId] must be the
  /// authenticated admin's id (from the verified JWT) — it is recorded for
  /// audit and is never used to decide WHICH owner is paid.
  ///
  /// [reference] is an optional external payout reference (UTR / bank ref) and
  /// [note] an optional free-text note. `settledAt` is generated server-side.
  Future<Map<String, dynamic>> markSettled({
    required String transferId,
    required String adminUserId,
    String reference = '',
    String note = '',
  }) async {
    // Validation happens BEFORE any database work, so a malformed request can
    // never reach a query (and is cheaply unit-testable).
    if (!ParkingService.isUuid(transferId)) {
      throw ApiError.validation('A valid settlement id is required.');
    }
    if (!ParkingService.isUuid(adminUserId)) {
      throw ApiError.unauthorized('A valid admin identity is required.');
    }
    final ref = reference.trim();
    final cleanNote = note.trim();
    if (ref.length > 120) {
      throw ApiError.validation(
        'Manual payout reference is too long (max 120 characters).',
      );
    }
    if (cleanNote.length > 500) {
      throw ApiError.validation('Note is too long (max 500 characters).');
    }

    return Db.pool.withConnection((conn) async {
      return conn.runTx((tx) async {
        // Lock the ledger row for the duration of the settlement so two admins
        // cannot settle the same earning twice.
        final current = await tx.execute(
          Sql.named('''
          SELECT pt.id, pt.owner_id, pt.booking_id, pt.settlement_status,
                 pt.owner_amount_paise, pt.settled_at,
                 pt.manual_payout_reference, pt.manual_payout_note,
                 p.payment_method, p.razorpay_mode
          FROM payment_transfers pt
          JOIN payments p ON p.id = pt.payment_id
          WHERE pt.id = @id
          FOR UPDATE OF pt
          '''),
          parameters: {'id': transferId},
        );
        if (current.isEmpty) {
          throw ApiError.notFound('Settlement record not found.');
        }
        final row = current.first.toColumnMap();

        // A manual payout is real money leaving the company. Never allow it
        // for a Razorpay test-mode payment (or a legacy row whose mode was
        // never recorded). This check is independent of the current server
        // mode, so switching to live keys cannot make old test earnings
        // settleable.
        final paymentMethod = (row['payment_method']?.toString() ?? '')
            .toUpperCase();
        if (paymentMethod == 'RAZORPAY' &&
            !SettlementStatus.isLiveRazorpayMode(
              row['razorpay_mode']?.toString(),
            )) {
          throw ApiError.conflict(
            'Test-mode Razorpay earnings are audit-only and cannot be '
            'settled. Legacy payments with no recorded mode are also '
            'blocked until reconciled.',
          );
        }

        // Idempotency: an already-settled earning is returned untouched. We do
        // NOT overwrite the original payout reference/note/settled_at.
        if (SettlementStatus.isSettled(row['settlement_status']?.toString())) {
          return _view(row, alreadySettled: true);
        }

        // A settlement is an assertion that money actually left the company.
        // Without an external reference (UTR / IMPS / UPI transaction id) there
        // is no evidence of that, so it must not be possible to clear the
        // ledger with an empty body.
        if (ref.isEmpty) {
          throw ApiError.validation(
            'A payout reference (UTR / bank / UPI transaction id) is required '
            'before an earning can be marked settled.',
          );
        }

        final updated = await tx.execute(
          Sql.named('''
          UPDATE payment_transfers
          SET settlement_status = 'SETTLED',
              settled_at = NOW(),
              settled_by_admin_user_id = @admin,
              manual_payout_reference = NULLIF(@ref, ''),
              manual_payout_note = NULLIF(@note, ''),
              updated_at = NOW()
          WHERE id = @id
            AND settlement_status <> 'SETTLED'
          RETURNING id, owner_id, booking_id, settlement_status,
                    owner_amount_paise, settled_at, manual_payout_reference,
                    manual_payout_note
          '''),
          parameters: {
            'id': transferId,
            'admin': adminUserId,
            'ref': ref,
            'note': cleanNote,
          },
        );
        if (updated.isEmpty) {
          // Lost a race: somebody settled it between the SELECT and UPDATE.
          // Re-read and answer idempotently.
          final reread = await tx.execute(
            Sql.named('''
            SELECT id, owner_id, booking_id, settlement_status,
                   owner_amount_paise, settled_at, manual_payout_reference,
                   manual_payout_note
            FROM payment_transfers
            WHERE id = @id
            '''),
            parameters: {'id': transferId},
          );
          return _view(reread.first.toColumnMap(), alreadySettled: true);
        }
        return _view(updated.first.toColumnMap(), alreadySettled: false);
      });
    });
  }

  /// Owner-facing-safe view of one settlement row. No Admin/PII leakage; the
  /// owner id is included only so the caller can log which owner was credited.
  static Map<String, dynamic> _view(
    Map<String, dynamic> row, {
    required bool alreadySettled,
  }) {
    return {
      'paymentTransferId': row['id'].toString(),
      'ownerId': row['owner_id']?.toString(),
      'bookingId': row['booking_id']?.toString(),
      'settlementStatus':
          (row['settlement_status']?.toString() ?? SettlementStatus.pending)
              .toUpperCase(),
      'ownerAmountPaise': _intOr(row['owner_amount_paise'], 0),
      'settledAt': row['settled_at']?.toString(),
      'manualPayoutReference': row['manual_payout_reference']?.toString(),
      'alreadySettled': alreadySettled,
    };
  }

  static int _intOr(Object? value, int fallback) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
}
