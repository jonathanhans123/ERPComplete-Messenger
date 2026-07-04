import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../config/api_config.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';

class AuthRepository extends ChangeNotifier {
  AuthRepository({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'access_token';
  static const _userNameKey = 'user_name';
  static const _userEmailKey = 'user_email';

  final FlutterSecureStorage _storage;

  String? _token;
  String? _userName;
  String? _userEmail;
  String _apiBaseUrl = ApiConfig.defaultBaseUrl;
  bool _bootstrapped = false;

  String get apiBaseUrl => _apiBaseUrl;
  String? get token => _token;
  String? get userName => _userName;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get isReady => _bootstrapped;

  Future<void> bootstrap() async {
    _apiBaseUrl = await _storage.read(key: ApiConfig.apiBaseUrlKey) ?? ApiConfig.defaultBaseUrl;
    _token = await _storage.read(key: _tokenKey);
    _userName = await _storage.read(key: _userNameKey);
    _userEmail = await _storage.read(key: _userEmailKey);
    _bootstrapped = true;
    notifyListeners();
  }

  Future<void> saveApiBaseUrl(String url) async {
    _apiBaseUrl = url.trim().isEmpty ? ApiConfig.defaultBaseUrl : url.trim();
    await _storage.write(key: ApiConfig.apiBaseUrlKey, value: _apiBaseUrl);
    notifyListeners();
  }

  ApiClient client() => apiClientForBaseUrl(_apiBaseUrl, token: _token);

  Future<void> login({required String email, required String password}) async {
    final client = apiClientForBaseUrl(_apiBaseUrl);
    final json = await client.postJson('auth/login', body: LoginRequest(email: email, password: password).toJson());
    final response = LoginResponse.fromJson(json);
    if (response.accessToken == null || response.accessToken!.isEmpty) {
      throw ApiException('No access token in login response');
    }
    _token = response.accessToken;
    _userName = response.user?.name;
    _userEmail = response.user?.email;
    await _storage.write(key: _tokenKey, value: _token);
    await _storage.write(key: _userNameKey, value: _userName);
    await _storage.write(key: _userEmailKey, value: _userEmail);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _userName = null;
    _userEmail = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userNameKey);
    await _storage.delete(key: _userEmailKey);
    notifyListeners();
  }
}
