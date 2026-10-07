import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Owns the single [Client] for the process: opening the local store,
/// restoring a session left by a previous run, and performing password login.
///
/// Everything the UI needs to know is exposed through [notifyListeners];
/// live room and message updates flow separately through [Client.onSync] and
/// the per-room [Timeline] callbacks so this never turns into a bottleneck.
class MatrixService extends ChangeNotifier {
  MatrixService._();

  static final MatrixService instance = MatrixService._();

  static const String clientName = 'Liber';
  static const String defaultHomeserver = 'https://matrix.org';

  Client? _client;
  bool _bootstrapped = false;
  bool _busy = false;
  bool _e2eeReady = false;
  String? _error;

  Client? get client => _client;
  bool get bootstrapped => _bootstrapped;
  bool get busy => _busy;

  /// True when the native Rust crypto library loaded, so encrypted rooms work.
  bool get e2eeReady => _e2eeReady;
  bool get encryptionEnabled => _client?.encryptionEnabled ?? false;
  bool get isLoggedIn => _client?.isLogged() ?? false;
  String? get error => _error;
  void clearError() {
    _error = null;
  }

  String? get userId => _client?.userID;
  String? get homeserverUrl => _client?.homeserver?.toString();

  /// Opens the local database and, when one exists, resumes the previous
  /// session. Safe to call more than once.
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _busy = true;
    notifyListeners();

    try {
      try {
        await vodozemac.init();
        _e2eeReady = true;
      } catch (_) {
        // No encryption is a degraded experience, not a fatal error: plain
        // rooms still work, so the app carries on.
        _e2eeReady = false;
      }

      final docs = await getApplicationDocumentsDirectory();
      final database = await openDatabase(p.join(docs.path, 'liber.db'));
      final matrixDatabase = await MatrixSdkDatabase.init(
        clientName,
        database: database,
        sqfliteFactory: databaseFactory,
      );

      final client = Client(clientName, database: matrixDatabase);
      _client = client;

      client.onLoginStateChanged.stream.listen((state) {
        if (state == LoginState.loggedIn) _error = null;
        notifyListeners();
      });

      // `getClient` returns null on a fresh install, so init() is only called
      // when there is actually a stored session to resume.
      final stored = await matrixDatabase.getClient(clientName);
      if (stored != null) {
        try {
          await client.init();
        } catch (e) {
          _error = describeMatrixError(e);
        }
      }
    } catch (e) {
      _error = describeMatrixError(e);
    } finally {
      _busy = false;
      _bootstrapped = true;
      notifyListeners();
    }
  }

  /// Logs in with a password. Returns true on success; on failure [error] is
  /// set to a message that is safe to show to the user.
  Future<bool> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      _error = "Le client Matrix n'est pas prêt.";
      notifyListeners();
      return false;
    }

    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final (server, user) = _resolveTarget(homeserver, username);
      if (user.isEmpty) {
        _error = 'Veuillez saisir un identifiant.';
        return false;
      }
      await client.checkHomeserver(server);
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: user),
        password: password,
        initialDeviceDisplayName: 'Liber (Android)',
      );
      await _rememberHomeserver(client.homeserver?.toString());
      return true;
    } catch (e) {
      _error = describeMatrixError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final client = _client;
    if (client == null) return;
    _busy = true;
    notifyListeners();
    try {
      await client.logout();
    } catch (e) {
      // The homeserver may be unreachable; dropping the local session still
      // signs the user out of this device.
      _error = describeMatrixError(e);
      await client.clear();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Splits what the user typed into a homeserver URL and a login name.
  /// A full `@alice:example.org` overrides the homeserver field.
  static (Uri, String) _resolveTarget(String homeserver, String username) {
    var server = homeserver.trim();
    var user = username.trim();
    if (user.startsWith('@')) user = user.substring(1);

    final separator = user.indexOf(':');
    if (separator > 0) {
      final domain = user.substring(separator + 1);
      if (domain.contains('.')) {
        server = 'https://$domain';
        user = user.substring(0, separator);
      }
    }

    if (server.isEmpty) server = defaultHomeserver;
    if (!server.contains('://')) server = 'https://$server';
    return (Uri.parse(server), user);
  }

  Future<void> _rememberHomeserver(String? url) async {
    if (url == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_homeserver', url);
  }

  static Future<String> lastHomeserver() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_homeserver') ?? defaultHomeserver;
  }

  /// Turns an SDK exception into a sentence a user can act on.
  static String describeMatrixError(Object error) {
    if (error is MatrixException) {
      final code = error.errcode;
      switch (code) {
        case 'M_FORBIDDEN':
          return 'Identifiants incorrects.';
        case 'M_LIMIT_EXCEEDED':
          return 'Trop de tentatives. Réessayez dans un instant.';
        case 'M_UNKNOWN_TOKEN':
          return 'Session expirée, veuillez vous reconnecter.';
        case 'M_USER_IN_USE':
          return 'Cet identifiant est déjà utilisé.';
        case 'M_UNRECOGNIZED':
          return 'Le serveur ne prend pas en charge cette opération.';
        default:
          return 'Erreur Matrix ($code) : ${error.errorMessage}';
      }
    }
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('HandshakeException') ||
        text.contains('Connection closed')) {
      return 'Impossible de joindre le serveur. Vérifiez votre connexion.';
    }
    if (text.contains('TimeoutException')) {
      return 'Le serveur met trop de temps à répondre.';
    }
    return text;
  }
}
