import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../config/api_config.dart';
import '../api/api_client.dart';
import '../models/api_models.dart';

class AuthRepository extends ChangeNotifier {
  AuthRepository({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'access_token';
  static const _userIdKey = 'user_id';
  static const _userNameKey = 'user_name';
  static const _userEmailKey = 'user_email';
  static const _buKey = 'business_unit_id';
  static const _teamKey = 'team_id';

  final FlutterSecureStorage _storage;

  String? _token;
  int? _userId;
  String? _userName;
  String? _userEmail;
  int? _businessUnitId;
  int? _teamId;
  bool _bootstrapped = false;
  bool _refreshing = false;

  String get apiBaseUrl => ApiConfig.defaultBaseUrl;
  String? get token => _token;
  int? get userId => _userId;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  int? get businessUnitId => _businessUnitId;
  int? get teamId => _teamId;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  bool get isReady => _bootstrapped;

  Future<void> bootstrap() async {
    _token = await _storage.read(key: _tokenKey);
    _userName = await _storage.read(key: _userNameKey);
    _userEmail = await _storage.read(key: _userEmailKey);
    _userId = int.tryParse(await _storage.read(key: _userIdKey) ?? '');
    _businessUnitId = int.tryParse(await _storage.read(key: _buKey) ?? '');
    _teamId = int.tryParse(await _storage.read(key: _teamKey) ?? '');

    if (isAuthenticated) {
      await refreshSession(logoutOnFailure: true);
    }

    _bootstrapped = true;
    notifyListeners();
  }

  ApiClient client() => apiClientForBaseUrl(
        apiBaseUrl,
        token: _token,
        businessUnitId: _businessUnitId,
        teamId: _teamId,
      );

  Future<void> login({
    required String email,
    required String password,
    String? twoFactorCode,
  }) async {
    final client = apiClientForBaseUrl(apiBaseUrl);
    final json = await client.postJson(
      'auth/login',
      body: LoginRequest(email: email, password: password, twoFactorCode: twoFactorCode).toJson(),
    );
    final response = LoginResponse.fromJson(json);
    if (response.accessToken == null || response.accessToken!.isEmpty) {
      throw ApiException('No access token in login response');
    }
    await _applyToken(response.accessToken!, user: response.user, email: email);
  }

  Future<bool> refreshSession({bool logoutOnFailure = false}) async {
    if (!isAuthenticated || _refreshing) return isAuthenticated;
    _refreshing = true;
    try {
      final client = apiClientForBaseUrl(apiBaseUrl, token: _token, businessUnitId: _businessUnitId, teamId: _teamId);
      final json = await client.postJson('auth/refresh');
      final newToken = json['access_token'] as String?;
      if (newToken == null || newToken.isEmpty) {
        throw ApiException('Token refresh failed', statusCode: 401);
      }
      await _persistToken(newToken);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (logoutOnFailure && e.statusCode == 401) {
        await logout();
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _applyToken(String accessToken, {UserSummary? user, String? email}) async {
    _token = accessToken;
    _userId = user?.id;
    _userName = user?.name;
    _userEmail = user?.email ?? email;
    _businessUnitId = user?.currentBusinessUnitId;
    _teamId = user?.currentTeamId;
    await _persistToken(accessToken);
    if (_userId != null) await _storage.write(key: _userIdKey, value: _userId.toString());
    if (_userName != null) await _storage.write(key: _userNameKey, value: _userName);
    if (_userEmail != null) await _storage.write(key: _userEmailKey, value: _userEmail);
    if (_businessUnitId != null) await _storage.write(key: _buKey, value: _businessUnitId.toString());
    if (_teamId != null) await _storage.write(key: _teamKey, value: _teamId.toString());
    notifyListeners();
  }

  Future<void> _persistToken(String accessToken) async {
    _token = accessToken;
    await _storage.write(key: _tokenKey, value: accessToken);
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    _userName = null;
    _userEmail = null;
    _businessUnitId = null;
    _teamId = null;
    for (final k in [_tokenKey, _userIdKey, _userNameKey, _userEmailKey, _buKey, _teamKey]) {
      await _storage.delete(key: k);
    }
    notifyListeners();
  }
}
