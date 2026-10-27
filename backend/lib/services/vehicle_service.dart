import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/vehicle.dart';
import 'package:postgres/postgres.dart';

/// Vehicle User's saved vehicles (used for fit check, booking and the
/// owner's "vehicle details" views).
class VehicleService {
  Future<Map<String, dynamic>> create({
    required String userId,
    required Map<String, dynamic> body,
  }) async {
    _validate(body);
    final vehicleType = body['vehicleType'].toString().toUpperCase();
    final isPrimary = body['isPrimary'] == true;

    final id = await Db.pool.withConnection((conn) async {
      if (isPrimary) {
        await _clearPrimary(conn, userId);
      }
      final res = await conn.execute(
        Sql.named('''
        INSERT INTO vehicles (
          user_id, vehicle_type, brand, model, registration_number,
          photo_url, length_m, width_m, height_m, is_primary
        ) VALUES (
          @userId, @vtype, @brand, @model, @reg,
          @photoUrl, @lengthM, @widthM, @heightM, @isPrimary
        )
        RETURNING id
        '''),
        parameters: {
          'userId': userId,
          'vtype': vehicleType,
          'brand': body['brand'].toString().trim(),
          'model': body['model'].toString().trim(),
          'reg': body['registrationNumber'].toString().trim(),
          'photoUrl': _strOrNull(body['photoUrl']),
          'lengthM': (body['lengthM'] as num).toDouble(),
          'widthM': (body['widthM'] as num).toDouble(),
          'heightM': (body['heightM'] as num).toDouble(),
          'isPrimary': isPrimary,
        },
      );
      return res.first.toColumnMap()['id']!.toString();
    });

    // First vehicle for the user becomes primary automatically.
    final result = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT COUNT(*) AS c FROM vehicles WHERE user_id = @uid'),
        parameters: {'uid': userId},
      );
    });
    final count = (result.first.toColumnMap()['c'] as int?) ?? 0;
    if (count == 1 && !isPrimary) {
      await Db.pool.withConnection((conn) async {
        await conn.execute(
          Sql.named('UPDATE vehicles SET is_primary = TRUE WHERE id = @id'),
          parameters: {'id': id},
        );
      });
    }
    return getById(id, userId: userId);
  }

  Future<List<Map<String, dynamic>>> listByUser(String userId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT * FROM vehicles WHERE user_id = @uid
        ORDER BY is_primary DESC, updated_at DESC
        '''),
        parameters: {'uid': userId},
      );
    });
    return res.map((r) => vehicleRowToJson(r.toColumnMap())).toList();
  }

  Future<Map<String, dynamic>> getById(
    String id, {
    required String userId,
  }) async {
    final row = await _fetchRow(id);
    if (row == null) throw ApiError.notFound('Vehicle not found.');
    if (row['user_id'].toString() != userId) {
      throw ApiError.forbidden('You can only access your own vehicles.');
    }
    return vehicleRowToJson(row);
  }

  Future<Map<String, dynamic>> update({
    required String id,
    required String userId,
    required Map<String, dynamic> body,
  }) async {
    _validate(body);
    final existing = await _fetchRow(id);
    if (existing == null) throw ApiError.notFound('Vehicle not found.');
    if (existing['user_id'].toString() != userId) {
      throw ApiError.forbidden('You can only edit your own vehicles.');
    }
    final isPrimary = body['isPrimary'] == true;

    await Db.pool.withConnection((conn) async {
      if (isPrimary) await _clearPrimary(conn, userId);
      await conn.execute(
        Sql.named('''
        UPDATE vehicles SET
          vehicle_type = @vtype, brand = @brand, model = @model,
          registration_number = @reg, photo_url = @photoUrl,
          length_m = @lengthM, width_m = @widthM, height_m = @heightM,
          is_primary = @isPrimary, updated_at = NOW()
        WHERE id = @id
        '''),
        parameters: {
          'id': id,
          'vtype': body['vehicleType'].toString().toUpperCase(),
          'brand': body['brand'].toString().trim(),
          'model': body['model'].toString().trim(),
          'reg': body['registrationNumber'].toString().trim(),
          'photoUrl': _strOrNull(body['photoUrl']),
          'lengthM': (body['lengthM'] as num).toDouble(),
          'widthM': (body['widthM'] as num).toDouble(),
          'heightM': (body['heightM'] as num).toDouble(),
          'isPrimary': isPrimary,
        },
      );
    });
    return getById(id, userId: userId);
  }

  Future<void> delete({required String id, required String userId}) async {
    final existing = await _fetchRow(id);
    if (existing == null) throw ApiError.notFound('Vehicle not found.');
    if (existing['user_id'].toString() != userId) {
      throw ApiError.forbidden('You can only delete your own vehicles.');
    }
    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('DELETE FROM vehicles WHERE id = @id'),
        parameters: {'id': id},
      );
      // If we removed the primary, promote the newest remaining vehicle.
      if (existing['is_primary'] == true) {
        await conn.execute(
          Sql.named('''
          UPDATE vehicles SET is_primary = TRUE
          WHERE user_id = @uid
            AND id = (
              SELECT id FROM vehicles WHERE user_id = @uid
              ORDER BY created_at DESC LIMIT 1
            )
        '''),
          parameters: {'uid': userId},
        );
      }
    });
  }

  // ---------------------------------------------------------------------
  // Validation + helpers
  // ---------------------------------------------------------------------
  void _validate(Map<String, dynamic> body) {
    final vtype = body['vehicleType']?.toString().toUpperCase() ?? '';
    if (!VehicleType.all.contains(vtype)) {
      throw ApiError.validation('Vehicle type must be BIKE or CAR.');
    }
    if ((body['brand']?.toString().trim() ?? '').isEmpty) {
      throw ApiError.validation('Vehicle brand is required.');
    }
    if ((body['model']?.toString().trim() ?? '').isEmpty) {
      throw ApiError.validation('Vehicle model is required.');
    }
    final reg = body['registrationNumber']?.toString().trim() ?? '';
    if (reg.isEmpty) {
      throw ApiError.validation('Vehicle registration number is required.');
    }
    final l = body['lengthM'];
    final w = body['widthM'];
    final h = body['heightM'];
    if (l is! num || w is! num || h is! num) {
      throw ApiError.validation(
        'Vehicle dimensions (length, width, height in metres) are required.',
      );
    }
    if (l <= 0 || w <= 0 || h <= 0) {
      throw ApiError.validation(
        'All vehicle dimensions must be greater than 0.',
      );
    }
  }

  Future<Map<String, dynamic>?> _fetchRow(String id) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT * FROM vehicles WHERE id = @id'),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  Future<void> _clearPrimary(dynamic conn, String userId) async {
    await conn.execute(
      Sql.named('UPDATE vehicles SET is_primary = FALSE WHERE user_id = @uid'),
      parameters: {'uid': userId},
    );
  }

  String? _strOrNull(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }
}
