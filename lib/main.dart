import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'screens/splash_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
    <DeviceOrientation>[DeviceOrientation.portraitUp],
  );
  // Without this, DateFormat('fr') throws a LocaleDataException that only
  // shows up as a blank grey screen in release builds.
  await initializeDateFormatting('fr');
  Intl.defaultLocale = 'fr';

  // The stored theme choice has to be known before the first frame: it picks
  // the palette and the status bar icon colour.
  await AppThemeController.load();
  final brightness = AppThemeController.effectiveBrightness();
  WaPalette.brightness = brightness;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
    ),
  );

  runApp(const LiberApp());
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
