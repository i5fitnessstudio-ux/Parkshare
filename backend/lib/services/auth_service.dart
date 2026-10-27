import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/user.dart';
import 'package:postgres/postgres.dart';

/// Password reset via OTP/email delivery is not used by the active
/// ParkShare authentication flow.

/// Authentication domain service.
///
/// Owns: register, login, refresh, me, logout. All DB writes go through PostgreSQL.
class AuthService {
  static const _roles = UserRole.all;

  /// Passwords that are long enough to pass the length check but are trivially
  /// guessable. Checked on register and on reset (audit M-10).
  static const _commonPasswords = {
    'password',
    'password1',
    'password123',
    '12345678',
    '123456789',
    '1234567890',
    'qwerty123',
    'admin123',
    'welcome1',
    'iloveyou',
    'parkshare',
    'parkshare123',
    'letmein1',
    'abc12345',
  };
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  /// UPI virtual payment address: `local@bank`, no spaces, no `+`.
  static final _upiRegex = RegExp(r'^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9._-]{2,64}$');
  static final _random = Random.secure();

  // ---------------------------------------------------------------------
  // Register
  // ---------------------------------------------------------------------
  /// Creates an account.
  ///
  /// [upiId] is the account's own UPI address and is OPTIONAL for every role.
  ///
  /// The active online flow is Razorpay Checkout, which settles to the
  /// marketplace and pays owners through their bank account details; a direct
  /// owner UPI id is only legacy metadata. Requiring it at registration blocked
  /// owners who use the live payment method, so it is no longer enforced.
  Future<AuthPayload> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
    String? upiId,
    String? confirmPassword,
  }) async {
    final rName = name.trim();
    final rEmail = email.trim().toLowerCase();
    final rPhone = phone.trim();
    final rRole = role.trim().toLowerCase();
    final rUpi = (upiId ?? '').trim();

    if (rName.isEmpty) throw ApiError.validation('Full name is required.');
    if (rName.length < 2) {
      throw ApiError.validation('Name must be at least 2 characters.');
    }
    if (rEmail.isEmpty || !_emailRegex.hasMatch(rEmail)) {
      throw ApiError.validation('A valid email address is required.');
    }
    if (rPhone.isEmpty) throw ApiError.validation('Phone number is required.');
    _assertPasswordAcceptable(password);
    if (!_roles.contains(rRole)) {
      throw ApiError.validation('Role must be either "user" or "owner".');
    }
    // The merged Create Account page posts one form; the server still
    // re-checks the confirmation so the rule can never be bypassed.
    final confirm = confirmPassword?.trim() ?? '';
    if (confirm.isNotEmpty && confirm != password) {
      throw ApiError.validation('Passwords do not match.');
    }

    // UPI is optional for all roles. The Razorpay online flow does not require
    // a direct owner UPI id; bank details are stored separately via
    // owner_payment_accounts for settlement where applicable.
    String? upiToStore;
    if (rUpi.isNotEmpty) {
      if (!_upiRegex.hasMatch(rUpi)) {
        throw ApiError.validation(
          'Enter a valid UPI ID (e.g. yourname@bank).',
        );
      }
      // Store as typed but canonicalised to lower case, which is how UPI apps
      // compare payee addresses.
      upiToStore = rUpi.toLowerCase();
    }

    final existing = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT 1 FROM users WHERE email = @email'),
        parameters: {'email': rEmail},
      );
    });
    if (existing.isNotEmpty) {
      throw ApiError.conflict('An account with this email already exists.');
    }

    final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());

    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('''
        INSERT INTO users (name, email, phone, upi_id, password_hash, role)
        VALUES (@name, @email, @phone, @upi, @hash, @role)
        '''),
        parameters: {
          'name': rName,
          'email': rEmail,
          'phone': rPhone,
          'upi': upiToStore,
          'hash': passwordHash,
          'role': rRole,
        },
      );
    });

    final user = await _findUserByEmail(rEmail);
    if (user == null) {
      throw ApiError.server('Account created but could not be loaded.');
    }
    final tokens = await _issueTokenPair(user);
    return AuthPayload(user: user, tokens: tokens);
  }

  // ---------------------------------------------------------------------
  // Login
  // ---------------------------------------------------------------------
  Future<AuthPayload> login({
    required String email,
    required String password,
    String? role,
  }) async {
    final rEmail = email.trim().toLowerCase();
    if (rEmail.isEmpty || password.isEmpty) {
      throw ApiError.validation('Email and password are required.');
    }
    final user = await _findUserByEmail(rEmail);
    if (user == null) {
      // Burn a comparable amount of CPU so a missing account is not
      // distinguishable from a wrong password by response time.
      await _dummyPasswordWork();
      throw ApiError.unauthorized('Invalid email or password.');
    }
    final passwordHash = await _passwordHashOf(user.id);
    if (passwordHash == null || !BCrypt.checkpw(password, passwordHash)) {
      throw ApiError.unauthorized('Invalid email or password.');
    }
    if (!user.isActive) {
      throw ApiError.forbidden('This account has been deactivated.');
    }
    if (role != null && user.role != role) {
      throw ApiError.forbidden(
        'This account is registered as a ${user.role}, not a $role.',
      );
    }
    final tokens = await _issueTokenPair(user);
    return AuthPayload(user: user, tokens: tokens);
  }

  /// Runs a bcrypt verification against a throwaway hash.
  ///
  /// Only used to equalise the cost of the "no such account" branch, so login
  /// cannot be used as user-enumeration oracles through timing.
  Future<void> _dummyPasswordWork() async {
    try {
      BCrypt.checkpw('parkshare-timing-equaliser', _dummyHash);
    } catch (_) {
      // Never let the equaliser change the outcome of a request.
    }
  }

  late final String _dummyHash = BCrypt.hashpw(
    'parkshare-timing-equaliser',
    BCrypt.gensalt(),
  );

  // ---------------------------------------------------------------------
  // Refresh (rotation)
  // ---------------------------------------------------------------------
  Future<AuthPayload> refresh(String refreshToken) async {
    if (refreshToken.isEmpty) {
      throw ApiError.unauthorized('Refresh token is required.');
    }
    final tokenHash = _sha256(refreshToken);
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT rt.user_id, u.email, u.name, u.phone, u.upi_id, u.role,
               u.is_active, u.deleted_at, u.created_at,
               rt.expires_at, rt.revoked_at
        FROM refresh_tokens rt
        JOIN users u ON u.id = rt.user_id
        WHERE rt.token_hash = @hash
        '''),
        parameters: {'hash': tokenHash},
      );
    });
    if (res.isEmpty) {
      throw ApiError.unauthorized('Invalid refresh token.');
    }
    final row = res.first.toColumnMap();
    if (row['revoked_at'] != null) {
      throw ApiError.unauthorized('Refresh token has been revoked.');
    }
    final expiresAt = row['expires_at'] as DateTime;
    if (expiresAt.isBefore(DateTime.now().toUtc())) {
      throw ApiError.unauthorized('Refresh token has expired.');
    }
    // A deactivated or deleted account must NOT be re-authenticated through a
    // still-valid refresh token. The message is deliberately the SAME generic
    // wording used for an unknown token, so this endpoint cannot be used as an
    // account-status oracle.
    final isActive = row['is_active'] == true || row['is_active'] == 't';
    if (!isActive || row['deleted_at'] != null) {
      throw ApiError.unauthorized('Invalid refresh token.');
    }
    final user = User(
      id: row['user_id'].toString(),
      name: row['name'] as String,
      email: row['email'] as String,
      phone: row['phone'] as String?,
      upiId: _cleanUpi(row['upi_id']),
      role: row['role'] as String,
      isActive: row['is_active'] == true || row['is_active'] == 't',
      createdAt: row['created_at'] as DateTime,
    );
    // Rotate: revoke the presented token, issue a fresh pair.
    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named(
          'UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = @hash',
        ),
        parameters: {'hash': tokenHash},
      );
    });
    final tokens = await _issueTokenPair(user);
    return AuthPayload(user: user, tokens: tokens);
  }

  // ---------------------------------------------------------------------
  // Me
  // ---------------------------------------------------------------------
  Future<User> me(String userId) async {
    final user = await _findUserById(userId);
    if (user == null) throw ApiError.notFound('User not found.');
    if (!user.isActive) {
      throw ApiError.forbidden('This account has been deactivated.');
    }
    return user;
  }

  // ---------------------------------------------------------------------
  // Logout (revoke refresh token)
  // ---------------------------------------------------------------------
  Future<void> logout(String refreshToken) async {
    if (refreshToken.isEmpty) return;
    final tokenHash = _sha256(refreshToken);
    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named(
          'UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_hash = @hash AND revoked_at IS NULL',
        ),
        parameters: {'hash': tokenHash},
      );
    });
  }

  // Password reset via OTP/email delivery is not used by the active
  // authentication flow. Methods removed.

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------
  Future<User?> _findUserByEmail(String email) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT id::text AS id, name, email, phone, upi_id, role, is_active,
               created_at
        FROM users WHERE email = @email AND deleted_at IS NULL
        '''),
        parameters: {'email': email},
      );
    });
    if (res.isEmpty) return null;
    return User.fromMap(res.first.toColumnMap());
  }

  Future<User?> _findUserById(String id) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT id::text AS id, name, email, phone, upi_id, role, is_active,
               created_at
        FROM users WHERE id = @id AND deleted_at IS NULL
        '''),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return User.fromMap(res.first.toColumnMap());
  }

  Future<String?> _passwordHashOf(String userId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT password_hash FROM users WHERE id = @id'),
        parameters: {'id': userId},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap()['password_hash'] as String?;
  }

  /// Shared password policy for register and reset (audit M-10).
  static void _assertPasswordAcceptable(String password) {
    if (password.length < Config.minPasswordLength) {
      throw ApiError.validation(
        'Password must be at least ${Config.minPasswordLength} characters.',
      );
    }
    if (_commonPasswords.contains(password.toLowerCase())) {
      throw ApiError.validation(
        'That password is too common. Please choose something harder to guess.',
      );
    }
  }

  /// Issues a new access + refresh token pair, persisting the refresh token
  /// (stored hashed) in PostgreSQL.
  ///
  /// SECURITY (audit H-04): both tokens now carry real `iat`/`exp` claims.
  /// Previously only `sub`, `role`, `type` and `jti` were signed, so an access
  /// token had **no expiry at all** — `JWT_ACCESS_EXPIRES_MINUTES` was
  /// reported to the client but not enforced anywhere, and a leaked token was
  /// valid forever. `dart_jsonwebtoken` rejects an expired `exp` during
  /// `JWT.verify`, which the auth middleware calls.
  Future<TokenPair> _issueTokenPair(User user) async {
    final now = DateTime.now().toUtc();
    final accessExpires = now.add(
      Duration(minutes: Config.accessExpiryMinutes),
    );
    final refreshExpires = now.add(Duration(days: Config.refreshTokenDays));
    final jti = _randomTokenId();

    final accessToken = JWT({
      'sub': user.id,
      'role': user.role,
      'type': 'access',
      'jti': jti,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': accessExpires.millisecondsSinceEpoch ~/ 1000,
    }).sign(SecretKey(Config.jwtSecret), algorithm: JWTAlgorithm.HS256);

    final refreshToken = JWT({
      'sub': user.id,
      'role': user.role,
      'type': 'refresh',
      'jti': jti,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': refreshExpires.millisecondsSinceEpoch ~/ 1000,
    }).sign(SecretKey(Config.jwtSecret), algorithm: JWTAlgorithm.HS256);

    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('''
        INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
        VALUES (@uid, @hash, @expires)
        '''),
        parameters: {
          'uid': user.id,
          'hash': _sha256(refreshToken),
          'expires': refreshExpires,
        },
      );
    });

    return TokenPair(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessExpiresAt: accessExpires,
      refreshExpiresAt: refreshExpires,
    );
  }

  String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();

  /// Normalises a stored UPI id: trims, lower-cases and turns an empty /
  /// placeholder value into `null` so the client can say "not configured".
  static String? _cleanUpi(Object? raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    if (value.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9._-]{2,64}$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  /// 32-char random token id (hex) used as the JWT `jti` claim so that
  /// tokens issued within the same second are never identical.
  String _randomTokenId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }


}
