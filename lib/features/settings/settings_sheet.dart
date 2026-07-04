import 'package:flutter/material.dart';

import 'settings_screen.dart';

Future<void> openSettings(BuildContext context) {
  return Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
}
