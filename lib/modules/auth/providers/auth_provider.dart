import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/storage/token_storage.dart';
import '../../../shared/models/user.dart';
import '../models/auth_models.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

/// Outcome of a session restore attempt.
enum RestoreStatus { authenticated, unauthenticated, failed }

/// Application-wide authentication state.
class AuthProvider extends ChangeNotifier {
  final AuthService authService;
  final TokenStorage tokenStorage;
  final SessionStorage sessionStorage;

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  String? _accessToken;
  String? _refreshToken;

  AuthProvider({
    required this.authService,
    required this.tokenStorage,
    required this.sessionStorage,
  });

  AuthStatus get status => _status;
  User? get user => _user;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isUnknown => _status == AuthStatus.unknown;

  Future<RestoreStatus> restoreSession() async {
    final hasTokens = await tokenStorage.hasTokens();
    if (!hasTokens) {
      await _setUnauthenticated();
      return RestoreStatus.unauthenticated;
    }

    final access = await tokenStorage.getAccessToken();
    final refresh = await tokenStorage.getRefreshToken();
    _accessToken = access;
    _refreshToken = refresh;

    try {
      _user = await authService.me(access!);
      _status = AuthStatus.authenticated;
      await sessionStorage.saveSession(_user!);
      notifyListeners();
      return RestoreStatus.authenticated;
    } on ApiException catch (e) {
      if (!e.isAuthError) {
        _status = AuthStatus.unknown;
        notifyListeners();
        return RestoreStatus.failed;
      }
    } catch (_) {
      _status = AuthStatus.unknown;
      notifyListeners();
      return RestoreStatus.failed;
    }

    try {
      final result = await authService.refresh(refresh!);
      await _persistSession(result);
      return RestoreStatus.authenticated;
    } on ApiException {
      await _clearSession();
      return RestoreStatus.unauthenticated;
    } catch (_) {
      await _clearSession();
      return RestoreStatus.unauthenticated;
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
    String? upiId,
  }) async {
    final result = await authService.register(
      name: name,
      email: email,
      phone: phone,
      password: password,
      role: role,
      upiId: upiId,
    );
    await _persistSession(result);
  }

  Future<void> login({
    required String email,
    required String password,
    String? role,
  }) async {
    final result = await authService.login(
      email: email,
      password: password,
      role: role,
    );
    await _persistSession(result);
  }

  Future<ForgotPasswordResult> forgotPassword(String email) {
    return authService.forgotPassword(email);
  }

  Future<void> verifyResetOtp(String email, String otp) {
    return authService.verifyResetOtp(email, otp);
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) {
    return authService.resetPassword(
      email: email,
      otp: otp,
      newPassword: newPassword,
    );
  }

  Future<void> logout() async {
    final refresh = _refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await authService.logout(refresh);
      } catch (_) {}
    }
    await _clearSession();
  }

  Future<void> clearAuthForTesting() async {
    await _clearSession();
  }

  /// Permanently deletes the signed-in account.
  ///
  /// [password] re-authenticates the account on the server; a wrong password
  /// comes back as 403 (authorization), NOT 401, so no other part of the app
  /// treats this as an expired session mid-delete. On success the local session
  /// (tokens + cached user) is cleared so the app can never be restored into a
  /// deleted account.
  Future<void> deleteAccount(String password) async {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException(
        type: ApiErrorType.auth,
        message: ErrorMessages.sessionExpired,
      );
    }
    await authService.deleteAccount(password: password, accessToken: token);
    await _clearSession();
  }

  Future<void> _persistSession(AuthResult result) async {
    _user = result.user;
    _accessToken = result.accessToken;
    _refreshToken = result.refreshToken;
    await tokenStorage.saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    await sessionStorage.saveSession(result.user);
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> _setUnauthenticated() async {
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    _status = AuthStatus.unauthenticated;
    await sessionStorage.clear();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    _user = null;
    _accessToken = null;
    _refreshToken = null;
    _status = AuthStatus.unauthenticated;
    await tokenStorage.clear();
    await sessionStorage.clear();
    notifyListeners();
  }
}
