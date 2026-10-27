import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';

/// Where a photo comes from (owner parking photo flow).
enum PhotoSource { camera, gallery }

class PickedPhoto {
  final Uint8List bytes;
  final String filename;
  final String contentType;

  const PickedPhoto({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  String get extension {
    final dot = filename.lastIndexOf('.');
    return dot >= 0 ? filename.substring(dot + 1).toLowerCase() : 'jpg';
  }
}

/// Abstraction over photo picking so tests can inject a deterministic source.
abstract class PhotoPickerService {
  /// Picks (camera or gallery) a single photo, downscaled to a sane size.
  /// Returns null if the user cancels.
  Future<PickedPhoto?> pick(PhotoSource source);
}

/// Production implementation backed by image_picker (camera + gallery).
class ImagePickerPhotoService implements PhotoPickerService {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    final xfile = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (xfile == null) return null;
    final bytes = await xfile.readAsBytes();
    if (bytes.isEmpty) return null;
    return PickedPhoto(
      bytes: bytes,
      filename: xfile.name.isEmpty ? 'photo.jpg' : xfile.name,
      contentType: _contentTypeFor(xfile.name, bytes),
    );
  }

  String _contentTypeFor(String name, Uint8List bytes) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    // JPEG magic check (robust for photos saved with odd names).
    if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'image/jpeg';
    }
    if (bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    return lower.endsWith('.jpg') ? 'image/jpeg' : 'image/jpeg';
  }
}

/// Deterministic picker for integration tests: returns a bundled asset
/// photo. Activated with `--dart-define=E2E_TEST=true`.
class E2EPhotoPickerService implements PhotoPickerService {
  final Uint8List? _bytes;

  E2EPhotoPickerService({this._bytes});

  static const String assetName = 'assets/test/parking_photo.png';

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    final bytes = _bytes ?? await _loadBundledPhoto();
    if (bytes == null || bytes.isEmpty) return null;
    return PickedPhoto(
      bytes: bytes,
      filename: 'parking_photo.png',
      contentType: 'image/png',
    );
  }

  Future<Uint8List?> _loadBundledPhoto() async {
    try {
      final data = await rootBundle.load(assetName);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}

/// Creates the picker for the running mode. Integration tests launch with
/// `--dart-define=E2E_TEST=true` and get the deterministic asset picker.
class PhotoPickerFactory {
  PhotoPickerFactory._();

  static const bool _e2e = bool.fromEnvironment('E2E_TEST');

  static PhotoPickerService create() =>
      _e2e ? E2EPhotoPickerService() : ImagePickerPhotoService();
}
