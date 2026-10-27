import 'dart:convert';

import 'package:parkshare_backend/config/config.dart';
import 'package:shelf/shelf.dart';

/// An application error that carries an HTTP status code so route handlers
/// can render a consistent JSON error envelope.
class ApiError implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? details;

  ApiError(this.statusCode, this.message, {this.details});

  factory ApiError.validation(String message) => ApiError(400, message);
  factory ApiError.unauthorized([String? message]) =>
      ApiError(401, message ?? 'Authentication required.');
  factory ApiError.forbidden([String? message]) =>
      ApiError(403, message ?? 'You are not allowed to perform this action.');
  factory ApiError.notFound([String? message]) =>
      ApiError(404, message ?? 'Resource not found.');
  factory ApiError.conflict(String message) => ApiError(409, message);

  /// 429. Used by the in-process rate limiter and the OTP resend cooldown.
  factory ApiError.rateLimited([String? message]) =>
      ApiError(429, message ?? 'Too many requests. Please try again shortly.');
  factory ApiError.server([String? message]) =>
      ApiError(500, message ?? 'Internal server error.');

  /// 413. Raised when an upload exceeds the configured byte budget. Kept
  /// separate from [validation] so a client can tell "too big" from "wrong
  /// type" without the message doing the work.
  factory ApiError.payloadTooLarge([String? message]) =>
      ApiError(413, message ?? 'The uploaded file is too large.');

  /// Response headers for this error. 401/429 get the headers a well-behaved
  /// client (and any future browser-based one) expects.
  Map<String, String> get responseHeaders => {
    'content-type': 'application/json',
    if (statusCode == 401) 'www-authenticate': 'Bearer realm="parkshare"',
    if (statusCode == 429) 'retry-after': '60',
  };

  Response toResponse() {
    return Response(
      statusCode,
      headers: responseHeaders,
      body: jsonEncode({'success': false, 'message': message, 'data': details}),
    );
  }
}

/// Consistent API response envelope: { success, message, data }.
class ApiResponse {
  static Response ok([Object? data, String message = 'Success']) {
    return Response.ok(
      jsonEncode({'success': true, 'message': message, 'data': data}),
      headers: {'content-type': 'application/json'},
    );
  }

  static Response created([Object? data, String message = 'Created']) {
    return Response(
      201,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'success': true, 'message': message, 'data': data}),
    );
  }

  static Response error(int status, String message, [Object? data]) {
    return Response(
      status,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'success': false, 'message': message, 'data': data}),
    );
  }

  static Response badRequest(String message) => error(400, message);
  static Response unauthorized(String message) => error(401, message);
  static Response notFound([String message = 'Resource not found.']) =>
      error(404, message);
  static Response conflict(String message) => error(409, message);
  static Response serverError([String message = 'Internal server error.']) =>
      error(500, message);
}

/// Reads and decodes a request JSON body into a Map (or returns null).
Future<Map<String, dynamic>?> readJsonBody(Request request) async {
  try {
    final body = await request.readAsString();
    if (body.trim().isEmpty) return null;
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  } catch (_) {
    return null;
  }
}

/// Global error middleware: converts exceptions into the JSON envelope.
///
/// SECURITY (audit M-05): an unhandled exception used to print its message AND
/// its stack trace to stdout, which is how internal SQL/column detail leaks
/// into log files. In production only the exception *type* is emitted, and the
/// client still receives the same generic 500 as before.
Middleware errorMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      try {
        return await inner(request);
      } on ApiError catch (e) {
        print('[ApiError] ${e.statusCode} ${e.message}');
        return e.toResponse();
      } catch (e, st) {
        if (Config.verboseErrors) {
          print('[Unhandled] $e\n$st');
        } else {
          print('[Unhandled] ${e.runtimeType} (details withheld)');
        }
        return ApiResponse.serverError();
      }
    };
  };
}

/// CORS middleware driven by `Config.effectiveAllowedOrigins`.
///
/// SECURITY (audit M-01): the old version unconditionally sent
/// `Access-Control-Allow-Origin: *`, which let any web page on the internet
/// drive the API from a visitor's browser. Now the value is an allow-list from
/// the environment; `*` is only ever used in development, and a request from a
/// non-allowed origin simply gets no CORS headers (so the browser blocks it).
///
/// `Vary: Origin` is always sent, otherwise a shared cache could serve one
/// origin's response to another.
Middleware corsMiddleware() {
  final allowed = Config.effectiveAllowedOrigins;
  final wildcards = allowed.contains('*');

  Map<String, String> headersFor(Request request) {
    final origin = request.headers['origin'] ?? '';
    if (allowed.isEmpty) return const {'vary': 'Origin'};
    final value = wildcards ? '*' : (allowed.contains(origin) ? origin : '');
    return {
      'vary': 'Origin',
      if (value.isNotEmpty) ...{
        'access-control-allow-origin': value,
        'access-control-allow-methods':
            'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'access-control-allow-headers':
            'Origin, Content-Type, Accept, Authorization',
        'access-control-max-age': '86400',
      },
    };
  }

  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: headersFor(request));
      }
      final response = await inner(request);
      return response.change(headers: headersFor(request));
    };
  };
}

/// Baseline security response headers (audit M-04).
///
/// `nosniff` matters here in particular: uploaded files are served from this
/// origin and the old content-type mapping guessed `image/jpeg` for any unknown
/// extension, so without `nosniff` a browser could be talked into rendering an
/// uploaded file as script.
Middleware securityHeadersMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      final response = await inner(request);
      return response.change(
        headers: {
          'x-content-type-options': 'nosniff',
          'x-frame-options': 'DENY',
          'referrer-policy': 'no-referrer',
          'cross-origin-resource-policy': 'same-site',
          'permissions-policy':
              'geolocation=(self), camera=(self), microphone=()',
        },
      );
    };
  };
}

/// Minimal in-process fixed-window rate limiter, keyed by client IP.
///
/// SECURITY (audit H-05, M-13): the password-reset endpoints are
/// unauthenticated, so without a limiter a 6-digit OTP (10^6 candidates) is
/// grindable at whatever rate the network allows. This is deliberately simple
/// and in-process — a multi-instance deployment must use a shared store, which
/// is called out in the documentation.
Middleware rateLimitMiddleware({
  required int requestsPerMinute,
  String Function(Request request)? keyOf,
  String name = 'default',
}) {
  if (requestsPerMinute <= 0) return (Handler inner) => inner;
  // NOTE: the window is recomputed per request, otherwise a request that
  // arrives later in the minute would still see entries that are already old.
  final hits = <String, List<DateTime>>{};

  return (Handler inner) {
    return (Request request) async {
      final key = keyOf?.call(request) ?? clientIpOf(request);
      final now = DateTime.now().toUtc();
      final window = now.subtract(const Duration(minutes: 1));
      // AUDIT FIX: this list MUST be growable. It used to be
      // `hits[key] ?? const <DateTime>[]`, and `removeWhere` on a const list
      // throws UnsupportedError — so the FIRST request from every new client IP
      // failed with a 500 instead of being served. The seed value is the
      // `const Duration`, not the list.
      final recent = hits[key] ?? <DateTime>[];
      recent.removeWhere((t) => t.isBefore(window));
      if (recent.length >= requestsPerMinute) {
        recent.add(now);
        hits[key] = recent;
        throw ApiError.rateLimited(
          'Too many requests. Please try again in a minute.',
        );
      }
      recent.add(now);
      hits[key] = recent;
      // Opportunistic cleanup so a long-lived process cannot grow unbounded.
      if (hits.length > 10000) {
        hits.removeWhere((_, times) => times.every((t) => t.isBefore(window)));
      }
      return inner(request);
    };
  };
}

/// Best-effort client IP, used as the default [rateLimitMiddleware] key.
///
/// Resolution order:
///   1. `context['remoteAddress']` — set by `bin/server.dart` from the real
///      socket, so this is the only trustworthy source. [Request] itself has no
///      remote-address accessor, hence the explicit binding.
///   2. the first entry of `X-Forwarded-For`, which is what a single trusted
///      reverse proxy appends last. ONLY safe because [clientIpOf] is not fed
///      by untrusted input at the TLS terminator we control; behind a proxy
///      that forwards a client-supplied header the socket address from (1)
///      should be preferred.
///   3. the requested `Host` value — a deliberate last resort, not a real IP.
///      It collapses every client behind one hostname into a single bucket,
///      which fails closed (over-limiting) rather than open.
String clientIpOf(Request request) {
  final remote = request.context['remoteAddress'];
  if (remote is String && remote.isNotEmpty) return remote;
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.trim().isNotEmpty) {
    return forwarded.split(',').first.trim();
  }
  return 'host:${request.requestedUri.host}';
}
