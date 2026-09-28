import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../config/api_config.dart';
import '../api/api_client.dart';
import '../cache/messenger_local_cache.dart';
import '../models/api_models.dart';

class AuthRepository extends ChangeNotifier {
  AuthRepository({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ) {
    // Any 401 from any API call signs out globally. Without this a dead
    // token (e.g. after a database reset) left the user stuck on stale
    // cached chats with only a "session expired" snackbar.
    ApiClient.onUnauthorized = () {
      unawaited(handleUnauthorized());
    };
  }

  static const _tokenKey = 'access_token';
  static const _userIdKey = 'user_id';
  static const _userNameKey = 'user_name';
  static const _userEmailKey = 'user_email';
  static const _buKey = 'business_unit_id';
  static const _teamKey = 'team_id';
  static const _storageReadTimeout = Duration(seconds: 15);

  final FlutterSecureStorage _storage;

  String? _token;
  int? _userId;
  String? _userName;
  String? _userEmail;
  int? _businessUnitId;
  int? _teamId;
  bool _bootstrapped = false;
  bool _refreshing = false;
  bool _recovering401 = false;

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
    try {
      await _loadStoredCredentials();
      // NOTE: no proactive refresh here. The server revokes the token on
      // every refresh, so rotating on every launch/resume widens the race
      // where in-flight requests still carry the old token, 401, and used to
      // sign the user out. A dead token is caught on first use instead.
    } catch (e, st) {
      debugPrint('[AuthRepository] bootstrap failed: $e\n$st');
    } finally {
      _bootstrapped = true;
      notifyListeners();
    }
  }

  /// Storage loading without the network session refresh that [bootstrap] adds.
  @visibleForTesting
  Future<void> loadStoredCredentialsForTest() => _loadStoredCredentials();

  Future<void> _loadStoredCredentials() async {
    _token = await _readStorage(_tokenKey);
    // The profile fields mean nothing without a token, and each empty read waits out the
    // retry back-off — skipping them keeps signed-out launches from idling on a spinner.
    if (!isAuthenticated) return;
    _userName = await _readStorage(_userNameKey);
    _userEmail = await _readStorage(_userEmailKey);
    _userId = int.tryParse(await _readStorage(_userIdKey) ?? '');
    _businessUnitId = int.tryParse(await _readStorage(_buKey) ?? '');
    _teamId = int.tryParse(await _readStorage(_teamKey) ?? '');
  }

  Future<String?> _readStorage(String key) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final value = await _storage.read(key: key).timeout(
          _storageReadTimeout,
          onTimeout: () => null,
        );
        if (value != null && value.isNotEmpty) return value;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        }
      } catch (_) {
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        }
      }
    }
    return null;
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
    // Drop any previous account's (or pre-reset database's) cached chats
    // before the new session populates the list.
    await MessengerLocalCache.instance.clearAll();
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
    await MessengerLocalCache.instance.clearAll();
    notifyListeners();
  }

  /// Global 401 handler (wired to [ApiClient.onUnauthorized]).
  ///
  /// A 401 is often just a stale-token race: the server revokes the token on
  /// every refresh, so a request that started before a rotation 401s even
  /// though the session is alive. Recover with a single refresh first and
  /// only sign out when refresh fails too. Network errors never reach here —
  /// only real 401s do, since _decodeMap is the sole caller.
  Future<void> handleUnauthorized() async {
    if (!isAuthenticated || _recovering401) return;
    _recovering401 = true;
    try {
      final ok = await refreshSession(logoutOnFailure: false);
      if (!ok || !isAuthenticated) {
        debugPrint('[AuthRepository] session expired — signing out');
        await logout();
      } else {
        debugPrint('[AuthRepository] recovered session after 401');
      }
    } finally {
      _recovering401 = false;
    }
  }
}
