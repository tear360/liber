import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WhatsApp's palette, resolved for the brightness currently in use.
///
/// Every screen reads these getters instead of `const` colours, so switching
/// to dark mode repaints the whole app without touching call sites. The
/// brightness is set by [AppThemeController] just before the tree rebuilds.
abstract final class WaPalette {
  /// Brightness the getters below resolve against. Always set together with
  /// the effective `ThemeMode`, before children build.
  static Brightness brightness = Brightness.light;

  static bool get isDark => brightness == Brightness.dark;

  static Color _v(Color light, Color dark) => isDark ? dark : light;

  /// Top bar, selected tab label and icons on light surfaces.
  static Color get primary => _v(const Color(0xFF008069), const Color(0xFF005C4B));

  /// Slightly deeper green for pressed states and the splash.
  static Color get primaryDark => _v(const Color(0xFF005C4B), const Color(0xFF004034));

  /// FAB and "archived"/secondary green accents.
  static Color get accent => _v(const Color(0xFF00A884), const Color(0xFF00A884));

  /// Unread counter pill.
  static Color get unreadBadge => _v(const Color(0xFF25D366), const Color(0xFF25D366));

  /// The compose FAB sits on this green.
  static Color get fab => _v(const Color(0xFF21C063), const Color(0xFF21C063));

  /// Chat screen wallpaper, the beige behind bubbles.
  static Color get wallpaper => _v(const Color(0xFFEFE7DE), const Color(0xFF0B141A));

  /// Outgoing (own) message bubble.
  static Color get outgoingBubble => _v(const Color(0xFFD9FDD3), const Color(0xFF005C4B));

  /// Incoming message bubble.
  static Color get incomingBubble => _v(const Color(0xFFFFFFFF), const Color(0xFF1B262C));

  static Color get textPrimary => _v(const Color(0xFF111B21), const Color(0xFFE9EDEF));
  static Color get textSecondary => _v(const Color(0xFF667781), const Color(0xFF8696A0));
  static Color get iconMuted => _v(const Color(0xFF54656F), const Color(0xFF8696A0));
  static Color get divider => _v(const Color(0xFFE9EDEF), const Color(0xFF222E35));
  static Color get surface => _v(const Color(0xFFFFFFFF), const Color(0xFF111B21));
  static Color get composerField => _v(const Color(0xFFF0F2F5), const Color(0xFF2A3942));
  static Color get incomingTimestamp => _v(const Color(0xFF667781), const Color(0xFF8696A0));

  /// Cards and banners sitting on top of [surface].
  static Color get raised => _v(const Color(0xFFFFFFFF), const Color(0xFF1B262C));

  /// Amber notice banners (unlock prompts, warnings).
  static Color get notice => _v(const Color(0xFFFFF4E5), const Color(0xFF2B2416));

  /// Bottom navigation: selected icon/label, unselected icon/label.
  static Color get navSelected => _v(const Color(0xFF103529), const Color(0xFF00A884));
  static Color get navUnselected => _v(const Color(0xFF54656F), const Color(0xFF8696A0));

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

/// Holds the user's theme choice (`clair` / `sombre` / `système`), persisted
/// in shared preferences, and repaints the app when it changes.
abstract final class AppThemeController {
  static const String _key = 'theme_mode';

  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  /// Loads the stored choice. Safe to call more than once.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode.value = switch (prefs.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  /// Applies and stores a new choice.
  static Future<void> set(ThemeMode value) async {
    mode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      switch (value) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }

  /// The brightness the app actually renders with right now: system theme
  /// follows the device setting, the two others are explicit.
  static Brightness effectiveBrightness() {
    switch (mode.value) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }
}

/// Builds the Material theme that makes the app look like WhatsApp.
///
/// Call [preparePalette] first (or build both themes through
/// [buildLiberTheme] for the brightness you intend to show) so that
/// [WaPalette] resolves to the matching colours.
ThemeData buildLiberTheme({Brightness brightness = Brightness.light}) {
  WaPalette.brightness = brightness;
  final isDark = brightness == Brightness.dark;

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: WaPalette.primary,
      primary: WaPalette.primary,
      secondary: WaPalette.accent,
      surface: WaPalette.surface,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: WaPalette.surface,
  );

  return base.copyWith(
    // WhatsApp's 2025 layout: light header, dark text, green accents.
    appBarTheme: AppBarTheme(
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
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: WaPalette.accent,
      unselectedLabelColor: WaPalette.textSecondary,
      labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      unselectedLabelStyle:
          const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      indicatorColor: WaPalette.accent,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: WaPalette.fab,
      foregroundColor: Colors.white,
      elevation: 3,
    ),
    dividerTheme: DividerThemeData(
      color: WaPalette.divider,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      iconColor: WaPalette.iconMuted,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: WaPalette.composerField,
      hintStyle: TextStyle(color: WaPalette.textSecondary, fontSize: 16),
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
      backgroundColor:
          isDark ? const Color(0xFF2A3942) : const Color(0xFF111B21),
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
            : (isDark
                ? const Color(0xFF3B4A54)
                : const Color(0xFFD9DBDD)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: WaPalette.composerField,
      selectedColor: isDark
          ? const Color(0xFF005C4B)
          : const Color(0xFFD3F4E5),
      showCheckmark: false,
      labelStyle: const TextStyle(fontSize: 13.5),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
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
