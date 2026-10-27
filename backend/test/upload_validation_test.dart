// Regression tests for audit M-02 / M-03 / M-04 (untrusted file uploads).
//
// Before the fix the upload endpoint trusted the multipart `Content-Type`
// header and appended the *client supplied* filename, so any binary could be
// stored as "image/jpeg" (and an .html/.svg/.js file could be stored verbatim
// and then served back from this origin).
import 'dart:convert';
import 'dart:io';

import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/storage/media_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Minimal but structurally valid PNG header (magic bytes + IHDR).
List<int> pngBytes({int length = 64}) {
  return <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
    0x00, 0x00, 0x00, 0x0D, // IHDR length
    ...List<int>.filled(length - 13, 0x41),
  ];
}

List<int> jpegBytes({int length = 64}) {
  return <int>[
    0xFF, 0xD8, 0xFF, 0xE0, ...List<int>.filled(length - 4, 0x00),
  ];
}

List<int> webpBytes({int length = 64}) {
  return <int>[
    0x52, 0x49, 0x46, 0x46, // RIFF
    0x1A, 0x00, 0x00, 0x00, // size
    0x57, 0x45, 0x42, 0x50, // WEBP
    ...List<int>.filled(length - 12, 0x00),
  ];
}

void main() {
  group('sniffImageType recognises images from their leading bytes', () {
    test('JPEG', () => expect(sniffImageType(jpegBytes()), 'image/jpeg'));
    test('PNG', () => expect(sniffImageType(pngBytes()), 'image/png'));
    test('WEBP', () => expect(sniffImageType(webpBytes()), 'image/webp'));
  });

  test('sniffImageType rejects non-images', () {
    expect(sniffImageType(utf8.encode('<!DOCTYPE html><html>x</html>')), isNull);
    expect(sniffImageType(utf8.encode('GIF89a....')), isNull);
    expect(sniffImageType(List<int>.filled(64, 0x41)), isNull);
    expect(sniffImageType(<int>[]), isNull);
  });

  test('sniffImageType needs enough bytes to decide', () {
    // A truncated header must never be accepted on the strength of 3 bytes.
    expect(sniffImageType([0xFF, 0xD8, 0xFF]), isNull);
    expect(sniffImageType([0x89, 0x50, 0x4E]), isNull);
  });

  group('looksExecutable short-circuits dangerous containers', () {
    test('Windows PE (MZ)', () {
      expect(looksExecutable([0x4D, 0x5A, 0x90, 0x00]), isTrue);
    });

    test('ELF binary', () {
      expect(looksExecutable([0x7F, 0x45, 0x4C, 0x46]), isTrue);
    });

    test('Mach-O (both magics)', () {
      expect(looksExecutable([0xCF, 0xFA, 0xED, 0xFE]), isTrue);
      expect(looksExecutable([0xCA, 0xFE, 0xBA, 0xBE]), isTrue);
    });

    test('Java class / jar', () {
      expect(looksExecutable([0xCA, 0xFE, 0xBA, 0xBE]), isTrue);
      expect(looksExecutable([0xCA, 0xFE, 0xD0, 0x0D]), isTrue);
    });

    test('ZIP container (.jar/.apk/.docm)', () {
      expect(looksExecutable([0x50, 0x4B, 0x03, 0x04]), isTrue);
    });

    test('PDF', () {
      expect(looksExecutable(utf8.encode('%PDF-1.7')), isTrue);
    });

    test('shell shebang', () {
      expect(looksExecutable(utf8.encode('#!/bin/sh\nrm -rf /')), isTrue);
    });

    test('HTML, XML and SVG served as text', () {
      expect(looksExecutable(utf8.encode('<!DOCTYPE html><html>')), isTrue);
      expect(looksExecutable(utf8.encode('  <html lang="en">')), isTrue);
      expect(looksExecutable(utf8.encode('<?xml version="1.0"?>')), isTrue);
      expect(looksExecutable(utf8.encode('<svg xmlns="...">')), isTrue);
    });

    test('a real photo is NOT flagged as executable', () {
      expect(looksExecutable(pngBytes()), isFalse);
      expect(looksExecutable(jpegBytes()), isFalse);
      expect(looksExecutable(webpBytes()), isFalse);
    });
  });

  group('extensionForImageType is derived from the bytes, never from input', () {
    test('maps the three accepted types', () {
      expect(extensionForImageType('image/png'), '.png');
      expect(extensionForImageType('image/webp'), '.webp');
      expect(extensionForImageType('image/jpeg'), '.jpg');
    });

    test('the allow-list and the forbidden list cannot overlap', () {
      final produced = kAllowedPhotoTypes.map(extensionForImageType).toSet();
      for (final ext in produced) {
        expect(
          kForbiddenUploadExtensions.contains(ext.toLowerCase()),
          isFalse,
          reason: '$ext is both producible and forbidden',
        );
      }
    });

    test('every forbidden extension is a lowercase dotted suffix', () {
      for (final ext in kForbiddenUploadExtensions) {
        expect(ext, startsWith('.'));
        expect(ext, ext.toLowerCase());
      }
    });

    test('the dangerous classics are all covered', () {
      for (final ext in [
        '.php', '.jsp', '.html', '.svg', '.js', '.exe', '.apk', '.hta',
      ]) {
        expect(kForbiddenUploadExtensions, contains(ext));
      }
    });
  });

  group('LocalMediaStorage', () {
    late Directory sandbox;
    late Directory uploadDir;
    late LocalMediaStorage storage;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('parkshare_upload_test');
      uploadDir = Directory('${sandbox.path}/uploads')..createSync(recursive: true);
      storage = LocalMediaStorage(directory: uploadDir.path);
    });

    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    test('saveBytes produces an unguessable, collision-free name', () async {
      final names = <String>{};
      for (var i = 0; i < 12; i++) {
        final relative = await storage.saveBytes(pngBytes(), extension: '.png');
        names.add(relative);
        expect(relative, startsWith('uploads/'));
        expect(relative, matches(RegExp(r'^uploads/[A-Za-z0-9]+\.png$')));
        expect(File('${uploadDir.path}/${relative.split('/').last}').existsSync(), isTrue);
      }
      expect(names.length, 12, reason: 'names must be unique');
    });

    test('saveBytes refuses to exceed the configured size budget', () async {
      final tiny = LocalMediaStorage(directory: uploadDir.path);
      // 8 MiB default budget; allocate one byte over the limit.
      final tooBig = List<int>.filled(8 * 1024 * 1024 + 1, 0);
      await expectLater(
        tiny.saveBytes(tooBig, extension: '.png'),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 413)),
      );
    });

    group('serve refuses to escape the upload directory', () {
      test('a traversal segment cannot reach the parent directory', () async {
        File('${sandbox.path}/secret.txt').writeAsStringSync('TOP SECRET');
        final response = await storage.serve(
          Request('GET', Uri.parse('http://localhost/uploads/../secret.txt')),
        );
        expect(response.statusCode, 404);
        expect(await response.readAsString(), isNot(contains('TOP SECRET')));
      });

      test('an absolute-ish traversal is neutralised', () async {
        File('${sandbox.path}/secret.txt').writeAsStringSync('TOP SECRET');
        final response = await storage.serve(
          Request('GET', Uri.parse('http://localhost/uploads/..%2Fsecret.txt')),
        );
        expect(response.statusCode, 404);
      });

      test('a sibling directory with a shared prefix is not reachable', () async {
        // `uploads-backup` starts with `uploads`, so a bare startsWith() guard
        // would have allowed this. Canonical comparison must not.
        final sibling = Directory('${sandbox.path}/uploads-backup');
        sibling.createSync(recursive: true);
        File('${sibling.path}/leak.txt').writeAsStringSync('LEAKED');
        final response = await storage.serve(
          Request('GET', Uri.parse('http://localhost/uploads/leak.txt')),
        );
        // The last path segment is resolved *inside* uploads/, and no such
        // file exists there, so this is a clean 404.
        expect(response.statusCode, 404);
        expect(await response.readAsString(), isNot(contains('LEAKED')));
      });

      test('a missing file is a 404', () async {
        final response = await storage.serve(
          Request('GET', Uri.parse('http://localhost/uploads/nope.png')),
        );
        expect(response.statusCode, 404);
      });
    });

    group('serve sends safe headers', () {
      test('a known image gets its real content type plus nosniff', () async {
        await storage.saveBytes(pngBytes(), extension: '.png');
        final name = uploadDir.listSync().first.uri.pathSegments.last;
        final response = await storage.serve(
          Request('GET', Uri.parse('http://localhost/uploads/$name')),
        );

        expect(response.statusCode, 200);
        expect(response.headers['content-type'], 'image/png');
        expect(response.headers['x-content-type-options'], 'nosniff');
        expect(response.headers['content-disposition'], contains('inline;'));
        expect(response.headers['cache-control'], 'public, max-age=86400');
      });

      test('an unknown extension is served as octet-stream, never guessed', () async {
        File('${uploadDir.path}/weird.pngx').writeAsBytesSync(pngBytes());
        final response = await storage.serve(
          Request('GET', Uri.parse('http://localhost/uploads/weird.pngx')),
        );
        expect(response.statusCode, 200);
        expect(
          response.headers['content-type'],
          'application/octet-stream',
          reason: 'an unknown type must be inert, not sniffed as an image',
        );
        expect(response.headers['x-content-type-options'], 'nosniff');
      });

      test('a stored .html would be served as octet-stream + nosniff', () async {
        // Defence in depth: even if such a file ever lands on disk it is not
        // rendered as a document by the browser.
        File('${uploadDir.path}/x.html')
            .writeAsStringSync('<script>alert(1)</script>');
        final response = await storage.serve(
          Request('GET', Uri.parse('http://localhost/uploads/x.html')),
        );
        expect(response.headers['content-type'], 'application/octet-stream');
        expect(response.headers['x-content-type-options'], 'nosniff');
      });
    });
  });
}
