import 'package:flutter_test/flutter_test.dart';

import 'package:erpcomplete_messenger/core/preferences/messenger_preferences.dart';
import 'package:erpcomplete_messenger/core/theme/theme_controller.dart';
import 'package:erpcomplete_messenger/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App boots login screen', (tester) async {
    final themeController = await createThemeController();
    final messengerPreferences = await createMessengerPreferences();
    while (!themeController.isLoaded || !messengerPreferences.isLoaded) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await tester.pumpWidget(ErpMessengerApp(themeController: themeController, messengerPreferences: messengerPreferences));
    await tester.pump();
    expect(find.text('Sign in'), findsOneWidget);
  });
}
