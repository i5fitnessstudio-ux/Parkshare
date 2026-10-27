// DB-backed integration test for the whole money path:
//
//   online (Razorpay) -> booking PAID/CONFIRMED -> owner earning (PENDING)
//                      -> admin records a MANUAL payout -> SETTLED
//   cash on delivery  -> owner confirms cash -> booking CONFIRMED -> earning
//
// These are the parts the DB-free unit tests cannot reach (the state machine,
// the ledger, the uniqueness constraints and the idempotency guards), so this
// file exercises them against a REAL disposable PostgreSQL database.
//
// HOW TO RUN
// ----------
// The suite is SKIPPED unless a disposable database is named, so `dart test`
// stays green on a machine that has no database:
//
//   $env:PARKSHARE_TEST_DB_HOST='127.0.0.1'
//   $env:PARKSHARE_TEST_DB_PORT='5432'
//   $env:PARKSHARE_TEST_DB_NAME='parkshare'
//   $env:PARKSHARE_TEST_DB_USER='parkshare'
//   $env:PARKSHARE_TEST_DB_PASSWORD='...'
//   dart test test/integration/payment_flow_integration_test.dart
//
// The disposable database must be reachable; the suite applies every pending
// migration (001-012) itself before seeding. The rows this file creates are
// prefixed with `itest-` and deleted again in `tearDownAll`, so it never
// touches pre-existing data.
//
// AUDIT ITEM 3: the configuration is still the controlled test environment
// (test-only JWT secret, test-only Razorpay key secret, Route disabled). Only
// the database coordinates come from the environment.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/booking.dart';
import 'package:parkshare_backend/routes/api_router.dart';
import 'package:parkshare_backend/services/admin_settlement_service.dart';
import 'package:parkshare_backend/services/owner_payment_account_service.dart';
import 'package:parkshare_backend/services/payment_service.dart';
import 'package:parkshare_backend/services/payout_details_cipher.dart';
import 'package:parkshare_backend/services/razorpay_payment_service.dart';
import 'package:parkshare_backend/services/razorpay_service.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/test_env.dart';

/// The controlled configuration plus the disposable database coordinates.
Map<String, String>? _integrationOverrides() {
  final name = Platform.environment['PARKSHARE_TEST_DB_NAME'] ?? '';
  if (name.isEmpty) return null;
  return <String, String>{
    ...TestEnv.values,
    'DB_HOST': Platform.environment['PARKSHARE_TEST_DB_HOST'] ?? '127.0.0.1',
    'DB_PORT': Platform.environment['PARKSHARE_TEST_DB_PORT'] ?? '5432',
    'DB_NAME': name,
    'DB_USER': Platform.environment['PARKSHARE_TEST_DB_USER'] ?? 'parkshare',
    'DB_PASSWORD': Platform.environment['PARKSHARE_TEST_DB_PASSWORD'] ?? '',
  };
}

const String _ownerA = 'aaaaaaaa-0000-4000-8000-000000000001';
const String _ownerB = 'aaaaaaaa-0000-4000-8000-000000000002';
const String _driver = 'aaaaaaaa-0000-4000-8000-000000000003';
const String _admin = 'aaaaaaaa-0000-4000-8000-000000000004';
const String _parkingA = 'bbbbbbbb-0000-4000-8000-000000000001';
const String _parkingB = 'bbbbbbbb-0000-4000-8000-000000000002';
const String _spaceA = 'cccccccc-0000-4000-8000-000000000001';
const String _spaceB = 'cccccccc-0000-4000-8000-000000000002';
const String _spaceB2 = 'cccccccc-0000-4000-8000-000000000003';
const String _vehicle = 'dddddddd-0000-4000-8000-000000000001';
const String _bookingOnline = 'eeeeeeee-0000-4000-8000-000000000001';
const String _bookingCod = 'eeeeeeee-0000-4000-8000-000000000002';
const String _bookingAtomic = 'eeeeeeee-0000-4000-8000-000000000003';
const String _bookingFailed = 'eeeeeeee-0000-4000-8000-000000000004';
const String _atomicPayment = 'ffffffff-0000-4000-8000-000000000003';
const String _failedPayment = 'ffffffff-0000-4000-8000-000000000004';
const String _testPayment = 'ffffffff-0000-4000-8000-000000000001';
const String _testTransfer = 'ffffffff-0000-4000-8000-000000000002';

/// Offline Razorpay gateway for the integration test.
///
/// The verifier deliberately fetches the payment from Razorpay to prove it was
/// captured. The previous test used the REAL client, so it would either call
/// the internet with fake credentials or fail its assertions. This fake returns
/// only the entries the test registered, and refuses an unknown id exactly like
/// a 404 from the gateway.
class _FakeRazorpayGateway extends RazorpayService {
  final Map<String, Map<String, dynamic>> payments = {};

  @override
  bool get isConfigured => true;

  @override
  Future<Map<String, dynamic>> fetchPayment(String paymentId) async {
    final payment = payments[paymentId];
    if (payment == null) {
      throw RazorpayException(404, 'Payment not found');
    }
    return payment;
  }

  @override
  Future<Map<String, dynamic>> createTransfer({
    required String razorpayPaymentId,
    required int amountPaise,
    required String linkedAccountId,
    Map<String, String> notes = const {},
  }) async {
    throw StateError('Route must stay disabled in this test');
  }
}

/// HMAC-SHA256 hex, exactly as the Razorpay gateway signs.
String _hmacHex(String message, String secret) {
  final mac = Hmac(sha256, utf8.encode(secret));
  return mac
      .convert(utf8.encode(message))
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

Future<List<Map<String, dynamic>>> _query(
  String sql, [
  Map<String, Object?> parameters = const {},
]) async {
  return Db.pool.withConnection((conn) async {
    final res = await conn.execute(Sql.named(sql), parameters: parameters);
    return res.map((r) => r.toColumnMap()).toList();
  });
}

Future<int> _exec(
  String sql, [
  Map<String, Object?> parameters = const {},
]) async {
  return Db.pool.withConnection((conn) async {
    final res = await conn.execute(Sql.named(sql), parameters: parameters);
    return res.affectedRows;
  });
}

void main() {
  final overrides = _integrationOverrides();

  group(
    'DB-backed money path',
    () {
      late RazorpayPaymentService razorpay;
      late PaymentService payments;
      late AdminSettlementService settlement;
      late _FakeRazorpayGateway gateway;

      setUpAll(() async {
        Config.applyTestOverrides(overrides!);
        await Db.init();
        await Db.migrate();

        gateway = _FakeRazorpayGateway();
        razorpay = RazorpayPaymentService(razorpay: gateway);
        payments = PaymentService();
        settlement = AdminSettlementService();

        gateway.payments['itest-pay-1'] = {
          'id': 'itest-pay-1',
          'order_id': 'itest-order-1',
          'status': 'captured',
          'amount': 50000,
          'currency': 'INR',
        };

        // ---- seed -------------------------------------------------------
        await _exec(
          '''
          INSERT INTO users (id, name, email, phone, password_hash, role)
          VALUES
            (@ownerA, 'Owner A', 'itest-owner-a@test.invalid', '9000000001', 'x', 'owner'),
            (@ownerB, 'Owner B', 'itest-owner-b@test.invalid', '9000000002', 'x', 'owner'),
            (@driver, 'Driver', 'itest-driver@test.invalid', '9000000003', 'x', 'user'),
            (@admin,  'Admin',  'itest-admin@test.invalid',  '9000000004', 'x', 'admin')
          ''',
          {
            'ownerA': _ownerA,
            'ownerB': _ownerB,
            'driver': _driver,
            'admin': _admin,
          },
        );

        await _exec(
          '''
          INSERT INTO parking_listings (
            id, owner_id, parking_name, address, city, state, pincode,
            latitude, longitude, parking_type, length_m, width_m, height_m,
            vehicle_type, monthly_enabled, monthly_rent, available
          ) VALUES
            (@parkingA, @ownerA, 'itest Parking A', 'itest street A', 'Pune',
             'MH', '411001', 18.52, 73.85, 'NON_COVERED', 20, 20, 4, 'BOTH',
             TRUE, 500, TRUE),
            (@parkingB, @ownerB, 'itest Parking B', 'itest street B', 'Pune',
             'MH', '411002', 18.53, 73.86, 'NON_COVERED', 20, 20, 4, 'BOTH',
             TRUE, 800, TRUE)
          ''',
          {
            'parkingA': _parkingA,
            'ownerA': _ownerA,
            'ownerB': _ownerB,
            'parkingB': _parkingB,
          },
        );

        await _exec(
          '''
          INSERT INTO parking_spaces (
            id, parking_id, space_code, vehicle_type, length_m, width_m, height_m
          ) VALUES
            (@spaceA,  @parkingA, 'itest-A1', 'CAR', 20, 20, 4),
            (@spaceB,  @parkingB, 'itest-B1', 'CAR', 20, 20, 4),
            (@spaceB2, @parkingB, 'itest-B2', 'CAR', 20, 20, 4)
          ''',
          {
            'spaceA': _spaceA,
            'parkingA': _parkingA,
            'spaceB': _spaceB,
            'spaceB2': _spaceB2,
            'parkingB': _parkingB,
          },
        );

        await _exec(
          '''
          INSERT INTO vehicles (
            id, user_id, vehicle_type, brand, model, registration_number,
            length_m, width_m, height_m
          ) VALUES (
            @vehicle, @driver, 'CAR', 'itest', 'itest', 'itest-REG-001',
            4.5, 1.8, 1.6
          )
          ''',
          {'vehicle': _vehicle, 'driver': _driver},
        );

        // The online booking is ACCEPTED (the owner approved it) and is
        // waiting for the payment.
        await _exec(
          '''
          INSERT INTO bookings (
            id, parking_id, parking_space_id, user_id, owner_id, vehicle_id,
            rental_type, start_date, end_date, amount, status,
            payment_method, payment_status
          ) VALUES (
            @booking, @parkingA, @spaceA, @driver, @ownerA, @vehicle,
            'MONTHLY', CURRENT_DATE, CURRENT_DATE + INTERVAL '30 days',
            500, 'ACCEPTED', 'RAZORPAY', 'PENDING'
          )
          ''',
          {
            'booking': _bookingOnline,
            'parkingA': _parkingA,
            'spaceA': _spaceA,
            'driver': _driver,
            'ownerA': _ownerA,
            'vehicle': _vehicle,
          },
        );

        // The COD booking is ACCEPTED too; the flow below switches it to cash.
        await _exec(
          '''
          INSERT INTO bookings (
            id, parking_id, parking_space_id, user_id, owner_id, vehicle_id,
            rental_type, start_date, end_date, amount, status,
            payment_method, payment_status
          ) VALUES (
            @booking, @parkingB, @spaceB, @driver, @ownerB, @vehicle,
            'MONTHLY', CURRENT_DATE, CURRENT_DATE + INTERVAL '30 days',
            800, 'ACCEPTED', 'RAZORPAY', 'PENDING'
          )
          ''',
          {
            'booking': _bookingCod,
            'parkingB': _parkingB,
            'spaceB': _spaceB,
            'driver': _driver,
            'ownerB': _ownerB,
            'vehicle': _vehicle,
          },
        );
      });

      tearDownAll(() async {
        if (overrides == null) return;
        // Only rows this file created (all ids are known constants).
        await _exec(
          'DELETE FROM payment_transfers WHERE owner_id IN (@a, @b)',
          {'a': _ownerA, 'b': _ownerB},
        );
        await _exec(
          'DELETE FROM razorpay_webhook_events WHERE event_key LIKE @p',
          {'p': 'itest-%'},
        );
        await _exec('DELETE FROM payments WHERE booking_id IN (@x, @y)', {
          'x': _bookingOnline,
          'y': _bookingCod,
        });
        await _exec('DELETE FROM bookings WHERE id IN (@x, @y)', {
          'x': _bookingOnline,
          'y': _bookingCod,
        });
        await _exec('DELETE FROM owner_payment_accounts WHERE owner_id = @a', {
          'a': _ownerA,
        });
        await _exec('DELETE FROM parking_spaces WHERE id IN (@a, @b, @c)', {
          'a': _spaceA,
          'b': _spaceB,
          'c': _spaceB2,
        });
        await _exec('DELETE FROM parking_listings WHERE id IN (@a, @b)', {
          'a': _parkingA,
          'b': _parkingB,
        });
        await _exec('DELETE FROM vehicles WHERE id = @v', {'v': _vehicle});
        await _exec('DELETE FROM users WHERE id IN (@a, @b, @c, @d)', {
          'a': _ownerA,
          'b': _ownerB,
          'c': _driver,
          'd': _admin,
        });
        await Db.close();
      });

      // ---------------------------------------------------------------
      // Item 4 — the backend derives the owner; Flutter is never trusted
      // ---------------------------------------------------------------
      group('item 4: the owner is derived server-side', () {
        test(
          'a verified payment credits the booking owner, never a client id',
          () async {
            // The payment row is created server-side by `createOrder`; here it
            // is inserted directly with the OWNER THAT THE BOOKING HAS, so a
            // mismatch with the client is impossible by construction.
            await _exec(
              '''
              INSERT INTO payments (
                booking_id, user_id, owner_id, amount, amount_paise, currency,
                payment_method, provider, payment_status,
                razorpay_order_id, verification_status, razorpay_mode,
                reference, updated_at
              ) VALUES (
                @booking, @user, @owner, 500, 50000, 'INR',
                'RAZORPAY', 'razorpay', 'CREATED',
                'itest-order-1', 'UNVERIFIED', 'live', 'itest-receipt-1', NOW()
              )
              ''',
              {'booking': _bookingOnline, 'user': _driver, 'owner': _ownerA},
            );

            const orderId = 'itest-order-1';
            const paymentId = 'itest-pay-1';
            final signature = _hmacHex(
              '$orderId|$paymentId',
              Config.razorpayKeySecret,
            );

            final booking = await razorpay.verifyCheckout(
              bookingId: _bookingOnline,
              userId: _driver,
              razorpayOrderId: orderId,
              razorpayPaymentId: paymentId,
              razorpaySignature: signature,
            );
            expect(booking['status'], BookingStatus.confirmed);
            expect(booking['paymentStatus'], PaymentStatus.success);

            // The ledger row points at the booking's owner.
            final transfers = await _query(
              'SELECT * FROM payment_transfers WHERE booking_id = @b',
              {'b': _bookingOnline},
            );
            expect(transfers.length, 1);
            expect(transfers.first['owner_id'].toString(), _ownerA);
            expect(transfers.first['gross_amount_paise'], 50000);
            expect(transfers.first['owner_amount_paise'], 50000);
            expect(transfers.first['settlement_status'], 'PENDING');
            expect(transfers.first['transfer_status'], 'PENDING');
            // Route is disabled: no transfer id may ever be written.
            expect(transfers.first['razorpay_transfer_id'], isNull);
          },
        );

        test(
          'a user cannot verify a payment for somebody else\'s booking',
          () async {
            // A second driver must not be able to touch owner B's booking.
            const intruder = 'aaaaaaaa-0000-4000-8000-000000000009';
            await _exec(
              '''
              INSERT INTO users (id, name, email, phone, password_hash, role)
              VALUES (@id, 'Intruder', 'itest-intruder@test.invalid', '9000000009',
                      'x', 'user')
              ''',
              {'id': intruder},
            );
            addTearDown(
              () => _exec('DELETE FROM users WHERE id = @id', {'id': intruder}),
            );

            await expectLater(
              razorpay.verifyCheckout(
                bookingId: _bookingCod,
                userId: intruder,
                razorpayOrderId: 'itest-order-1',
                razorpayPaymentId: 'itest-pay-x',
                razorpaySignature: 'irrelevant',
              ),
              throwsA(
                isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403),
              ),
            );
          },
        );
      });

      // ---------------------------------------------------------------
      // Item 6 — duplicate protection
      // ---------------------------------------------------------------
      group('item 6: nothing is ever counted twice', () {
        test(
          'repeating the verify callback creates no second earning',
          () async {
            const orderId = 'itest-order-1';
            const paymentId = 'itest-pay-1';
            final signature = _hmacHex(
              '$orderId|$paymentId',
              Config.razorpayKeySecret,
            );

            await razorpay.verifyCheckout(
              bookingId: _bookingOnline,
              userId: _driver,
              razorpayOrderId: orderId,
              razorpayPaymentId: paymentId,
              razorpaySignature: signature,
            );
            await razorpay.verifyCheckout(
              bookingId: _bookingOnline,
              userId: _driver,
              razorpayOrderId: orderId,
              razorpayPaymentId: paymentId,
              razorpaySignature: signature,
            );

            final transfers = await _query(
              'SELECT * FROM payment_transfers WHERE booking_id = @b',
              {'b': _bookingOnline},
            );
            expect(transfers.length, 1, reason: 'one earning per payment');
          },
        );

        test('a duplicated webhook is a no-op', () async {
          final rawBody = jsonEncode({
            'event': 'payment.captured',
            'payload': {
              'payment': {
                'entity': {
                  'id': 'itest-pay-1',
                  'order_id': 'itest-order-1',
                  'status': 'captured',
                  'amount': 50000,
                },
              },
            },
          });
          final signature = _hmacHex(rawBody, Config.razorpayWebhookSecret);
          const eventId = 'itest-event-duplicate';

          final first = await razorpay.processWebhook(
            rawBody: rawBody,
            signature: signature,
            eventIdFromHeader: eventId,
          );
          final second = await razorpay.processWebhook(
            rawBody: rawBody,
            signature: signature,
            eventIdFromHeader: eventId,
          );

          expect(first['duplicate'], isFalse);
          expect(second['duplicate'], isTrue);

          final events = await _query(
            'SELECT * FROM razorpay_webhook_events WHERE event_key = @k',
            {'k': eventId},
          );
          expect(events.length, 1);

          final transfers = await _query(
            'SELECT * FROM payment_transfers WHERE booking_id = @b',
            {'b': _bookingOnline},
          );
          expect(
            transfers.length,
            1,
            reason: 'the webhook created no second earning',
          );
        });

        test('an invalid webhook signature changes nothing', () async {
          final rawBody = jsonEncode({'event': 'payment.captured'});
          await expectLater(
            razorpay.processWebhook(
              rawBody: rawBody,
              signature: 'deadbeef',
              eventIdFromHeader: 'itest-event-bad',
            ),
            throwsA(
              isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400),
            ),
          );
          final events = await _query(
            'SELECT * FROM razorpay_webhook_events WHERE event_key = @k',
            {'k': 'itest-event-bad'},
          );
          expect(events, isEmpty);
        });
      });

      // ---------------------------------------------------------------
      // Atomic payment state
      // ---------------------------------------------------------------
      group('atomic payment confirmation', () {
        test(
          'a captured payment for a cancelled booking is not recorded',
          () async {
            await _exec(
              '''
              INSERT INTO bookings (
                id, parking_id, parking_space_id, user_id, owner_id, vehicle_id,
                rental_type, start_date, end_date, amount, status,
                payment_method, payment_status
              ) VALUES (
                @booking, @parkingA, NULL, @driver, @ownerA, @vehicle,
                'MONTHLY', CURRENT_DATE, CURRENT_DATE + INTERVAL '30 days',
                500, 'CANCELLED', 'RAZORPAY', 'PENDING'
              )
              ''',
              {
                'booking': _bookingAtomic,
                'parkingA': _parkingA,
                'driver': _driver,
                'ownerA': _ownerA,
                'vehicle': _vehicle,
              },
            );
            await _exec(
              '''
              INSERT INTO payments (
                id, booking_id, user_id, owner_id, amount, amount_paise,
                currency, payment_method, provider, payment_status,
                razorpay_order_id, verification_status, razorpay_mode,
                reference, updated_at
              ) VALUES (
                @id, @booking, @driver, @owner, 500, 50000, 'INR',
                'RAZORPAY', 'razorpay', 'CREATED', 'itest-order-atomic',
                'UNVERIFIED', 'live', 'itest-receipt-atomic', NOW()
              )
              ''',
              {
                'id': _atomicPayment,
                'booking': _bookingAtomic,
                'driver': _driver,
                'owner': _ownerA,
              },
            );
            addTearDown(() async {
              await _exec('DELETE FROM payments WHERE id = @id', {
                'id': _atomicPayment,
              });
              await _exec('DELETE FROM bookings WHERE id = @id', {
                'id': _bookingAtomic,
              });
            });

            gateway.payments['itest-pay-atomic'] = {
              'id': 'itest-pay-atomic',
              'order_id': 'itest-order-atomic',
              'status': 'captured',
              'amount': 50000,
              'currency': 'INR',
            };
            final signature = _hmacHex(
              'itest-order-atomic|itest-pay-atomic',
              Config.razorpayKeySecret,
            );

            await expectLater(
              razorpay.verifyCheckout(
                bookingId: _bookingAtomic,
                userId: _driver,
                razorpayOrderId: 'itest-order-atomic',
                razorpayPaymentId: 'itest-pay-atomic',
                razorpaySignature: signature,
              ),
              throwsA(
                isA<ApiError>().having((e) => e.statusCode, 'statusCode', 409),
              ),
            );

            // The payment UPDATE and the ledger INSERT must have rolled back
            // with the refused booking confirmation.
            final payment = await _query(
              'SELECT * FROM payments WHERE id = @id',
              {'id': _atomicPayment},
            );
            expect(payment.first['payment_status'], 'CREATED');
            expect(payment.first['razorpay_payment_id'], isNull);
            final ledger = await _query(
              'SELECT * FROM payment_transfers WHERE payment_id = @id',
              {'id': _atomicPayment},
            );
            expect(ledger, isEmpty);
            final booking = await _query(
              'SELECT * FROM bookings WHERE id = @id',
              {'id': _bookingAtomic},
            );
            expect(booking.first['status'], BookingStatus.cancelled);
            expect(booking.first['payment_status'], 'PENDING');
          },
        );

        test('a failed webhook marks both payment and booking as failed', () async {
          await _exec(
            '''
            INSERT INTO bookings (
              id, parking_id, parking_space_id, user_id, owner_id, vehicle_id,
              rental_type, start_date, end_date, amount, status,
              payment_method, payment_status
            ) VALUES (
              @booking, @parkingA, NULL, @driver, @ownerA, @vehicle,
              'MONTHLY', CURRENT_DATE, CURRENT_DATE + INTERVAL '30 days',
              500, 'ACCEPTED', 'RAZORPAY', 'PENDING'
            )
            ''',
            {
              'booking': _bookingFailed,
              'parkingA': _parkingA,
              'driver': _driver,
              'ownerA': _ownerA,
              'vehicle': _vehicle,
            },
          );
          await _exec(
            '''
            INSERT INTO payments (
              id, booking_id, user_id, owner_id, amount, amount_paise,
              currency, payment_method, provider, payment_status,
              razorpay_order_id, verification_status, razorpay_mode,
              reference, updated_at
            ) VALUES (
              @id, @booking, @driver, @owner, 500, 50000, 'INR',
              'RAZORPAY', 'razorpay', 'CREATED', 'itest-order-failed',
              'UNVERIFIED', 'live', 'itest-receipt-failed', NOW()
            )
            ''',
            {
              'id': _failedPayment,
              'booking': _bookingFailed,
              'driver': _driver,
              'owner': _ownerA,
            },
          );
          addTearDown(() async {
            await _exec('DELETE FROM payments WHERE id = @id', {
              'id': _failedPayment,
            });
            await _exec('DELETE FROM bookings WHERE id = @id', {
              'id': _bookingFailed,
            });
          });

          final rawBody = jsonEncode({
            'event': 'payment.failed',
            'payload': {
              'payment': {
                'entity': {
                  'id': 'itest-pay-failed',
                  'order_id': 'itest-order-failed',
                  'status': 'failed',
                  'amount': 50000,
                },
              },
            },
          });
          final signature = _hmacHex(rawBody, Config.razorpayWebhookSecret);
          final result = await razorpay.processWebhook(
            rawBody: rawBody,
            signature: signature,
            eventIdFromHeader: 'itest-event-failed',
          );
          expect(result['handled'], 'failed');

          final payment = await _query(
            'SELECT * FROM payments WHERE id = @id',
            {'id': _failedPayment},
          );
          expect(payment.first['payment_status'], 'FAILED');
          expect(payment.first['verification_status'], 'GATEWAY_FAILED');

          // The Flutter screen reads bookings.paymentStatus; it must no longer
          // be stuck on PENDING after the gateway reported a failure.
          final booking = await _query(
            'SELECT * FROM bookings WHERE id = @id',
            {'id': _bookingFailed},
          );
          expect(booking.first['payment_status'], 'FAILED');
          expect(booking.first['status'], BookingStatus.accepted);
        });
      });

      // ---------------------------------------------------------------
      // Item 5 — manual settlement
      // ---------------------------------------------------------------
      group('item 5: manual settlement PENDING -> SETTLED', () {
        test('an admin records a real manual payout, idempotently', () async {
          final transfers = await _query(
            'SELECT * FROM payment_transfers WHERE booking_id = @b',
            {'b': _bookingOnline},
          );
          expect(transfers.length, 1);
          final transferId = transfers.first['id'].toString();

          // A manual payout can only be executed if the admin can obtain the
          // destination. Save one, then read it back through the admin-only
          // decryption path before settling.
          final accountService = OwnerPaymentAccountService();
          await accountService.saveForOwner(
            ownerId: _ownerA,
            body: {
              'legalName': 'itest Owner A',
              'accountType': 'INDIVIDUAL',
              'mobile': '9000000001',
              'email': 'itest-owner-a@test.invalid',
              'accountHolderName': 'itest Owner A',
              'bankAccountNumber': '123456789012',
              'confirmBankAccountNumber': '123456789012',
              'ifscCode': 'HDFC0001234',
              'consent': true,
            },
          );

          final pendingQueue = await settlement.listPending();
          final queued = pendingQueue.singleWhere(
            (r) => r['paymentTransferId'] == transferId,
          );
          expect(queued['payoutDetailsAvailable'], isTrue);
          expect(queued['bankLast4'], '9012');
          expect(jsonEncode(queued), isNot(contains('123456789012')));

          final destination = await settlement.getPayoutDestination(
            transferId: transferId,
            adminUserId: _admin,
          );
          expect(destination['bankAccountNumber'], '123456789012');
          expect(destination['ifscCode'], 'HDFC0001234');
          expect(destination['ownerId'], _ownerA);
          expect(destination['ownerAmountPaise'], 50000);

          // An empty reference is not evidence of a payout and must be refused.
          await expectLater(
            settlement.markSettled(transferId: transferId, adminUserId: _admin),
            throwsA(
              isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400),
            ),
          );

          final first = await settlement.markSettled(
            transferId: transferId,
            adminUserId: _admin,
            reference: 'UTR-ITEST-001',
            note: 'itest manual payout',
          );
          expect(first['settlementStatus'], 'SETTLED');
          expect(first['manualPayoutReference'], 'UTR-ITEST-001');
          expect(first['alreadySettled'], isFalse);

          final settled = await _query(
            'SELECT * FROM payment_transfers WHERE id = @id',
            {'id': transferId},
          );
          final row = settled.first;
          expect(row['settlement_status'], 'SETTLED');
          expect(row['settled_at'], isNotNull);
          expect(row['settled_by_admin_user_id'].toString(), _admin);
          expect(row['manual_payout_reference'], 'UTR-ITEST-001');
          expect(row['manual_payout_note'], 'itest manual payout');
          // A manual payout is NOT a Razorpay transfer.
          expect(row['razorpay_transfer_id'], isNull);
          expect(row['transfer_status'], 'PENDING');

          // Repeat: idempotent, the original record is untouched.
          final second = await settlement.markSettled(
            transferId: transferId,
            adminUserId: _admin,
            reference: 'UTR-ITEST-002',
            note: 'itest second attempt',
          );
          expect(second['alreadySettled'], isTrue);
          expect(second['manualPayoutReference'], 'UTR-ITEST-001');

          final after = await _query(
            'SELECT * FROM payment_transfers WHERE id = @id',
            {'id': transferId},
          );
          expect(after.first['manual_payout_reference'], 'UTR-ITEST-001');
          expect(after.first['settled_at'], row['settled_at']);

          await expectLater(
            settlement.getPayoutDestination(
              transferId: transferId,
              adminUserId: _admin,
            ),
            throwsA(
              isA<ApiError>().having((e) => e.statusCode, 'statusCode', 409),
            ),
          );
        });

        test('a test-mode earning is audit-only: it cannot be settled and is '
            'hidden from live-mode owner totals', () async {
          await _exec(
            '''
              INSERT INTO payments (
                id, booking_id, user_id, owner_id, amount, amount_paise,
                currency, payment_method, provider, payment_status,
                razorpay_order_id, verification_status, razorpay_mode,
                reference, updated_at
              ) VALUES (
                @id, @booking, @user, @owner, 500, 50000, 'INR',
                'RAZORPAY', 'razorpay', 'SUCCESS', 'itest-order-test',
                'WEBHOOK_VERIFIED', 'test', 'itest-receipt-test', NOW()
              )
              ''',
            {
              'id': _testPayment,
              'booking': _bookingOnline,
              'user': _driver,
              'owner': _ownerA,
            },
          );
          await _exec(
            '''
              INSERT INTO payment_transfers (
                id, payment_id, booking_id, owner_id, gross_amount_paise,
                platform_fee_paise, owner_amount_paise, currency,
                transfer_status, settlement_status
              ) VALUES (
                @id, @payment, @booking, @owner, 50000, 0, 50000, 'INR',
                'PENDING', 'PENDING'
              )
              ''',
            {
              'id': _testTransfer,
              'payment': _testPayment,
              'booking': _bookingOnline,
              'owner': _ownerA,
            },
          );
          addTearDown(() async {
            await _exec('DELETE FROM payment_transfers WHERE payment_id = @p', {
              'p': _testPayment,
            });
            await _exec('DELETE FROM payments WHERE id = @p', {
              'p': _testPayment,
            });
          });

          await expectLater(
            settlement.markSettled(
              transferId: _testTransfer,
              adminUserId: _admin,
              reference: 'UTR-MUST-NOT-EXIST',
            ),
            throwsA(
              isA<ApiError>().having((e) => e.statusCode, 'statusCode', 409),
            ),
          );

          final blocked = await _query(
            'SELECT settlement_status, settled_at '
            'FROM payment_transfers WHERE id = @id',
            {'id': _testTransfer},
          );
          expect(blocked.first['settlement_status'], 'PENDING');
          expect(blocked.first['settled_at'], isNull);

          // In live mode the test ledger row and its gross amount disappear
          // from the owner-facing numbers. The settled live row remains.
          try {
            Config.applyTestOverrides({...overrides!, 'RAZORPAY_MODE': 'live'});
            final live = await payments.ownerEarningsSummary(ownerId: _ownerA);
            expect(live['pendingSettlementPaise'], 0);
            expect(live['settledPaise'], 50000);
            expect(live['transferCount'], 1);
            expect(live['totalEarnings'], 500);
          } finally {
            Config.applyTestOverrides(overrides!);
          }
        });

        test(
          'the owner being paid comes from the ledger row, never from input',
          () async {
            final transfers = await _query(
              'SELECT * FROM payment_transfers WHERE booking_id = @b',
              {'b': _bookingOnline},
            );
            final transferId = transfers.first['id'].toString();

            // A second admin records the payout. The owner that is credited is
            // still the one on the ledger row, never one taken from the input.
            const admin2 = 'aaaaaaaa-0000-4000-8000-000000000005';
            await _exec(
              '''
              INSERT INTO users (id, name, email, phone, password_hash, role)
              VALUES (@id, 'Admin 2', 'itest-admin2@test.invalid', '9000000005',
                      'x', 'admin')
              ''',
              {'id': admin2},
            );
            addTearDown(
              () => _exec('DELETE FROM users WHERE id = @id', {'id': admin2}),
            );

            final result = await settlement.markSettled(
              transferId: transferId,
              adminUserId: admin2,
            );
            expect(result['ownerId'], _ownerA);
            expect(result['alreadySettled'], isTrue);
          },
        );

        test('an OWNER token is refused at the route boundary (403)', () async {
          final transfers = await _query(
            'SELECT * FROM payment_transfers WHERE booking_id = @b',
            {'b': _bookingOnline},
          );
          final transferId = transfers.first['id'].toString();

          setActiveUserVerifierForTesting((_) async => true);
          addTearDown(resetActiveUserVerifier);

          final handler = const Pipeline()
              .addMiddleware(corsMiddleware())
              .addMiddleware(securityHeadersMiddleware())
              .addMiddleware(errorMiddleware())
              .addHandler(ApiRouter.create());

          Future<Response> send(String role) async {
            final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
            final jwt = JWT({
              'sub': _ownerA,
              'role': role,
              'type': 'access',
              'jti': 'itest-settlement',
              'iat': now,
              'exp': now + 3600,
            }).sign(SecretKey(Config.jwtSecret), algorithm: JWTAlgorithm.HS256);

            return handler(
              Request(
                'POST',
                Uri.parse(
                  'http://localhost/api/admin/settlements/$transferId/mark-settled',
                ),
                body: '{"reference":"UTR-ITEST-OWNER"}',
                headers: {'authorization': 'Bearer $jwt'},
              ),
            );
          }

          // An owner may NOT settle an earning - not even their own.
          final ownerResponse = await send('owner');
          expect(ownerResponse.statusCode, 403);

          // A plain user may NOT settle either.
          final userResponse = await send('user');
          expect(userResponse.statusCode, 403);

          // An admin passes the gate.
          final adminResponse = await send('admin');
          expect(adminResponse.statusCode, isNot(401));
          expect(adminResponse.statusCode, isNot(403));
        });
      });

      // ---------------------------------------------------------------
      // Item 7 — Owner A / Owner B isolation
      // ---------------------------------------------------------------
      group('item 7: one owner never sees another owner\'s money', () {
        test('the earnings summary is scoped to the caller', () async {
          final service = PaymentService();
          final ownerA = await service.ownerEarningsSummary(ownerId: _ownerA);
          final ownerB = await service.ownerEarningsSummary(ownerId: _ownerB);

          expect(ownerA['totalEarnings'], 500);
          expect(ownerA['paidBookings'], 1);
          expect(ownerB['totalEarnings'], 0);
          expect(ownerB['paidBookings'], 0);
        });

        test('the settlement ledger is scoped to the caller', () async {
          final service = PaymentService();
          final ownerA = await service.ownerEarningsSummary(ownerId: _ownerA);
          final ownerB = await service.ownerEarningsSummary(ownerId: _ownerB);

          // AUDIT GUARD: `SUM()` over a bigint column yields PostgreSQL
          // `numeric`, and the driver ALWAYS decodes `numeric` as a STRING.
          // The owner A transfer was settled by the admin in item 5, so the
          // exact expected values are asserted one by one. If the textual
          // numeric is ever decoded as 0 again, these exact assertions fail
          // (a `pending + settled == total` check alone would NOT, because
          // 0 + 0 == 0 would still satisfy a total-only expectation).
          expect(ownerA['pendingSettlementPaise'], 0);
          expect(ownerA['settledPaise'], 50000);
          expect(ownerA['transferCount'], 1);

          // Owner A's whole settlement ledger (pending + settled) is theirs.
          final ownerATotal =
              (ownerA['pendingSettlementPaise'] as int) +
              (ownerA['settledPaise'] as int);
          expect(ownerATotal, 50000);

          // Owner B sees NOTHING of owner A's ledger.
          expect(ownerB['pendingSettlementPaise'], 0);
          expect(ownerB['settledPaise'], 0);
          expect(ownerB['transferCount'], 0);
          expect(ownerB['settlementEntries'], isEmpty);
        });
      });

      // ---------------------------------------------------------------
      // Item 8 — COD regression
      // ---------------------------------------------------------------
      group('item 8: cash on delivery still works exactly as before', () {
        test(
          'the owner confirms the cash and the earning is created once',
          () async {
            await payments.createCod(bookingId: _bookingCod, userId: _driver);

            final pending = await _query(
              'SELECT * FROM bookings WHERE id = @b',
              {'b': _bookingCod},
            );
            expect(pending.first['status'], BookingStatus.codPending);
            expect(pending.first['payment_status'], PaymentStatus.codPending);

            await payments.confirmCod(bookingId: _bookingCod, ownerId: _ownerB);

            final confirmed = await _query(
              'SELECT * FROM bookings WHERE id = @b',
              {'b': _bookingCod},
            );
            expect(confirmed.first['status'], BookingStatus.confirmed);
            expect(
              confirmed.first['payment_status'],
              PaymentStatus.codConfirmed,
            );

            final service = PaymentService();
            final ownerB = await service.ownerEarningsSummary(ownerId: _ownerB);
            expect(ownerB['totalEarnings'], 800);
            expect(ownerB['paidBookings'], 1);

            // Repeat: the earning must NOT double.
            await payments.confirmCod(bookingId: _bookingCod, ownerId: _ownerB);
            final ownerB2 = await service.ownerEarningsSummary(
              ownerId: _ownerB,
            );
            expect(ownerB2['totalEarnings'], 800);
            expect(ownerB2['paidBookings'], 1);
          },
        );
      });

      // ---------------------------------------------------------------
      // Item 9 — owner payment account
      // ---------------------------------------------------------------
      group('item 9: the owner payout destination is encrypted at rest', () {
        test(
          'full details are encrypted and never exposed to the app',
          () async {
            final service = OwnerPaymentAccountService();
            await service.saveForOwner(
              ownerId: _ownerA,
              body: {
                'legalName': 'itest Owner A',
                'accountType': 'INDIVIDUAL',
                'mobile': '9000000001',
                'email': 'itest-owner-a@test.invalid',
                'accountHolderName': 'itest Owner A',
                'bankAccountNumber': '123456789012',
                'confirmBankAccountNumber': '123456789012',
                'ifscCode': 'HDFC0001234',
                'consent': true,
              },
            );

            final columns = await _query('''
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = current_schema()
              AND table_name = 'owner_payment_accounts'
            ''');
            final names = columns.map((c) => c['column_name'].toString());
            expect(names.contains('bank_last4'), isTrue);
            expect(names.contains('bank_account_number'), isFalse);
            expect(names.contains('ifsc_code'), isFalse);
            expect(
              names.contains('payout_account_number_encrypted'),
              isTrue,
              reason:
                  'migration 012 must keep a recoverable payout destination',
            );

            final rows = await _query(
              'SELECT * FROM owner_payment_accounts WHERE owner_id = @o',
              {'o': _ownerA},
            );
            expect(rows.length, 1);
            expect(rows.first['bank_last4'], '9012');

            final encryptedAccount = rows
                .first['payout_account_number_encrypted']
                .toString();
            final encryptedIfsc = rows.first['payout_ifsc_encrypted']
                .toString();
            expect(encryptedAccount, startsWith('v1.'));
            expect(encryptedIfsc, startsWith('v1.'));
            expect(encryptedAccount, isNot(contains('123456789012')));
            expect(encryptedIfsc, isNot(contains('HDFC0001234')));
            expect(
              PayoutDetailsCipher.decrypt(encryptedAccount),
              '123456789012',
            );
            expect(PayoutDetailsCipher.decrypt(encryptedIfsc), 'HDFC0001234');

            final projection = await service.getForOwner(ownerId: _ownerA);
            expect(projection['bankLast4'], '9012');
            expect(projection['payoutDetailsAvailable'], isTrue);
            expect(jsonEncode(projection), isNot(contains('123456789012')));
            expect(jsonEncode(projection), isNot(contains('HDFC0001234')));
            expect(jsonEncode(projection), isNot(contains('v1.')));
          },
        );
      });
    },
    skip: overrides == null
        ? 'set PARKSHARE_TEST_DB_NAME to run the DB-backed integration test'
        : null,
  );
}
