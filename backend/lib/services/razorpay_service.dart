import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:parkshare_backend/config/config.dart';

/// A sanitised Razorpay failure.
///
/// SECURITY: [userMessage] is safe to surface to a client. Raw Razorpay error
/// bodies are never propagated (they can echo request data), and the key
/// secret / webhook secret are never included in any string this class builds.
class RazorpayException implements Exception {
  /// HTTP status from Razorpay, or 0 for a transport/parse failure.
  final int statusCode;

  /// Razorpay error code (e.g. `BAD_REQUEST_ERROR`), when present.
  final String? code;

  /// Safe, generic message for the API layer.
  final String userMessage;

  RazorpayException(this.statusCode, this.userMessage, {this.code});

  @override
  String toString() => 'RazorpayException($statusCode, ${code ?? '-'})';
}

/// A created Razorpay order (only the fields the backend needs).
class RazorpayOrder {
  final String id;
  final int amountPaise;
  final String currency;
  final String receipt;
  final String status;

  const RazorpayOrder({
    required this.id,
    required this.amountPaise,
    required this.currency,
    required this.receipt,
    required this.status,
  });

  factory RazorpayOrder.fromJson(Map<String, dynamic> json) => RazorpayOrder(
    id: json['id']?.toString() ?? '',
    amountPaise: (json['amount'] as num?)?.toInt() ?? 0,
    currency: json['currency']?.toString() ?? 'INR',
    receipt: json['receipt']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
  );
}

/// Thin, focused Razorpay REST client.
///
/// Responsibilities: Basic-Auth calls to the Razorpay API (create order, fetch
/// payment, create Route transfer), plus the two HMAC verifications. It knows
/// nothing about ParkShare's booking state machine, which is why it stays
/// testable without a database.
class RazorpayService {
  RazorpayService({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = _timeout;
  }

  final HttpClient _httpClient;

  static const String _apiBase = 'https://api.razorpay.com/v1';
  static const Duration _timeout = Duration(seconds: 20);

  bool get isConfigured => Config.razorpayConfigured;

  /// `Authorization: Basic base64(key_id:key_secret)`.
  ///
  /// The header value is built here and never logged.
  String get _basicAuthHeader {
    final raw = '${Config.razorpayKeyId}:${Config.razorpayKeySecret}';
    return 'Basic ${base64.encode(utf8.encode(raw))}';
  }

  // ---------------------------------------------------------------------
  // Orders / payments / transfers
  // ---------------------------------------------------------------------

  /// Creates an order. [amountPaise] is the authoritative integer amount.
  Future<RazorpayOrder> createOrder({
    required int amountPaise,
    required String receipt,
    Map<String, String> notes = const {},
  }) async {
    _requireConfigured();
    final json = await _post('/orders', {
      'amount': amountPaise,
      'currency': 'INR',
      'receipt': receipt,
      // Auto-capture so no separate capture call is needed; the webhook then
      // reports `payment.captured`.
      'payment_capture': 1,
      'notes': notes,
    });
    return RazorpayOrder.fromJson(json);
  }

  /// Fetches a payment (used for reconciliation / diagnostics).
  Future<Map<String, dynamic>> fetchPayment(String paymentId) async {
    _requireConfigured();
    return _get('/payments/$paymentId');
  }

  /// Creates a Route transfer of [amountPaise] to [linkedAccountId].
  ///
  /// Only ever called when `RAZORPAY_ROUTE_ENABLED` is true AND the linked
  /// account comes from the database. Never accepts a client-supplied account.
  Future<Map<String, dynamic>> createTransfer({
    required String razorpayPaymentId,
    required int amountPaise,
    required String linkedAccountId,
    Map<String, String> notes = const {},
  }) async {
    _requireConfigured();
    return _post('/payments/$razorpayPaymentId/transfers', {
      'transfers': [
        {
          'account': linkedAccountId,
          'amount': amountPaise,
          'currency': 'INR',
          'notes': notes,
        },
      ],
    });
  }

  // ---------------------------------------------------------------------
  // Signature verification (pure functions, unit-testable)
  // ---------------------------------------------------------------------

  /// Razorpay Orders checkout signature:
  ///   HMAC_SHA256(`<order_id>|<payment_id>`, key_secret), hex.
  ///
  /// [secret] is passed explicitly so tests can use a fixed secret. In
  /// production the caller passes [Config.razorpayKeySecret].
  static bool verifyCheckoutSignature({
    required String orderId,
    required String paymentId,
    required String signature,
    required String secret,
  }) {
    if (orderId.isEmpty || paymentId.isEmpty || signature.isEmpty) {
      return false;
    }
    return _hmacHexMatches(
      message: '$orderId|$paymentId',
      signatureHex: signature,
      secret: secret,
    );
  }

  /// Razorpay webhook signature: HMAC_SHA256(rawBody, webhook_secret), hex,
  /// compared against the `X-Razorpay-Signature` header.
  static bool verifyWebhookSignature({
    required String rawBody,
    required String signature,
    required String secret,
  }) {
    if (rawBody.isEmpty || signature.isEmpty || secret.isEmpty) return false;
    return _hmacHexMatches(
      message: rawBody,
      signatureHex: signature,
      secret: secret,
    );
  }

  /// True when `HMAC_SHA256(message, secret)` (hex) equals [signatureHex].
  ///
  /// Uses a constant-time comparison so a caller cannot learn the correct
  /// signature byte-by-byte from response timing.
  static bool _hmacHexMatches({
    required String message,
    required String signatureHex,
    required String secret,
  }) {
    if (secret.isEmpty) return false;
    final mac = Hmac(sha256, utf8.encode(secret));
    final expected = mac.convert(utf8.encode(message)).bytes;
    final provided = _hexToBytes(signatureHex);
    return constantTimeEquals(expected, provided);
  }

  /// Length-safe constant-time byte comparison.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    // Compare a fixed number of bytes so the loop count does not depend on the
    // length mismatch; a differing length still fails.
    final maxLen = a.length > b.length ? a.length : b.length;
    var diff = a.length ^ b.length;
    for (var i = 0; i < maxLen; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      diff |= av ^ bv;
    }
    return diff == 0;
  }

  /// Decodes a lowercase/uppercase hex string. Returns an empty list when the
  /// input is not valid hex, which then fails the comparison.
  static Uint8List _hexToBytes(String hex) {
    final clean = hex.trim();
    if (clean.isEmpty || clean.length.isOdd) return Uint8List(0);
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(clean.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return Uint8List(0);
      out[i] = byte;
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------

  void _requireConfigured() {
    if (!isConfigured) {
      throw RazorpayException(
        0,
        'Online payment is not configured on the server yet.',
        code: 'NOT_CONFIGURED',
      );
    }
  }

  Future<Map<String, dynamic>> _get(String path) => _send('GET', path, null);

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final uri = Uri.parse('$_apiBase$path');
    try {
      final request = await _httpClient.openUrl(method, uri).timeout(_timeout);
      request.headers.set(HttpHeaders.authorizationHeader, _basicAuthHeader);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(_timeout);
      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(responseBody);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is List) {
          return {'data': decoded};
        }
        throw RazorpayException(
          response.statusCode,
          'Unexpected response from the payment gateway.',
        );
      }
      throw _mapError(response.statusCode, responseBody);
    } on RazorpayException {
      rethrow;
    } on TimeoutException {
      throw RazorpayException(
        0,
        'The payment gateway took too long to respond. Please try again.',
        code: 'TIMEOUT',
      );
    } on SocketException {
      throw RazorpayException(
        0,
        'Could not reach the payment gateway. Please try again.',
        code: 'CONNECTION_ERROR',
      );
    } on FormatException {
      throw RazorpayException(
        0,
        'The payment gateway returned an unreadable response.',
        code: 'MALFORMED_RESPONSE',
      );
    } catch (_) {
      throw RazorpayException(
        0,
        'The payment gateway request failed. Please try again.',
        code: 'UNKNOWN',
      );
    }
  }

  /// Maps a Razorpay 4xx/5xx to a safe [RazorpayException].
  ///
  /// Only generic wording and the non-sensitive error code are kept; the raw
  /// description is dropped so it can never reach the client or the logs.
  RazorpayException _mapError(int status, String body) {
    String? code;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          code = error['code']?.toString();
        }
      }
    } catch (_) {
      // Non-JSON error body: keep the generic message.
    }
    final message = status >= 500
        ? 'The payment gateway is temporarily unavailable. Please try again.'
        : 'The payment gateway rejected the request. Please try again.';
    return RazorpayException(status, message, code: code);
  }
}
