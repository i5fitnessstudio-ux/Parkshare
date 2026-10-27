import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../constants/api_constants.dart';
import 'api_exception.dart';
import 'api_response.dart';

/// Thin HTTP client for the ParkShare REST API.
///
/// All methods return the `data` payload of the { success, message, data }
/// envelope and throw [ApiException] on errors, categorised via HTTP status.
class ApiClient {
  final http.Client _client;
  final String baseUrl;

  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? ApiConstants.baseUrl;

  Future<dynamic> get(String path, {String? token}) {
    return _send('GET', path, token: token);
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    String? token,
    bool formUrlEncoded = false,
  }) {
    return _send('POST', path, body: body, token: token);
  }

  Future<dynamic> put(String path, {Object? body, String? token}) {
    return _send('PUT', path, body: body, token: token);
  }

  Future<dynamic> patch(String path, {Object? body, String? token}) {
    return _send('PATCH', path, body: body, token: token);
  }

  Future<dynamic> delete(String path, {Object? body, String? token}) {
    return _send('DELETE', path, body: body, token: token);
  }

  /// Uploads a photo (multipart) and returns the `{ url, relativePath }`
  /// payload. JPG/PNG/WEBP only; the server limits the size.
  ///
  /// Uses a dedicated [http.Client] (not the shared pooled one) and retries
  /// once on network errors: a half-closed keep-alive connection against a
  /// long-lived dev server can otherwise make the multipart send throw
  /// mid-session even though plain JSON calls keep working.
  Future<Map<String, dynamic>> uploadPhoto({
    required List<int> bytes,
    required String filename,
    required String contentType,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl${ApiConstants.uploadPhoto}');

    for (var attempt = 0; attempt < 2; attempt++) {
      final client = http.Client();
      try {
        final request = http.MultipartRequest('POST', uri);
        request.headers['Accept'] = 'application/json';
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: filename,
            contentType: MediaType.parse(contentType),
          ),
        );

        final streamed = await client
            .send(request)
            .timeout(ApiConstants.connectTimeout);
        final response = await http.Response.fromStream(streamed)
            .timeout(ApiConstants.receiveTimeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            final envelope = ApiResponse.fromJson(response.body);
            if (envelope.data is Map<String, dynamic>) {
              return envelope.data as Map<String, dynamic>;
            }
          } on FormatException {
            // fall through to error handling
          }
          throw ApiException.fromStatus(
            response.statusCode,
            'Invalid upload response.',
          );
        }

        String message =
            'Upload failed. Please try again. (${response.statusCode})';
        try {
          final envelope = ApiResponse.fromJson(response.body);
          if (envelope.message.isNotEmpty) message = envelope.message;
        } catch (_) {}
        throw ApiException.fromStatus(response.statusCode, message);
      } on TimeoutException {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        throw const ApiException(
          type: ApiErrorType.network,
          message: 'The upload timed out. Please try again.',
        );
      } on SocketException {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        throw const ApiException(
          type: ApiErrorType.network,
          message: 'Unable to reach the server. Check your connection.',
        );
      } on http.ClientException {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        throw const ApiException(
          type: ApiErrorType.network,
          message: 'Unable to reach the server. Check your connection.',
        );
      } on Object {
        throw const ApiException(
          type: ApiErrorType.network,
          message: 'Upload failed. Please try again.',
        );
      } finally {
        client.close();
      }
    }

    // Unreachable — the loop always returns or throws. Kept for analysis.
    throw const ApiException(
      type: ApiErrorType.network,
      message: 'Upload failed. Please try again.',
    );
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final streamed = await _client
          .send(request)
          .timeout(ApiConstants.connectTimeout);
      response = await http.Response.fromStream(streamed)
          .timeout(ApiConstants.receiveTimeout);
    } on TimeoutException {
      throw const ApiException(
        type: ApiErrorType.network,
        message: 'The request timed out. Please try again.',
      );
    } on SocketException {
      throw const ApiException(
        type: ApiErrorType.network,
        message: 'Unable to reach the server. Check your connection.',
      );
    } on http.ClientException {
      throw const ApiException(
        type: ApiErrorType.network,
        message: 'Unable to reach the server. Check your connection.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        type: ApiErrorType.network,
        message: 'Network error. Please try again.',
      );
    }

    final bodyText = response.body;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final envelope = ApiResponse.fromJson(bodyText);
        return envelope.data;
      } on FormatException {
        throw ApiException.fromStatus(
          response.statusCode,
          'Invalid server response.',
        );
      }
    }

    // Error path: parse envelope for a friendly message.
    String message =
        'Something went wrong. Please try again. (${response.statusCode})';
    Map<String, dynamic>? data;
    try {
      final envelope = ApiResponse.fromJson(bodyText);
      if (envelope.message.isNotEmpty) message = envelope.message;
      if (envelope.data is Map<String, dynamic>) {
        data = envelope.data as Map<String, dynamic>;
      }
    } catch (_) {
      // Non-envelope error body; keep default message.
    }
    throw ApiException.fromStatus(response.statusCode, message, data: data);
  }
}
