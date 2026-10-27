// Tests for the media-cleanup helpers used by self-service account deletion.
//
// Account deletion removes vehicle photos and the media of listings that are
// hard-deleted. The cleanup runs AFTER the database transaction commits and
// must be best effort: [relativeUploadPath] decides whether a stored value
// points at an uploads file at all, and [LocalMediaStorage.delete] must never
// throw (a stale file can never fail an otherwise-successful deletion).
import 'dart:io';

import 'package:parkshare_backend/storage/media_storage.dart';
import 'package:test/test.dart';

void main() {
  group('relativeUploadPath', () {
    test('extracts uploads/<file> from an absolute http URL', () {
      expect(
        relativeUploadPath('http://10.0.2.2:8080/uploads/ab12.jpg'),
        'uploads/ab12.jpg',
      );
    });

    test('extracts uploads/<file> from a PUBLIC_BASE_URL value', () {
      expect(
        relativeUploadPath('https://parkshare.example.com/uploads/xy.webp'),
        'uploads/xy.webp',
      );
    });

    test('accepts a plain relative path', () {
      expect(relativeUploadPath('uploads/photo.png'), 'uploads/photo.png');
    });

    test('keeps only the first segment after uploads/', () {
      // Same last-segment discipline as serve(): a crafted multi-segment value
      // must not be able to reference a nested path.
      expect(relativeUploadPath('uploads/a/b/c.jpg'), 'uploads/a');
    });

    test('rejects .. traversal after the marker', () {
      expect(relativeUploadPath('uploads/../secret.png'), isNull);
    });

    test('rejects . as the first segment', () {
      expect(relativeUploadPath('uploads/./x.png'), isNull);
    });

    test('returns null when there is no uploads/ segment', () {
      expect(relativeUploadPath('http://host/photos/ab12.jpg'), isNull);
      expect(relativeUploadPath('/etc/passwd'), isNull);
    });

    test('returns null for an empty or missing value', () {
      expect(relativeUploadPath(null), isNull);
      expect(relativeUploadPath(''), isNull);
      expect(relativeUploadPath('   '), isNull);
    });

    test('returns null when uploads/ has no following segment', () {
      expect(relativeUploadPath('uploads/'), isNull);
      expect(relativeUploadPath('http://host/uploads/'), isNull);
    });

    test('tolerates a leading/trailing whitespace value', () {
      expect(relativeUploadPath('  uploads/ab.jpg  '), 'uploads/ab.jpg');
    });
  });

  group('LocalMediaStorage.delete', () {
    late Directory temp;
    late LocalMediaStorage storage;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('parkshare_media_test_');
      storage = LocalMediaStorage(directory: temp.path);
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('deletes only the last path segment referenced by the URL', () async {
      final file = File('${temp.path}${Platform.pathSeparator}keepme.jpg');
      await file.writeAsBytes([1, 2, 3]);
      final other = File('${temp.path}${Platform.pathSeparator}other.jpg');
      await other.writeAsBytes([4, 5, 6]);

      await storage.delete('http://host/uploads/keepme.jpg');

      expect(file.existsSync(), isFalse);
      expect(other.existsSync(), isTrue, reason: 'unrelated files stay');
    });

    test('is a silent no-op for null / non-uploads values', () async {
      await expectLater(storage.delete(null), completes);
      await expectLater(storage.delete(''), completes);
      await expectLater(storage.delete('http://host/photos/x.jpg'), completes);
      await expectLater(storage.delete('uploads/../escape.jpg'), completes);
    });

    test('never throws when the file is absent', () async {
      await expectLater(
        storage.delete('http://host/uploads/does-not-exist.jpg'),
        completes,
      );
    });
  });
}