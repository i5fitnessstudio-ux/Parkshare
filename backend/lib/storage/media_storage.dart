import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:shelf/shelf.dart';

/// Storage abstraction for uploaded media (owner parking photos).
///
/// The database must never store permanent local device paths. Instead the
/// owner app uploads the photo bytes to the backend, [MediaStorage] persists
/// the file, and the database stores a remote/public URL to the file.
abstract class MediaStorage {
  /// Persists [bytes] and returns a relative URL path such as
  /// `uploads/ab12...jpg` (served under `GET <base>/uploads/<file>`).
  Future<String> saveBytes(List<int> bytes, {required String extension});

  /// Resolves a relative `uploads/...` path to a browsable file response.
  Future<Response> serve(Request request);

  /// Deletes the file behind a stored URL or relative path (e.g.
  /// `http://host/uploads/ab12.jpg` or `uploads/ab12.jpg`).
  ///
  /// BEST EFFORT, NEVER THROWS: account deletion calls this AFTER the database
  /// transaction has committed, so a disk failure here must not turn a
  /// successful deletion into an error for the caller.
  Future<void> delete(String? urlOrPath);
}

/// Filesystem-backed [MediaStorage] for development / single-node hosting.
///
/// Swap this for S3/Cloud Storage in production without touching routes —
/// the API only ever sees [MediaStorage].
class LocalMediaStorage implements MediaStorage {
  final Directory _dir;

  LocalMediaStorage({String? directory})
    : _dir = Directory(directory ?? Config.uploadDir);

  /// AUDIT M-07: filenames must be unguessable, so this is the CSPRNG rather
  /// than the predictable `Random()` that was used before.
  static final Random _random = Random.secure();

  @override
  Future<String> saveBytes(List<int> bytes, {required String extension}) async {
    if (bytes.length > Config.maxUploadBytes) {
      throw ApiError.payloadTooLarge(
        'File too large (max ${Config.maxUploadBytes ~/ (1024 * 1024)} MB).',
      );
    }
    if (!_dir.existsSync()) {
      _dir.createSync(recursive: true);
    }
    final name = _randomName() + extension;
    final file = File('${_dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return 'uploads/$name';
  }

  @override
  Future<Response> serve(Request request) async {
    // Only the LAST path segment is honoured, so `..` segments cannot climb
    // out of the directory: `uploads/../x.png` resolves to `<root>/x.png`.
    final name = request.url.path.split('/').last;
    final file = File('${_dir.path}${Platform.pathSeparator}$name');
    // AUDIT M-03: the guard used to be a bare `startsWith(uploadRoot)`, which
    // also matches sibling directories such as `uploads-backup`. Compare
    // canonicalised paths and require a separator boundary instead.
    //
    // AUDIT FIX: the path must be joined with `Platform.pathSeparator`. Joining
    // with a literal '/' produced `C:\dir/uploads/x.png` while the root was
    // `C:\dir\uploads`, so `startsWith('C:\dir\uploads\')` was false and EVERY
    // legitimate upload returned 404 on Windows.
    final root = _dir.absolute.path;
    final resolved = file.absolute.path;
    final insideRoot =
        resolved == root || resolved.startsWith('$root${Platform.pathSeparator}');
    if (!insideRoot || !file.existsSync()) {
      return ApiResponse.notFound('File not found.');
    }
    final bytes = await file.readAsBytes();
    return Response.ok(
      bytes,
      headers: {
        'content-type': _contentType(file.path),
        'cache-control': 'public, max-age=86400',
        // Belt and braces with securityHeadersMiddleware: never let a browser
        // sniff an uploaded file into something executable.
        'x-content-type-options': 'nosniff',
        'content-disposition': 'inline; filename="${
          file.uri.pathSegments.isEmpty ? 'photo' : file.uri.pathSegments.last
        }"',
      },
    );
  }

  static String _contentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        // AUDIT M-04: never guess. `application/octet-stream` plus the global
        // `nosniff` header means an unknown file is inert instead of being
        // rendered as an image by a browser's sniffing.
        return 'application/octet-stream';
    }
  }

  @override
  Future<void> delete(String? urlOrPath) async {
    final relative = relativeUploadPath(urlOrPath);
    if (relative == null) return;
    // Only the LAST path segment is ever referenced on disk — the same rule
    // [serve] follows — so `..` segments cannot climb out of the directory.
    final name = relative.split('/').last;
    if (name.isEmpty || name == '.' || name == '..') return;
    try {
      final file = File('${_dir.path}${Platform.pathSeparator}$name');
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {
      // Best effort only. Deliberately swallowed: the data deletion already
      // committed in PostgreSQL and a stale file must not fail the request.
    }
  }

  static String _randomName() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  }
}

/// Builds the absolute public URL for a stored file, honouring
/// `PUBLIC_BASE_URL` when configured (production). In development the URL is
/// derived from the request host so it works on the Android emulator
/// (10.0.2.2:8080) and the iOS simulator (localhost:8080).
///
/// AUDIT M-03: `Config.validateForStartup()` REFUSES to start in production
/// without `PUBLIC_BASE_URL`, because deriving the base from the request's
/// `Host` header lets a caller with a valid token persist attacker-chosen
/// photo URLs into the database.
String publicUrlFor(Request request, String relativePath) {
  final base = Config.publicBaseUrl.isNotEmpty
      ? Config.publicBaseUrl.replaceAll(RegExp(r'/$'), '')
      : 'http://${request.requestedUri.host}:${request.requestedUri.port}';
  return '$base/$relativePath';
}

/// Extracts the `uploads/<file>` relative path from a stored URL or path.
///
/// The database stores full URLs (`http://host/uploads/ab12.jpg` or
/// `PUBLIC_BASE_URL/uploads/ab12.jpg`) plus, in legacy rows, plain relative
/// paths. Only the FIRST segment after `uploads/` is ever used — the same
/// last-segment discipline as [LocalMediaStorage.serve] — so a crafted value
/// cannot climb out of the uploads directory (`uploads/../x` → `uploads/x`).
///
/// Returns null when the value is empty or contains no usable `uploads/`
/// segment; callers (media cleanup after account deletion) treat null as
/// "nothing to delete".
String? relativeUploadPath(String? urlOrPath) {
  final raw = (urlOrPath ?? '').trim();
  if (raw.isEmpty) return null;
  final marker = 'uploads/';
  final idx = raw.indexOf(marker);
  if (idx < 0) return null;
  final rest = raw.substring(idx + marker.length);
  final segments = rest
      .split('/')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (segments.isEmpty) return null;
  final first = segments.first;
  if (first == '.' || first == '..') return null;
  return '$marker$first';
}

/// Allowed media types for owner parking photos.
const Set<String> kAllowedPhotoTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
};

/// File extensions that must never be accepted, whatever the bytes say.
///
/// AUDIT M-02. Nothing in the pipeline can currently produce one of these
/// (the extension is derived from the sniffed type), but the list makes the
/// intent explicit and guards future changes to the storage layer.
const Set<String> kForbiddenUploadExtensions = {
  '.php', '.phtml', '.phar', '.asp', '.aspx', '.jsp', '.cgi', '.pl', '.py',
  '.rb', '.sh', '.bash', '.exe', '.dll', '.so', '.bat', '.cmd', '.com', '.msi',
  '.jar', '.apk', '.html', '.htm', '.xhtml', '.svg', '.js', '.mjs',
  '.swf', '.hta', '.ps1',
};

/// Recognises an image purely from its **leading bytes** (the "magic bytes").
///
/// Returns the canonical MIME type, or null when the content is not one of the
/// three formats the app accepts. AUDIT M-02: this replaces trusting the
/// caller-supplied multipart `Content-Type` header.
String? sniffImageType(List<int> bytes) {
  if (bytes.length < 12) return null;

  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }

  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }

  // WEBP: "RIFF" .... "WEBP"
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }

  return null;
}

/// The storage extension for a sniffed image type. Deliberately derived from
/// the bytes, never from user input.
String extensionForImageType(String mime) => switch (mime) {
  'image/png' => '.png',
  'image/webp' => '.webp',
  _ => '.jpg',
};

/// True when the leading bytes match a known executable/script/document
/// container (AUDIT M-02). This is a short-circuit for a clear error message,
/// not the primary control — [sniffImageType] is what actually decides.
bool looksExecutable(List<int> bytes) {
  if (bytes.length < 4) return false;

  // MZ (Windows PE/DOS), ELF, Mach-O, Java class, shebang, PK (zip-based
  // formats such as .jar/.apk/.docm), PDF.
  if (bytes[0] == 0x4D && bytes[1] == 0x5A) return true; // MZ
  if (bytes[0] == 0x7F &&
      bytes[1] == 0x45 &&
      bytes[2] == 0x4C &&
      bytes[3] == 0x46) {
    return true; // ELF
  }
  if (bytes[0] == 0xCF &&
      bytes[1] == 0xFA &&
      bytes[2] == 0xED &&
      bytes[3] == 0xFE) {
    return true; // Mach-O
  }
  if (bytes[0] == 0xCA &&
      bytes[1] == 0xFE &&
      bytes[2] == 0xBA &&
      bytes[3] == 0xBE) {
    return true; // Mach-O (fat)
  }
  if (bytes[0] == 0xCA &&
      bytes[1] == 0xFE &&
      bytes[2] == 0xD0 &&
      bytes[3] == 0x0D) {
    return true; // Java class
  }
  if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
    return true; // %PDF
  }
  if (bytes[0] == 0x23 && bytes[1] == 0x21) return true; // #! shebang
  if (bytes[0] == 0x50 && bytes[1] == 0x4B) return true; // PK zip container

  // HTML/XML/SVG served as text.
  final head = String.fromCharCodes(bytes.take(256)).trimLeft().toLowerCase();
  if (head.startsWith('<!doctype html') ||
      head.startsWith('<html') ||
      head.startsWith('<?xml') ||
      head.startsWith('<svg')) {
    return true;
  }
  return false;
}
