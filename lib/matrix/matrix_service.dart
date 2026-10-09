import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../notifications/notification_service.dart';

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

  Encryption? get encryption => _client?.encryption;

  /// True when the account has signed this session with its cross-signing
  /// key: peers then share their room keys with it and encrypted messages
  /// become readable.
  bool get sessionVerified {
    final client = _client;
    final userId = client?.userID;
    final deviceId = client?.deviceID;
    if (client == null || userId == null || deviceId == null) return false;
    return client.userDeviceKeys[userId]?.deviceKeys[deviceId]?.verified ==
        true;
  }

  /// True when the account keeps its keys in secure secret storage, so the
  /// recovery key alone can unlock the messages on this device.
  bool get recoveryKeyAvailable =>
      _client?.encryption?.ssss.defaultKeyId != null;

  /// True once the megolm backup key is cached, meaning the room keys stored
  /// in the server-side backup can be downloaded without another device.
  Future<bool> keysUnlocked() async {
    final encryption = _client?.encryption;
    if (encryption == null) return false;
    try {
      return await encryption.keyManager.isCached();
    } catch (_) {
      return false;
    }
  }

  static const String wrongRecoveryKey =
      'Clé de récupération ou phrase secrète incorrecte.';

  /// Opens secure secret storage with [credential] (the recovery key or the
  /// passphrase chosen by the user) and downloads the room keys kept in the
  /// server-side backup.
  ///
  /// This is what makes the history readable on a freshly logged-in device
  /// without waiting for another session to come online: unlocking also
  /// caches the cross-signing keys, and the SDK self-signs this device with
  /// them, which is the same trusted state an interactive verification
  /// reaches.
  Future<void> restoreWithRecoveryKey(String credential) async {
    final client = _client;
    final encryption = client?.encryption;
    if (client == null || encryption == null) {
      throw MatrixServiceException(
        "Le chiffrement n'est pas encore prêt sur cet appareil.",
      );
    }
    final value = credential.trim();
    if (value.isEmpty) {
      throw MatrixServiceException('Saisissez votre clé de récupération.');
    }

    final OpenSSSS open;
    try {
      open = encryption.ssss.open();
    } catch (_) {
      throw MatrixServiceException(
        "Ce compte n'a pas de clé de récupération enregistrée : utilisez "
        'la vérification avec un autre appareil.',
      );
    }

    try {
      await open.unlock(keyOrPassphrase: value);
    } on InvalidPassphraseException {
      throw MatrixServiceException(wrongRecoveryKey);
    } on FormatException {
      // A mistyped recovery key does not decode at all.
      throw MatrixServiceException(wrongRecoveryKey);
    }

    await downloadRoomKeys(encryption);
  }

  /// Session ids already asked for, so repeated retries do not spam the
  /// other devices of the account with to-device requests.
  final Set<String> _requestedSessions = <String>{};

  /// Asks for the room keys this device is still missing.
  ///
  /// Verifying a device only proves it to the account — nobody sends the
  /// old megolm keys on their own, they have to be requested. The online
  /// backup is tried first and, when it does not exist (the common case on
  /// matrix.org), the request falls through to the account's other devices.
  /// That second path is what makes the history readable after a
  /// verification.
  Future<void> requestMissingKeys() async {
    final client = _client;
    final encryption = client?.encryption;
    if (client == null || encryption == null) return;

    for (final room in client.rooms) {
      if (room.isSpace || room.membership == Membership.leave) continue;
      if (!room.encrypted) continue;

      final lastEvent = room.lastEvent;
      if (lastEvent == null ||
          lastEvent.type != EventTypes.Encrypted ||
          lastEvent.messageType != MessageTypes.BadEncrypted ||
          lastEvent.content['can_request_session'] != true) {
        continue;
      }

      final sessionId = lastEvent.content.tryGet<String>('session_id');
      final senderKey = lastEvent.content.tryGet<String>('sender_key');
      if (sessionId == null || senderKey == null) continue;

      final key = '${room.id}|$sessionId';
      if (!_requestedSessions.add(key)) continue;

      unawaited(_requestSessionKey(room, sessionId, senderKey, encryption));
    }
    notifyListeners();
  }

  /// Never lets a single unreachable peer break a key request.
  static Future<void> _requestSessionKey(
    Room room,
    String sessionId,
    String? senderKey,
    Encryption encryption,
  ) async {
    try {
      await encryption.keyManager.request(
        room,
        sessionId,
        senderKey,
        tryOnlineBackup: true,
        onlineKeyBackupOnly: false,
      );
    } catch (_) {
      // Best effort: the retry stays available in the conversation.
    }
  }

  /// Pulls every room key out of the server-side backup.
  Future<void> downloadRoomKeys([Encryption? encryption]) async {
    final target = encryption ?? _client?.encryption;
    final client = _client;
    if (target == null || client == null) return;

    // Without that secret in secure storage the SDK would return quietly and
    // the user would believe the history had been restored.
    if (!await target.keyManager.isCached()) {
      throw MatrixServiceException(
        "Ce compte ne sauvegarde pas ses clés : seule la vérification avec "
        'un autre appareil peut débloquer les messages.',
      );
    }

    try {
      await target.keyManager.loadAllKeys();
    } on MatrixException catch (e) {
      if (e.errcode == 'M_NOT_FOUND') {
        throw MatrixServiceException(
          "Ce compte n'a pas de sauvegarde de clés : les messages déjà "
          'reçus resteront illisibles sur cet appareil.',
        );
      }
      rethrow;
    }

    // Rooms already on screen pick the new keys up through the SDK's session
    // key stream; the others decrypt from the store when they are opened
    // again. Nudging the client makes the chat list refresh its previews.
    notifyListeners();
  }

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

      // Without declaring the methods this client supports, the SDK
      // silently drops every incoming key-verification request — which is
      // why "verify this device" prompts never appeared in the app.
      final client = Client(
        clientName,
        database: matrixDatabase,
        verificationMethods: const {
          KeyVerificationMethod.emoji,
          KeyVerificationMethod.numbers,
        },
      );
      _client = client;

      // Every event the account's push rules want to announce becomes a
      // system notification while the app is in the background.
      NotificationService.bind(client);

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
          if (client.isLogged()) {
            unawaited(NotificationService.requestPermission());
          }
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
      unawaited(NotificationService.requestPermission());
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

/// A failure that already carries a sentence meant for the user, so the UI
/// can show it as-is instead of a stack trace.
class MatrixServiceException implements Exception {
  MatrixServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
