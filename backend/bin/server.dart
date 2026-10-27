import 'dart:io';

import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/routes/api_router.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Starts the ParkShare Shelf API server.
///
/// Port resolution order:
///   1. `PORT` environment variable (e.g. `$env:PORT="8081"`)
///   2. `PORT` in backend/.env (via [Config.port])
///   3. default 8080
///
/// If the chosen port is already in use the server fails loudly with
/// remediation instructions instead of silently switching ports.
///
/// SECURITY (audit H-01): [Config.validateForStartup] runs BEFORE the socket is
/// bound. In production that means a missing or placeholder `JWT_SECRET`, a
/// missing `PUBLIC_BASE_URL`, an empty CORS allow-list or a password-reset flow
/// with no delivery channel all abort the boot. The server can no longer come
/// up "successfully" while silently signing tokens with a public key.
/// Builds the request pipeline.
///
/// Middleware order matters:
///   * `corsMiddleware` runs first so even an error response carries the CORS
///     headers the browser needs in order to *read* the error;
///   * `logRequests` is added only when `Config.requestLoggingEnabled`
///     (audit M-06: off in production unless explicitly requested, so an OTP
///     delivery trail is not dumped to disk by default);
///   * `errorMiddleware` is closest to the handler so it sees the raw
///     exceptions and converts them into the JSON envelope.
Handler _buildHandler() {
  var pipeline = const Pipeline()
      .addMiddleware(corsMiddleware())
      .addMiddleware(securityHeadersMiddleware())
      .addMiddleware(errorMiddleware());
  if (Config.requestLoggingEnabled) {
    pipeline = pipeline.addMiddleware(logRequests());
  }
  return pipeline.addHandler(ApiRouter.create());
}

Future<void> main() async {
  Config.load();

  final problems = Config.validateForStartup();
  if (problems.isNotEmpty) {
    stderr.writeln('');
    // ASCII-only: stderr encoding is platform dependent, so keep this message
    // free of non-ASCII characters that render as garbage on Windows consoles.
    stderr.writeln('ParkShare API: refusing to start - insecure configuration.');
    stderr.writeln('  APP_ENV = ${Config.appEnv}');
    for (final problem in problems) {
      stderr.writeln('  - $problem');
    }
    stderr.writeln('');
    stderr.writeln(
      'Fix backend/.env (see backend/.env.example), or run with '
      'APP_ENV=development for a local run.',
    );
    // exit() rather than exitCode: the DB pool has not been opened yet, but
    // being explicit here guarantees the process really terminates.
    exit(1);
  }

  await Db.init();
  await Db.migrate();

  final handler = _buildHandler();

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? Config.port;
  if (port < 1 || port > 65535) {
    stderr.writeln(
      'Invalid PORT value "$port" (must be 1-65535). '
      'Fix it with: \$env:PORT="8080"; dart run bin/server.dart',
    );
    // exit() (not just exitCode) so the process dies even though the DB
    // pool keeps sockets/timers alive after main() returns.
    exit(1);
  }

  stdout.writeln('ParkShare API: attempting to bind 0.0.0.0:$port ...');

  HttpServer server;
  try {
    // Deliberately not shelf_io.serve(): see [_dispatchWithPeerAddress].
    server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  } on SocketException catch (e) {
    final errno = e.osError?.errorCode;
    stderr.writeln(
      'Failed to bind ParkShare API to port $port: '
      '${e.message} (errno = $errno)',
    );
    if (errno == 10048 || errno == 48 || errno == 98) {
      // Windows WSAEADDRINUSE = 10048, POSIX EADDRINUSE = 48/98.
      stderr.writeln('Port $port is already in use by another process.');
      stderr.writeln('Options:');
      stderr.writeln('  A) Free the port on Windows, then restart:');
      stderr.writeln(
        '     Get-NetTCPConnection -LocalPort $port -State Listen '
        '| Select-Object OwningProcess',
      );
      stderr.writeln('     Stop-Process -Id <PID> -Force');
      stderr.writeln(
        '  B) Run the backend on another port (URL is printed '
        'on startup):',
      );
      stderr.writeln('     \$env:PORT="8081"; dart run bin/server.dart');
    } else {
      stderr.writeln(
        'Could not open the socket (errno $errno). Check '
        'permissions/firewall or pick another PORT.',
      );
    }
    // exit() (not just exitCode) so the process dies even though the DB
    // pool keeps sockets/timers alive after main() returns.
    exit(1);
  }

  _dispatchWithPeerAddress(server, handler);

  print(
    'ParkShare API listening on '
    'http://${server.address.host}:${server.port}',
  );
  print('Health check: http://localhost:${server.port}/health');
}

/// Accepts connections and hands each one to the shelf pipeline with the *real*
/// socket peer address bound into the request context.
///
/// SECURITY (audit H-05): `clientIpOf` is the key for the fixed-window rate
/// limiter that guards `/api/auth/login` and the password-reset endpoints.
/// `shelf`'s `Request` exposes no remote address, so without this binding the
/// only signal left would be the caller-controlled `Host`/`X-Forwarded-For`
/// headers, which lets an attacker mint a fresh bucket per request. Binding the
/// address from the [HttpServer] we own means bucket rotation is not free.
void _dispatchWithPeerAddress(HttpServer server, Handler handler) {
  server.listen(
    (HttpRequest httpRequest) {
      final peer = httpRequest.connectionInfo?.remoteAddress.address ?? 'unknown';
      shelf_io.handleRequest(
        httpRequest,
        (Request request) => handler(
              request.change(
                context: <String, Object>{'remoteAddress': peer},
              ),
            ),
      );
    },
    onError: (Object error, StackTrace stackTrace) {
      stderr.writeln('Request loop error: $error');
    },
    cancelOnError: false,
  );
}
