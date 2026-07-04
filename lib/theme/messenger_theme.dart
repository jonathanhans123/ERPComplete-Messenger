import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WhatsApp / LINE inspired palette with ERP blue accent.
abstract final class MessengerPalette {
  static const accent = Color(0xFF007BFF);
  static const accentDark = Color(0xFF4DA3FF);
  static const whatsAppGreen = Color(0xFF00A884);
  static const whatsAppGreenDark = Color(0xFF005C4B);
  static const danger = Color(0xFFEA4335);

  // Light
  static const lightBg = Color(0xFFEFF2F5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightHeader = Color(0xFFF0F2F5);
  static const lightSentBubble = Color(0xFFD9FDD3);
  static const lightReceivedBubble = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF111B21);
  static const lightSubtext = Color(0xFF667781);

  // Dark
  static const darkBg = Color(0xFF0B141A);
  static const darkSurface = Color(0xFF1F2C34);
  static const darkHeader = Color(0xFF1F2C34);
  static const darkSentBubble = Color(0xFF005C4B);
  static const darkReceivedBubble = Color(0xFF202C33);
  static const darkText = Color(0xFFE9EDEF);
  static const darkSubtext = Color(0xFF8696A0);
}

class MessengerThemeExtension extends ThemeExtension<MessengerThemeExtension> {
  const MessengerThemeExtension({
    required this.chatBackground,
    required this.sentBubble,
    required this.receivedBubble,
    required this.sentText,
    required this.receivedText,
    required this.headerBackground,
    required this.subtext,
    required this.unreadBadge,
    required this.composerBackground,
  });

  final Color chatBackground;
  final Color sentBubble;
  final Color receivedBubble;
  final Color sentText;
  final Color receivedText;
  final Color headerBackground;
  final Color subtext;
  final Color unreadBadge;
  final Color composerBackground;

  static const light = MessengerThemeExtension(
    chatBackground: MessengerPalette.lightBg,
    sentBubble: MessengerPalette.lightSentBubble,
    receivedBubble: MessengerPalette.lightReceivedBubble,
    sentText: MessengerPalette.lightText,
    receivedText: MessengerPalette.lightText,
    headerBackground: MessengerPalette.lightHeader,
    subtext: MessengerPalette.lightSubtext,
    unreadBadge: MessengerPalette.whatsAppGreen,
    composerBackground: MessengerPalette.lightHeader,
  );

  static const dark = MessengerThemeExtension(
    chatBackground: MessengerPalette.darkBg,
    sentBubble: MessengerPalette.darkSentBubble,
    receivedBubble: MessengerPalette.darkReceivedBubble,
    sentText: MessengerPalette.darkText,
    receivedText: MessengerPalette.darkText,
    headerBackground: MessengerPalette.darkHeader,
    subtext: MessengerPalette.darkSubtext,
    unreadBadge: MessengerPalette.whatsAppGreen,
    composerBackground: MessengerPalette.darkSurface,
  );

  @override
  MessengerThemeExtension copyWith({
    Color? chatBackground,
    Color? sentBubble,
    Color? receivedBubble,
    Color? sentText,
    Color? receivedText,
    Color? headerBackground,
    Color? subtext,
    Color? unreadBadge,
    Color? composerBackground,
  }) {
    return MessengerThemeExtension(
      chatBackground: chatBackground ?? this.chatBackground,
      sentBubble: sentBubble ?? this.sentBubble,
      receivedBubble: receivedBubble ?? this.receivedBubble,
      sentText: sentText ?? this.sentText,
      receivedText: receivedText ?? this.receivedText,
      headerBackground: headerBackground ?? this.headerBackground,
      subtext: subtext ?? this.subtext,
      unreadBadge: unreadBadge ?? this.unreadBadge,
      composerBackground: composerBackground ?? this.composerBackground,
    );
  }

  @override
  MessengerThemeExtension lerp(ThemeExtension<MessengerThemeExtension>? other, double t) {
    if (other is! MessengerThemeExtension) return this;
    return this;
  }
}

ThemeData buildMessengerTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;
  final ext = isDark ? MessengerThemeExtension.dark : MessengerThemeExtension.light;
  final primary = isDark ? MessengerPalette.accentDark : MessengerPalette.accent;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: Colors.white,
    secondary: MessengerPalette.whatsAppGreen,
    onSecondary: Colors.white,
    error: MessengerPalette.danger,
    onError: Colors.white,
    surface: isDark ? MessengerPalette.darkSurface : MessengerPalette.lightSurface,
    onSurface: isDark ? MessengerPalette.darkText : MessengerPalette.lightText,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: ext.chatBackground,
    extensions: [ext],
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      backgroundColor: ext.headerBackground,
      foregroundColor: isDark ? MessengerPalette.darkText : MessengerPalette.lightText,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: isDark ? MessengerPalette.darkText : MessengerPalette.lightText,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: MessengerPalette.whatsAppGreen,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF2A3942) : Colors.white,
      hintStyle: TextStyle(color: ext.subtext),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: primary.withValues(alpha: 0.5)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      showCheckmark: false,
      backgroundColor: isDark ? const Color(0xFF2A3942) : const Color(0xFFE9EDEF),
      selectedColor: isDark ? const Color(0xFF103529) : const Color(0xFFD1F4CC),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: isDark ? MessengerPalette.darkText : MessengerPalette.lightText,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      iconColor: ext.subtext,
    ),
    dividerTheme: DividerThemeData(color: isDark ? const Color(0xFF2A3942) : const Color(0xFFE9EDEF), space: 1, thickness: 0.5),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? MessengerPalette.darkSurface : MessengerPalette.lightSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
  );
}

MessengerThemeExtension messengerExt(BuildContext context) {
  return Theme.of(context).extension<MessengerThemeExtension>() ?? MessengerThemeExtension.light;
}
