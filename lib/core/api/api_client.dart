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

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$normalized/$p').replace(queryParameters: query);
  }

  Map<String, String> get _jsonHeaders => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> getJson(String path, {Map<String, String>? query}) async {
    final response = await http.get(_uri(path, query), headers: _jsonHeaders);
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> postJson(String path, {Map<String, dynamic>? body}) async {
    final response = await http.post(_uri(path), headers: _jsonHeaders, body: jsonEncode(body ?? {}));
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> postForm(String path, Map<String, String> fields) async {
    final response = await http.post(
      _uri(path),
      headers: {
        'Accept': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: fields,
    );
    return _decodeMap(response);
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    if (response.statusCode == 401) {
      throw ApiException('Session expired. Sign in again.', statusCode: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String msg = response.body;
      try {
        final j = jsonDecode(response.body);
        if (j is Map && j['message'] != null) msg = j['message'].toString();
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      throw ApiException(msg.isNotEmpty ? msg : 'Server error (${response.statusCode})', statusCode: response.statusCode);
    }
    if (response.body.isEmpty) return {};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }
}

ApiClient apiClientForBaseUrl(String baseUrl, {String? token}) {
  final url = baseUrl.trim().isEmpty ? ApiConfig.defaultBaseUrl : baseUrl.trim();
  return ApiClient(baseUrl: url, token: token);
}
