import 'dart:convert';

/// Envelope returned by the ParkShare backend: { success, message, data }.
class ApiResponse {
  final bool success;
  final String message;
  final dynamic data;

  const ApiResponse({required this.success, required this.message, this.data});

  factory ApiResponse.fromJson(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid API response envelope.');
    }
    return ApiResponse(
      success: decoded['success'] == true,
      message: decoded['message']?.toString() ?? '',
      data: decoded['data'],
    );
  }
}
