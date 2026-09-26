import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:erpcomplete_messenger/core/auth/auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('signed-out bootstrap is ready without reading the profile fields', () async {
    // Stale profile values with no token must not be loaded.
    FlutterSecureStorage.setMockInitialValues({'user_name': 'Stale', 'user_id': '9'});
    final auth = AuthRepository();

    final watch = Stopwatch()..start();
    await auth.bootstrap();
    watch.stop();

    expect(auth.isReady, isTrue);
    expect(auth.isAuthenticated, isFalse);
    expect(auth.userName, isNull);
    expect(auth.userId, isNull);
    // Only the token read backs off (200 ms + 400 ms); the other five keys are skipped.
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('signed-in bootstrap loads the stored profile', () async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'token-123',
      'user_id': '42',
      'user_name': 'Budi',
      'user_email': 'budi@example.com',
      'business_unit_id': '182',
      'team_id': '7',
    });
    final auth = AuthRepository();

    await auth.loadStoredCredentialsForTest();

    expect(auth.isAuthenticated, isTrue);
    expect(auth.userId, 42);
    expect(auth.userName, 'Budi');
    expect(auth.userEmail, 'budi@example.com');
    expect(auth.businessUnitId, 182);
    expect(auth.teamId, 7);
  });
}
