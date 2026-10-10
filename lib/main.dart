import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'diagnostics.dart';
import 'notifications/notification_service.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // An uncaught asynchronous error (a failing sync, a broken stream) used
    // to kill the app with no trace. It is now journaled — Sécurité →
    // Journal shows it after the next start — and the app carries on.
    PlatformDispatcher.instance.onError = (error, stack) {
      Diagnostics.instance.add('Erreur non gérée : $error');
      return true;
    };
    FlutterError.onError = (details) {
      Diagnostics.instance.add(
        'Erreur d’interface : ${details.exception}',
      );
      FlutterError.presentError(details);
    };

    // The four steps below are independent (orientation, French date data,
    // stored theme, notification channel), so they run together: the wait is
    // the slowest one instead of the sum of all four.
    await Future.wait(<Future<void>>[
      SystemChrome.setPreferredOrientations(
        <DeviceOrientation>[DeviceOrientation.portraitUp],
      ),
      // Without this, DateFormat('fr') throws a LocaleDataException that only
      // shows up as a blank grey screen in release builds.
      initializeDateFormatting('fr'),
      // The stored theme choice has to be known before the first frame: it
      // picks the palette and the status bar icon colour.
      AppThemeController.load(),
      // Notification channel and tap handler must exist before the first
      // sync delivers a message.
      NotificationService.init(),
    ]);
    Intl.defaultLocale = 'fr';

    final brightness = AppThemeController.effectiveBrightness();
    WaPalette.brightness = brightness;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );

    runApp(const LiberApp());
  }, (error, stack) {
    // Same net for errors thrown outside the framework's own handling.
    Diagnostics.instance.add('Erreur non gérée : $error');
  });
}

class LiberApp extends StatelessWidget {
  const LiberApp({super.key});

  /// Built once each: the palette is baked in while the theme is created, so
  /// a rebuild only has to point [WaPalette] back at the effective colour.
  static final ThemeData _lightTheme =
      buildLiberTheme(brightness: Brightness.light);
  static final ThemeData _darkTheme =
      buildLiberTheme(brightness: Brightness.dark);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.mode,
      builder: (context, _) {
        // Children of this builder read the palette while they build.
        WaPalette.brightness = AppThemeController.effectiveBrightness();
        return MaterialApp(
          title: 'Liber',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: AppThemeController.mode.value,
          home: const SplashScreen(),
        );
      },
    );
  }
}
