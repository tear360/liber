import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liber/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('WaPalette', () {
    test('resolves light and dark surfaces from the active brightness', () {
      WaPalette.brightness = Brightness.light;
      expect(WaPalette.surface, const Color(0xFFFFFFFF));
      expect(WaPalette.wallpaper, const Color(0xFFEFE7DE));
      expect(WaPalette.textPrimary, const Color(0xFF111B21));

      WaPalette.brightness = Brightness.dark;
      expect(WaPalette.surface, const Color(0xFF111B21));
      expect(WaPalette.wallpaper, const Color(0xFF0B141A));
      expect(WaPalette.textPrimary, const Color(0xFFE9EDEF));
      expect(WaPalette.outgoingBubble, const Color(0xFF005C4B));
      expect(WaPalette.notice, const Color(0xFF2B2416));
      // Avatar hues must stay readable on both backgrounds.
      expect(WaPalette.avatarPalette, hasLength(8));

      WaPalette.brightness = Brightness.light;
    });

    test('the dark theme bakes in dark surfaces, the light one light', () {
      final dark = buildLiberTheme(brightness: Brightness.dark);
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF111B21));
      expect(dark.appBarTheme.backgroundColor, const Color(0xFF111B21));
      expect(
        dark.appBarTheme.foregroundColor,
        const Color(0xFFE9EDEF),
      );
      // Status bar icons have to stay legible over the header.
      expect(
        dark.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
        Brightness.light,
      );

      final light = buildLiberTheme(brightness: Brightness.light);
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
      expect(
        light.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
        Brightness.dark,
      );

      // Building the themes leaves the palette on whichever one was last;
      // the app resets it to the effective value before children build.
      WaPalette.brightness = Brightness.light;
    });
  });

  group('AppThemeController', () {
    test('persists the chosen mode and restores it', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      addTearDown(() => AppThemeController.mode.value = ThemeMode.system);

      await AppThemeController.set(ThemeMode.dark);
      expect(AppThemeController.mode.value, ThemeMode.dark);

      AppThemeController.mode.value = ThemeMode.system;
      await AppThemeController.load();
      expect(AppThemeController.mode.value, ThemeMode.dark);

      await AppThemeController.set(ThemeMode.light);
      AppThemeController.mode.value = ThemeMode.dark;
      await AppThemeController.load();
      expect(AppThemeController.mode.value, ThemeMode.light);
    });
  });
}
