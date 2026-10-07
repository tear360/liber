import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The light palette used by WhatsApp today. Every value here is transcribed
/// from the shipping app so Liber reads as the same product at a glance.
abstract final class WaPalette {
  /// Top bar, selected tab label and icons on light surfaces.
  static const Color primary = Color(0xFF008069);

  /// Slightly deeper green for pressed states and the splash.
  static const Color primaryDark = Color(0xFF005C4B);

  /// FAB and "archived"/secondary green accents.
  static const Color accent = Color(0xFF00A884);

  /// Unread counter pill.
  static const Color unreadBadge = Color(0xFF25D366);

  /// The compose FAB sits on this green.
  static const Color fab = Color(0xFF21C063);

  /// Chat screen wallpaper, the beige behind bubbles.
  static const Color wallpaper = Color(0xFFEFE7DE);

  /// Outgoing (own) message bubble.
  static const Color outgoingBubble = Color(0xFFD9FDD3);

  /// Incoming message bubble.
  static const Color incomingBubble = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF111B21);
  static const Color textSecondary = Color(0xFF667781);
  static const Color iconMuted = Color(0xFF54656F);
  static const Color divider = Color(0xFFE9EDEF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color composerField = Color(0xFFF0F2F5);
  static const Color incomingTimestamp = Color(0xFF667781);

  /// Bottom navigation: selected icon/label, unselected icon/label.
  static const Color navSelected = Color(0xFF103529);
  static const Color navUnselected = Color(0xFF54656F);

  /// Colours a call can take to stand in for a missing avatar.
  static const List<Color> avatarPalette = <Color>[
    Color(0xFFE542A0),
    Color(0xFF6BC24B),
    Color(0xFFF2A93B),
    Color(0xFF3EA6F2),
    Color(0xFF9B59B6),
    Color(0xFFE0533D),
    Color(0xFF25A18E),
    Color(0xFF7E57C2),
  ];
}

/// Builds the Material theme that makes the app look like WhatsApp.
ThemeData buildLiberTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: WaPalette.primary,
      primary: WaPalette.primary,
      secondary: WaPalette.accent,
      surface: WaPalette.surface,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: WaPalette.surface,
  );

  return base.copyWith(
    // WhatsApp's 2025 layout: light header, dark text, green accents.
    appBarTheme: const AppBarTheme(
      backgroundColor: WaPalette.surface,
      foregroundColor: WaPalette.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: WaPalette.textPrimary,
        letterSpacing: -0.3,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: WaPalette.primary,
      unselectedLabelColor: WaPalette.textSecondary,
      labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      indicatorColor: WaPalette.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: WaPalette.fab,
      foregroundColor: Colors.white,
      elevation: 3,
    ),
    dividerTheme: const DividerThemeData(
      color: WaPalette.divider,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      iconColor: WaPalette.iconMuted,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WaPalette.composerField,
      hintStyle: const TextStyle(color: WaPalette.textSecondary, fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WaPalette.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF111B21),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : WaPalette.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? WaPalette.accent
            : const Color(0xFFD9DBDD),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: WaPalette.composerField,
      selectedColor: const Color(0xFFD3F4E5),
      showCheckmark: false,
      labelStyle: const TextStyle(fontSize: 13.5),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: WaPalette.surface,
      selectedItemColor: WaPalette.navSelected,
      unselectedItemColor: WaPalette.navUnselected,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
