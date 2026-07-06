import 'package:flutter/material.dart';

import '../../features/calls/call_screen.dart';
import '../notifications/incoming_call_action_handler.dart';

/// Single entry for opening the in-call UI — prevents duplicate routes / freezes.
class CallScreenNavigator {
  CallScreenNavigator._();

  static const routeName = '/messenger-call';

  static bool _routeOpen = false;

  static bool get isOpen => _routeOpen;

  static Future<void> open([BuildContext? context]) async {
    if (_routeOpen) return;

    final nav = IncomingCallActionHandler.navigatorKey?.currentState;
    if (nav != null && nav.mounted) {
      _routeOpen = true;
      try {
        await nav.push<void>(
          MaterialPageRoute(
            settings: const RouteSettings(name: routeName),
            builder: (_) => const CallScreen(),
          ),
        );
      } finally {
        _routeOpen = false;
      }
      return;
    }

    if (context != null && context.mounted) {
      _routeOpen = true;
      try {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            settings: const RouteSettings(name: routeName),
            builder: (_) => const CallScreen(),
          ),
        );
      } finally {
        _routeOpen = false;
      }
    }
  }

  static void popIfOpen() {
    if (!_routeOpen) return;
    final nav = IncomingCallActionHandler.navigatorKey?.currentState;
    if (nav != null && nav.mounted && nav.canPop()) {
      nav.pop();
    }
  }
}
