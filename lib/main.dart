import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app/app_shell.dart';
import 'core/auth/auth_repository.dart';
import 'core/calls/call_session_controller.dart';
import 'core/calls/incoming_call_controller.dart';
import 'core/notifications/incoming_call_action_handler.dart';
import 'core/notifications/messenger_notification_service.dart';
import 'core/preferences/messenger_preferences.dart';
import 'core/theme/theme_controller.dart';
import 'theme/messenger_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await MessengerNotificationService.instance.init().timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    await MessengerNotificationService.instance.clearAllCallNotifications();
  } catch (_) {
    // Notifications are optional — never block app launch.
  }
  final themeController = await createThemeController();
  final messengerPreferences = await createMessengerPreferences();
  final navigatorKey = GlobalKey<NavigatorState>();
  IncomingCallActionHandler.navigatorKey = navigatorKey;
  runApp(ErpMessengerApp(
    themeController: themeController,
    messengerPreferences: messengerPreferences,
    navigatorKey: navigatorKey,
  ));
}

class ErpMessengerApp extends StatelessWidget {
  const ErpMessengerApp({
    super.key,
    required this.themeController,
    required this.messengerPreferences,
    required this.navigatorKey,
  });

  final ThemeController themeController;
  final MessengerPreferences messengerPreferences;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthRepository()..bootstrap()),
        ChangeNotifierProvider(create: (_) => CallSessionController()),
        ChangeNotifierProvider(create: (_) => IncomingCallController()),
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: messengerPreferences),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themeCtrl, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'ERPComplete Messenger',
            theme: buildMessengerTheme(brightness: Brightness.light),
            darkTheme: buildMessengerTheme(brightness: Brightness.dark),
            themeMode: themeCtrl.mode,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
