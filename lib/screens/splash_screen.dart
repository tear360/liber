import 'package:flutter/material.dart';

import '../matrix/matrix_service.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Waits for [MatrixService.bootstrap] to finish, then routes to the chat list
/// when a session was restored, or to the login form otherwise.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _service = MatrixService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_route);
    _service.bootstrap().whenComplete(_route);
  }

  @override
  void dispose() {
    _service.removeListener(_route);
    super.dispose();
  }

  void _route() {
    if (!mounted || !_service.bootstrapped) return;
    _service.removeListener(_route);

    final next = _service.isLoggedIn
        ? const HomeScreen()
        : const LoginScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: animation,
          child: next,
        ),
        transitionDuration: const Duration(milliseconds: 320),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WaPalette.primaryDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text(
                'L',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w700,
                  color: WaPalette.primaryDark,
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Liber',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Matrix, dans votre poche',
              style: TextStyle(color: Color(0xFFB8E0D6), fontSize: 14),
            ),
            const SizedBox(height: 34),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
