import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required this.baseUrl, this.token});

  final String baseUrl;
  String? token;

  Uri _uri(String path) {
    final normalized = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$normalized/$p');
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> postJson(String path, {Map<String, dynamic>? body}) async {
    final response = await http.post(
      _uri(path),
      headers: _headers,
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final response = await http.get(_uri(path), headers: _headers);
    return _decodeMap(response);
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    if (response.statusCode == 401) {
      throw ApiException('Session expired. Sign in again.', statusCode: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.body.isNotEmpty ? response.body : 'Server error (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }
}

ApiClient apiClientForBaseUrl(String baseUrl, {String? token}) {
  final url = baseUrl.trim().isEmpty ? ApiConfig.defaultBaseUrl : baseUrl.trim();
  return ApiClient(baseUrl: url, token: token);
}
