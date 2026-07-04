import 'package:flutter/material.dart';

/// Colors aligned with public/css/messaging-app.css
abstract final class MessengerColors {
  static const primary = Color(0xFF007BFF);
  static const primaryHover = Color(0xFF0056B3);
  static const sentBubble = Color(0xFF004185);
  static const sentText = Color(0xFFF5F8FC);
  static const receivedBubble = Color(0xFF353535);
  static const receivedText = Color(0xFFECECEC);
  static const bgPrimary = Color(0xFFFFFFFF);
  static const bgSecondary = Color(0xFFF8F9FA);
  static const bgTertiary = Color(0xFFE9ECEF);
  static const textPrimary = Color(0xFF212529);
  static const textSecondary = Color(0xFF6C757D);
  static const border = Color(0xFFDEE2E6);
  static const success = Color(0xFF28A745);
  static const danger = Color(0xFFDC3545);
}

ThemeData buildMessengerTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: MessengerColors.primary,
    brightness: brightness,
    primary: isDark ? const Color(0xFF4DA3FF) : MessengerColors.primary,
    surface: isDark ? const Color(0xFF1A1A1A) : MessengerColors.bgPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF1A1A1A) : MessengerColors.bgSecondary,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: isDark ? const Color(0xFF2D2D2D) : MessengerColors.bgPrimary,
      foregroundColor: isDark ? Colors.white : MessengerColors.textPrimary,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : MessengerColors.textPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF3A3A3A) : MessengerColors.bgPrimary,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: scheme.outline)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: isDark ? const Color(0xFF404040) : MessengerColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: MessengerColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isDark ? const Color(0xFF3A3A3A) : MessengerColors.bgTertiary,
      selectedColor: MessengerColors.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white : MessengerColors.textPrimary),
      side: BorderSide(color: isDark ? const Color(0xFF404040) : MessengerColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
