import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/user.dart';
import '../models/auth_models.dart';

/// AuthService talks to the backend auth APIs and returns typed results.
class AuthService {
  final ApiClient _apiClient;

  AuthService(this._apiClient);

  /// Creates the account.
  ///
  /// [upiId] is optional for every role. It is retained only as legacy
  /// metadata: production payments use Razorpay and owner payouts use a
  /// bank account, so a missing UPI id never blocks registration or payout.
  Future<AuthResult> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
    String? upiId,
  }) async {
    final upi = (upiId ?? '').trim();
    final data = await _apiClient.post(
      ApiConstants.register,
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role,
        // Only send a non-empty UPI id: an empty string would trip the
        // backend's format check instead of meaning "not provided".
        if (upi.isNotEmpty) 'upiId': upi,
      },
    );
    return AuthResult.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  Future<AuthResult> login({
    required String email,
    required String password,
    String? role,
  }) async {
    final data = await _apiClient.post(
      ApiConstants.login,
      body: {'email': email, 'password': password, 'role': ?role},
    );
    return AuthResult.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  Future<User> me(String accessToken) async {
    final data = await _apiClient.get(ApiConstants.me, token: accessToken);
    return User.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  Future<AuthResult> refresh(String refreshToken) async {
    final data = await _apiClient.post(
      ApiConstants.refresh,
      body: {'refreshToken': refreshToken},
    );
    return AuthResult.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  Future<void> logout(String refreshToken) async {
    await _apiClient.post(
      ApiConstants.logout,
      body: {'refreshToken': refreshToken},
    );
  }

  Future<ForgotPasswordResult> forgotPassword(String email) async {
    final data = await _apiClient.post(
      ApiConstants.forgotPassword,
      body: {'email': email},
    );
    return ForgotPasswordResult.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  Future<void> verifyResetOtp(String email, String otp) async {
    await _apiClient.post(
      ApiConstants.verifyResetOtp,
      body: {'email': email, 'otp': otp},
    );
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    await _apiClient.post(
      ApiConstants.resetPassword,
      body: {'email': email, 'otp': otp, 'newPassword': newPassword},
    );
  }

  /// Deletes the signed-in account.
  ///
  /// The backend re-authenticates with [password] (403 when it is wrong) and
  /// derives the account identity from [accessToken] — the client never sends a
  /// userId.
  Future<void> deleteAccount({
    required String password,
    required String accessToken,
  }) async {
    await _apiClient.delete(
      ApiConstants.deleteAccount,
      body: {'password': password},
      token: accessToken,
    );
  }
}
