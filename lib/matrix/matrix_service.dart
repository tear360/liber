import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../diagnostics.dart';
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

  /// Every device the account knows about, this one first when it is in the
  /// list. This is the "historique des connexions" view: each entry is a
  /// session that can read the account's encrypted messages.
  List<DeviceKeys> get accountDevices {
    final client = _client;
    final userId = client?.userID;
    if (client == null || userId == null) return const [];
    final own = client.userDeviceKeys[userId]?.deviceKeys.values ??
        const <DeviceKeys>[];
    final devices = own.where((d) => d.isValid).toList()
      ..sort((a, b) {
        final aMine = a.deviceId == client.deviceID;
        final bMine = b.deviceId == client.deviceID;
        if (aMine != bMine) return aMine ? -1 : 1;
        return (a.deviceDisplayName ?? a.deviceId ?? '')
            .toLowerCase()
            .compareTo((b.deviceDisplayName ?? b.deviceId ?? '').toLowerCase());
      });
    return devices;
  }

  /// Marks one device of the account as trusted on the server. Peers then
  /// share the room keys with it, which is what makes messages readable.
  Future<void> markDeviceVerified(DeviceKeys device) async {
    Diagnostics.instance
        .add('Appareil ${device.deviceId} marqué comme vérifié');
    await device.setVerified(true);
    notifyListeners();
  }

  /// Drops the trust placed in one device.
  Future<void> markDeviceUnverified(DeviceKeys device) async {
    Diagnostics.instance
        .add('Appareil ${device.deviceId} marqué comme non vérifié');
    await device.setVerified(false);
    notifyListeners();
  }

  /// Stops trusting a device outright: it is blocked and its keys are
  /// ignored from then on.
  Future<void> blockDevice(DeviceKeys device) async {
    Diagnostics.instance.add('Appareil ${device.deviceId} bloqué');
    await device.setBlocked(true);
    notifyListeners();
  }

  /// Human-readable reason why a session cannot read the encrypted history
  /// on this device, or `null` when everything is in place.
  String? get encryptionStatus {
    final client = _client;
    if (client == null) return 'Aucune session ouverte.';
    if (!encryptionEnabled) {
      return 'Le chiffrement n’a pas pu démarrer sur cet appareil : les '
          'messages chiffrés restent illisibles.';
    }
    if (!sessionVerified) {
      return 'Cet appareil n’est pas vérifié : les messages chiffrés reçus '
          'avant son ajout restent verrouillés.';
    }
    return null;
  }

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
  Future<void> requestMissingKeys({bool force = false}) async {
    final client = _client;
    final encryption = client?.encryption;
    if (client == null || encryption == null) return;

    // Requests sent before the account trusted this device are refused by the
    // peers; without clearing the dedup set here they would never be asked
    // again and the history would stay locked forever.
    if (force) _requestedSessions.clear();

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

      Diagnostics.instance.add('Clé demandée pour ${room.getLocalizedDisplayname()}');
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

  /// Builds the [Client] with everything the app wires around it. Called
  /// once at bootstrap and again by [recoverCrypto], which has to rebuild
  /// the client from scratch because `Client.init()` refuses to run twice.
  Client _createClient(MatrixSdkDatabase database) {
    // Without declaring the methods this client supports, the SDK
    // silently drops every incoming key-verification request — which is
    // why "verify this device" prompts never appeared in the app.
    final client = Client(
      clientName,
      database: database,
      verificationMethods: const {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.numbers,
      },
    );

    // Every event the account's push rules want to announce becomes a
    // system notification while the app is in the background.
    NotificationService.bind(client);

    client.onLoginStateChanged.stream.listen((state) {
      if (state == LoginState.loggedIn) _error = null;
      notifyListeners();
    });
    return client;
  }

  /// Opens the local database and, when one exists, resumes the previous
  /// session. Safe to call more than once.
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _busy = true;
    notifyListeners();
    Diagnostics.instance.attachSdkLogs();

    try {
      try {
        await vodozemac.init();
        _e2eeReady = true;
        Diagnostics.instance.add('Chiffrement (vodozemac) démarré');
      } catch (e) {
        // No encryption is a degraded experience, not a fatal error: plain
        // rooms still work, so the app carries on.
        _e2eeReady = false;
        Diagnostics.instance.add(
          'AVERTISSEMENT : le chiffrement n’a pas pu démarrer — $e',
        );
      }

      final docs = await getApplicationDocumentsDirectory();
      final database = await openDatabase(p.join(docs.path, 'liber.db'));
      final matrixDatabase = await MatrixSdkDatabase.init(
        clientName,
        database: database,
        sqfliteFactory: databaseFactory,
      );

      _client = _createClient(matrixDatabase);

      // `getClient` returns null on a fresh install, so init() is only called
      // when there is actually a stored session to resume.
      final stored = await matrixDatabase.getClient(clientName);
      if (stored != null) {
        try {
          await clientSafeInit();
          if (_client?.isLogged() ?? false) {
            unawaited(NotificationService.requestPermission());
            unawaited(refreshDeviceKeys());
          }
        } catch (e) {
          _error = describeMatrixError(e);
          Diagnostics.instance.add('Reprise de session impossible — $e');
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

  /// `Client.init()` with the encryption state recorded in the journal, so a
  /// silent crypto failure (the cause of "every message stays locked") is
  /// visible in the diagnostic log instead of only in a debugger.
  Future<void> clientSafeInit() async {
    await _client?.init();
    final encryption = _client?.encryption;
    if (_client?.isLogged() ?? false) {
      Diagnostics.instance.add(
        encryption == null
            ? 'Session reprise SANS chiffrement : les salons chiffrés seront '
                'illisibles et l’envoi y sera bloqué.'
            : 'Session reprise avec chiffrement actif',
      );
    }
  }

  /// Reloading the native crypto library after a failed start.
  ///
  /// `_encryption` is only built inside `Client.init()`, which cannot run a
  /// second time on a logged-in client — so the way back is a fresh client
  /// resumed from the same stored session, once the library loads.
  Future<bool> recoverCrypto() async {
    if (_client?.encryption != null) return true;
    final wasLoggedIn = _client?.isLogged() ?? false;
    Diagnostics.instance.add(
      'Nouvel essai de démarrage du chiffrement'
      '${wasLoggedIn ? ' (session conservée)' : ''}',
    );
    try {
      await vodozemac.init();
      _e2eeReady = true;
    } catch (e) {
      Diagnostics.instance.add(
        'Bibliothèque de chiffrement toujours indisponible — $e',
      );
      return false;
    }
    if (!wasLoggedIn) return false;

    final previous = _client;
    try {
      _client = null;
      await previous?.dispose();
      final docs = await getApplicationDocumentsDirectory();
      final database = await openDatabase(p.join(docs.path, 'liber.db'));
      final matrixDatabase = await MatrixSdkDatabase.init(
        clientName,
        database: database,
        sqfliteFactory: databaseFactory,
      );
      final client = _createClient(matrixDatabase);
      _client = client;
      final stored = await matrixDatabase.getClient(clientName);
      if (stored == null) return false;
      await client.init();
      final ok = client.encryption != null;
      Diagnostics.instance.add(
        ok
            ? 'Chiffrement actif après reconstruction du client'
            : 'Le chiffrement reste inactif après reconstruction',
      );
      if (ok) {
        unawaited(NotificationService.requestPermission());
        unawaited(refreshDeviceKeys());
      }
      notifyListeners();
      return ok;
    } catch (e) {
      Diagnostics.instance.add('Reconstruction du client impossible — $e');
      notifyListeners();
      return false;
    }
  }

  /// Starts an emoji verification against one specific device of the account
  /// (own devices and contacts alike). Returns the request so the caller can
  /// drive the comparison screen, and asks for the room keys afterwards.
  Future<KeyVerification> startDeviceVerification(DeviceKeys device) async {
    await refreshDeviceKeys();
    final request = await device.startVerification();
    Diagnostics.instance
        .add('Vérification demandée à l’appareil ${device.deviceId}');
    return request;
  }

  /// Starts the verification this screen needs: with one other device on the
  /// account it targets that device, otherwise the account's own cross-signing
  /// key.
  ///
  /// The device list is fetched first. The SDK cancels an incoming request it
  /// cannot resolve to a known device (`im.fluffychat.unknown_device`), which
  /// used to make every attempt look like the other side had refused it.
  Future<KeyVerification> startSelfVerification() async {
    await refreshDeviceKeys();
    final client = _client;
    final userId = client?.userID;
    if (client == null || userId == null) {
      throw MatrixServiceException('Aucune session ouverte.');
    }
    final keyList = client.userDeviceKeys[userId];
    if (keyList == null) {
      throw MatrixServiceException(
        'Les clés de votre compte ne sont pas encore disponibles : '
        'réessayez dans un instant.',
      );
    }
    Diagnostics.instance.add('Vérification du compte démarrée');
    return keyList.startVerification();
  }

  /// Connection history as the homeserver sees it: for every session, the
  /// last IP address and the last time it talked to the server. Filled by
  /// [refreshConnectionHistory] and read by the Sécurité screen.
  List<Device> serverSessions = const [];

  /// Fetches the server-side session list (`GET /_matrix/client/v3/devices`),
  /// which carries `last_seen_ip` and `last_seen_ts` — the true connection
  /// history, unlike the SDK's local `lastActive` guess.
  Future<void> refreshConnectionHistory() async {
    final client = _client;
    if (client == null || client.userID == null) return;
    try {
      final devices = await client.getDevices();
      serverSessions = devices ?? const [];
      Diagnostics.instance.add(
        'Historique des connexions : ${serverSessions.length} session(s)',
      );
      notifyListeners();
    } catch (e) {
      Diagnostics.instance.add('Historique des connexions impossible — $e');
    }
  }

  /// The server-side record for [deviceId], if the history was fetched.
  Device? serverSessionFor(String? deviceId) {
    if (deviceId == null) return null;
    for (final session in serverSessions) {
      if (session.deviceId == deviceId) return session;
    }
    return null;
  }

  /// Refreshes the account's device list. A fresh session that has not
  /// queried device keys yet cancels every incoming verification request it
  /// does not recognise (`im.fluffychat.unknown_device`), which is why a
  /// verification started from another device could do nothing here.
  Future<void> refreshDeviceKeys() async {
    final client = _client;
    if (client == null || client.userID == null) return;
    try {
      await client.updateUserDeviceKeys();
      final count =
          client.userDeviceKeys[client.userID]?.deviceKeys.length ?? 0;
      Diagnostics.instance.add('Liste des appareils du compte : $count');
      notifyListeners();
    } catch (e) {
      Diagnostics.instance.add('Liste des appareils impossible — $e');
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
