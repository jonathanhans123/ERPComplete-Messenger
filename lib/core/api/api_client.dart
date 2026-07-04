import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../config/api_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// VPS API client — hostname URL for TLS.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    this.token,
    this.businessUnitId,
    this.teamId,
  });

  final String baseUrl;
  String? token;
  final int? businessUnitId;
  final int? teamId;

  static final HttpClient _client = (() {
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) =>
          host == ApiConfig.serverIp || host == ApiConfig.nginxHost;
    return client;
  })();

  Uri _uri(String path, {Map<String, String>? query}) {
    final normalized = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final p = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$normalized/$p').replace(queryParameters: query);
  }

  void _applyHeaders(HttpClientRequest request) {
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null && token!.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (businessUnitId != null) {
      request.headers.set('X-Business-Unit-Id', businessUnitId.toString());
    }
    if (teamId != null) {
      request.headers.set('X-Team-Id', teamId.toString());
    }
  }

  Future<Map<String, dynamic>> getJson(String path, {Map<String, String>? query}) {
    return _send(method: 'GET', path: path, query: query);
  }

  Future<Map<String, dynamic>> postJson(String path, {Map<String, dynamic>? body}) {
    return _send(method: 'POST', path: path, jsonBody: body ?? {});
  }

  Future<Map<String, dynamic>> putJson(String path, {Map<String, dynamic>? body}) {
    return _send(method: 'PUT', path: path, jsonBody: body ?? {});
  }

  Future<Map<String, dynamic>> deleteJson(String path) {
    return _send(method: 'DELETE', path: path);
  }

  Future<Map<String, dynamic>> postForm(String path, Map<String, String> fields) {
    return _send(method: 'POST', path: path, formBody: fields);
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<({String field, File file, String filename})>? files,
  }) async {
    final boundary = '----erpboundary${DateTime.now().millisecondsSinceEpoch}';
    final uri = _uri(path);
    final request = await _client.postUrl(uri);
    _applyHeaders(request);
    request.headers.contentType = ContentType('multipart', 'form-data', charset: 'utf-8', parameters: {'boundary': boundary});

    final body = BytesBuilder();
    void writeField(String name, String value) {
      body.add(utf8.encode('--$boundary\r\n'));
      body.add(utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
      body.add(utf8.encode('$value\r\n'));
    }

    fields.forEach(writeField);
    for (final f in files ?? []) {
      body.add(utf8.encode('--$boundary\r\n'));
      body.add(utf8.encode('Content-Disposition: form-data; name="${f.field}"; filename="${f.filename}"\r\n'));
      body.add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'));
      body.add(f.file.readAsBytesSync());
      body.add(utf8.encode('\r\n'));
    }
    body.add(utf8.encode('--$boundary--\r\n'));
    request.add(body.toBytes());

    try {
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return _decodeMap(response.statusCode, text, path: path);
    } catch (e) {
      throw ApiException(_friendlyError(e));
    }
  }

  Future<Map<String, dynamic>> _send({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, dynamic>? jsonBody,
    Map<String, String>? formBody,
  }) async {
    try {
      final uri = _uri(path, query: query);
      final HttpClientRequest request;
      switch (method) {
        case 'GET':
          request = await _client.getUrl(uri);
        case 'PUT':
          request = await _client.putUrl(uri);
        case 'DELETE':
          request = await _client.deleteUrl(uri);
        default:
          request = await _client.postUrl(uri);
      }

      _applyHeaders(request);

      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(jsonEncode(jsonBody)));
      } else if (formBody != null) {
        request.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
        request.add(utf8.encode(_encodeForm(formBody)));
      }

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return _decodeMap(response.statusCode, body, path: path);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(_friendlyError(e));
    }
  }

  static String _encodeForm(Map<String, String> fields) {
    return fields.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
  }

  Map<String, dynamic> _decodeMap(int statusCode, String body, {required String path}) {
    if (statusCode == 401) {
      final isLogin = path.contains('auth/login');
      throw ApiException(
        isLogin ? 'Invalid email or password.' : 'Session expired. Sign in again.',
        statusCode: 401,
      );
    }
    if (statusCode == 403) {
      throw ApiException('This action is unauthorized.', statusCode: 403);
    }
    if (statusCode < 200 || statusCode >= 300) {
      String msg = body;
      try {
        final j = jsonDecode(body);
        if (j is Map && j['message'] != null) msg = j['message'].toString();
        if (j is Map && j['error'] != null) msg = j['error'].toString();
      } catch (_) {}
      if (msg.contains('<html') || msg.length > 280) {
        msg = 'Server error ($statusCode). Please try again.';
      }
      throw ApiException(msg.isNotEmpty ? msg : 'Server error ($statusCode)', statusCode: statusCode);
    }
    if (body.isEmpty) return {};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('HandshakeException') || msg.contains('CERTIFICATE')) {
      return 'Secure connection failed. Try again on Wi‑Fi or mobile data.';
    }
    if (msg.contains('Connection refused') ||
        msg.contains('Connection timed out') ||
        msg.contains('SocketException') ||
        msg.contains('Failed host lookup')) {
      return 'Server unreachable. Check your internet connection.';
    }
    if (e is ApiException) return e.message;
    return 'Network error. Please try again.';
  }
}

ApiClient apiClientForBaseUrl(
  String baseUrl, {
  String? token,
  int? businessUnitId,
  int? teamId,
}) {
  return ApiClient(
    baseUrl: baseUrl.trim().isEmpty ? ApiConfig.defaultBaseUrl : baseUrl.trim(),
    token: token,
    businessUnitId: businessUnitId,
    teamId: teamId,
  );
}

String formatApiError(Object e) {
  final s = e.toString();
  return s.replaceFirst('ApiException: ', '');
}
