/// Typed error categories used across the app so UI can respond
/// correctly to validation / auth / network / server failures.
enum ApiErrorType {
  validation,
  auth,
  authorization,
  network,
  notFound,
  conflict,
  server,
  unknown,
}

class ApiException implements Exception {
  final ApiErrorType type;
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? data;

  const ApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.data,
  });

  factory ApiException.fromStatus(
    int status,
    String message, {
    Map<String, dynamic>? data,
  }) {
    return ApiException(
      type: typeFromStatus(status),
      message: message,
      statusCode: status,
      data: data,
    );
  }

  bool get isAuthError => type == ApiErrorType.auth;

  @override
  String toString() => 'ApiException($type, $statusCode, $message)';
}

ApiErrorType typeFromStatus(int status) {
  if (status >= 400 && status < 500) {
    switch (status) {
      case 400:
        return ApiErrorType.validation;
      case 401:
        return ApiErrorType.auth;
      case 403:
        return ApiErrorType.authorization;
      case 404:
        return ApiErrorType.notFound;
      case 409:
        return ApiErrorType.conflict;
      default:
        return ApiErrorType.validation;
    }
  }
  if (status >= 500) return ApiErrorType.server;
  return ApiErrorType.unknown;
}
