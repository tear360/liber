import 'dart:async';

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

  // Release builds show a blank screen for any uncaught build error. Show a
  // readable error card instead so failures are visible and reportable.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  ErrorWidget.builder = (details) => _CrashCard(details: details);

  runApp(const LiberApp());
}

/// Replaces Flutter's grey "error" box in debug and the blank screen in
/// release with a small card explaining that something failed to render.
class _CrashCard extends StatelessWidget {
  const _CrashCard({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFFBF5),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber,
                  size: 40, color: Color(0xFFE0902B)),
              const SizedBox(height: 12),
              const Text(
                "Un élément n'a pas pu être affiché",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F1914),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                details.exception.toString(),
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF54656F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
