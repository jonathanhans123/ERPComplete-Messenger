import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:erpcomplete_messenger/core/preferences/messenger_preferences.dart';
import 'package:erpcomplete_messenger/core/theme/theme_controller.dart';
import 'package:erpcomplete_messenger/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Secure storage and path_provider are platform channels with no host in widget tests.
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '.',
    );
  });

  testWidgets('App boots to the sign-in screen when no session is stored', (tester) async {
    late final ThemeController themeController;
    late final MessengerPreferences messengerPreferences;
    // These load outside the widget tree, so let them finish on the real clock.
    await tester.runAsync(() async {
      themeController = await createThemeController();
      messengerPreferences = await createMessengerPreferences();
      while (!themeController.isLoaded || !messengerPreferences.isLoaded) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    await tester.pumpWidget(ErpMessengerApp(
      navigatorKey: GlobalKey<NavigatorState>(),
      themeController: themeController,
      messengerPreferences: messengerPreferences,
    ));

    // AuthRepository.bootstrap runs inside the tree on the fake clock (storage read retries
    // back off with timers), so advance time until the spinner gives way to the login form.
    for (var i = 0; i < 20 && find.text('Sign in').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('ERPMessage'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);

    // Tear the tree down and let any remaining timers fire so none outlive the test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });
}
