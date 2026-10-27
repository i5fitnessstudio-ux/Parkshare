import 'dart:typed_data';

import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/storage/media_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';

/// Handles owner parking photo uploads: multipart body -> [MediaStorage] ->
/// remote/public URL stored in the database (never local device paths).
///
/// SECURITY (audit M-02): validation is based on the file's actual leading
/// bytes, never on the multipart `Content-Type` header. The header is chosen by
/// the caller, so trusting it let any binary — an HTML page, a script, an
/// executable — be stored as "image/jpeg" and then served back from this
/// origin.
class UploadService {
  UploadService(this._storage);

  final MediaStorage _storage;

  Future<Map<String, dynamic>> uploadImage(Request request) async {
    final form = request.formData();
    if (form == null) {
      throw ApiError.validation(
        'Expected a multipart/form-data request with a "file" part.',
      );
    }

    Uint8List? bytes;
    String? declaredMime;
    try {
      // Consume the ENTIRE multipart stream (including the boundary trailer)
      // so the request body is fully drained before the response is written.
      await for (final data in form.formData) {
        if (data.name != 'file') continue;
        bytes = await data.part.readBytes();
        declaredMime = data.part.headers['content-type'];
      }
    } catch (_) {
      throw ApiError.validation('Could not read the uploaded file.');
    }

    if (bytes == null || bytes.isEmpty) {
      throw ApiError.validation('No file part named "file" was provided.');
    }
    if (bytes.length > Config.maxUploadBytes) {
      throw ApiError.payloadTooLarge(
        'File too large (max ${Config.maxUploadBytes ~/ (1024 * 1024)} MB).',
      );
    }

    // AUDIT M-02: reject known-dangerous content BEFORE the magic-byte check so
    // the message is explicit for the most common abuse, and so a file can
    // never be written to disk in the first place.
    if (looksExecutable(bytes)) {
      throw ApiError.validation(
        'Executable and script files are not accepted. Only JPG, PNG or WEBP '
        'photos are allowed.',
      );
    }

    // The authoritative check: what do the bytes actually say they are?
    final sniffed = sniffImageType(bytes);
    if (sniffed == null) {
      throw ApiError.validation(
        'Only JPG, PNG or WEBP photos are allowed. '
        'The uploaded file is not a valid image.',
      );
    }

    // The declared MIME type, when present and sane, must not contradict the
    // bytes. A mismatch is a strong signal of deliberate obfuscation.
    final declared = (declaredMime?.split(';').first.trim() ?? '')
        .toLowerCase();
    if (declared.isNotEmpty &&
        kAllowedPhotoTypes.contains(declared) &&
        declared != sniffed) {
      throw ApiError.validation(
        'The uploaded file does not match its declared type. Only JPG, PNG or '
        'WEBP photos are allowed.',
      );
    }

    final relative = await _storage.saveBytes(
      bytes,
      extension: extensionForImageType(sniffed),
    );
    return {'url': publicUrlFor(request, relative), 'relativePath': relative};
  }
}
