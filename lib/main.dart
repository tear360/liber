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
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  // Without this, DateFormat('fr') throws a LocaleDataException that only
  // shows up as a blank grey screen in release builds.
  await initializeDateFormatting('fr');
  Intl.defaultLocale = 'fr';
  runApp(const LiberApp());
}

class LiberApp extends StatelessWidget {
  const LiberApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liber',
      debugShowCheckedModeBanner: false,
      theme: buildLiberTheme(),
      home: const SplashScreen(),
    );
  }
}
