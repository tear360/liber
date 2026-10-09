import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_service.dart';
import '../theme.dart';
import 'verification_screen.dart';

/// « Sécurité des messages » : the single place where the encrypted history
/// becomes readable on this device.
///
/// A freshly logged-in session starts out unverified, so the homeserver and
/// the other participants share no room keys with it: every encrypted message
/// shows up as a lock. Two ways out, both offered here:
///
/// - verify this session against another of the account's devices (emoji
///   comparison), or
/// - enter the account's recovery key, which unlocks secure secret storage
///   and lets the SDK download the room keys from the server-side backup.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SecurityScreen()),
    );
  }

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _service = MatrixService.instance;
  final _recoveryController = TextEditingController();

  bool _verifying = false;
  bool _restoring = false;
  bool _keysUnlocked = false;
  String? _error;
  String? _status;

  Client? get _client => _service.client;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshKeyState());
  }

  @override
  void dispose() {
    _recoveryController.dispose();
    super.dispose();
  }

  Future<void> _refreshKeyState() async {
    final unlocked = await _service.keysUnlocked();
    if (mounted) setState(() => _keysUnlocked = unlocked);
  }

  /// Starts an emoji verification with the account's other sessions, which is
  /// what marks this device as trusted on the server.
  Future<void> _startVerification() async {
    final client = _client;
    final userId = client?.userID;
    if (client == null || userId == null || _verifying) return;

    final keyList = client.userDeviceKeys[userId];
    if (keyList == null) {
      setState(
        () => _error =
            "Les clés de votre compte ne sont pas encore disponibles. "
            'Réessayez dans un instant.',
      );
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    KeyVerification? request;
    try {
      request = await keyList.startVerification();
      if (!mounted) return;
      await VerificationScreen.open(context, request);
      await _refreshKeyState();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Vérification impossible : '
              '${MatrixService.describeMatrixError(e)}',
        );
      }
      try {
        await request?.cancel('m.user', true);
      } catch (_) {
        // The other side may already have closed the request.
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// Unlocks secure secret storage with the typed recovery key and downloads
  /// the room keys kept in the server-side backup.
  Future<void> _restore() async {
    if (_restoring) return;

    setState(() {
      _restoring = true;
      _error = null;
      _status = null;
    });

    try {
      await _service.restoreWithRecoveryKey(_recoveryController.text);
      _recoveryController.clear();
      if (!mounted) return;
      setState(() {
        _keysUnlocked = true;
        _status = 'Les clés de votre compte ont été restaurées : les messages '
            'chiffrés disponibles s’affichent en clair. Ouvrez une discussion '
            'pour les voir.';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = MatrixService.describeMatrixError(e));
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = _client;
    final userId = client?.userID;
    final verified = _service.sessionVerified;
    final canVerify =
        client != null && userId != null && client.encryption != null;
    final hasRecoveryKey = _service.recoveryKeyAvailable;
    final canRestore = !_restoring && _recoveryController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Sécurité des messages'),
        backgroundColor: WaPalette.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: WaPalette.primary,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: verified ? WaPalette.accent.withValues(alpha: 0.12)
                    : const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    verified ? Icons.verified_user : Icons.gpp_maybe_outlined,
                    color: verified
                        ? WaPalette.accent
                        : const Color(0xFFE0902B),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      verified
                          ? 'Cet appareil est vérifié : votre historique '
                              'chiffré s’affiche en clair.'
                          : 'Cet appareil n’est pas encore vérifié. Les '
                              'messages chiffrés reçus avant son ajout sont '
                              'illisibles : déverrouillez-les ci-dessous.',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: WaPalette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _Notice(
                text: _error!,
                icon: Icons.error_outline,
                color: const Color(0xFFB3261E),
              ),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              _Notice(
                text: _status!,
                icon: Icons.check_circle_outline,
                color: WaPalette.accent,
              ),
            ],
            const SizedBox(height: 20),

            // ---- Another device -----------------------------------------
            const _SectionTitle('Vérifier avec un autre appareil'),
            const _Explanation(
              'Ouvrez Liber (ou Element) sur un appareil déjà connecté à ce '
              'compte, acceptez la demande, puis comparez les émojis affichés '
              'sur les deux écrans.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (!canVerify || _verifying) ? null : _startVerification,
              icon: _verifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2),
              label: const Text('Vérifier cet appareil'),
            ),

            const SizedBox(height: 28),

            // ---- Recovery key -------------------------------------------
            const _SectionTitle('Déverrouiller avec la clé de récupération'),
            _Explanation(
              hasRecoveryKey
                  ? 'Sans second appareil disponible : saisissez la clé de '
                      'récupération de votre compte (Paramètres → Sécurité sur '
                      'une session déjà vérifiée). Les messages reçus sont '
                      'alors déchiffrés ici.'
                  : 'Aucune clé de récupération n’est enregistrée sur ce '
                      'compte : seule la vérification avec un autre appareil '
                      'peut débloquer les messages.',
            ),
            if (hasRecoveryKey) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _recoveryController,
                enabled: !_restoring,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Clé de récupération ou phrase secrète',
                  hintText: 'Ex. EsT… quatre groupes de 12 caractères',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _restore(),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canRestore ? _restore : null,
                icon: _restoring
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.key_outlined),
                label: Text(
                  _restoring ? 'Téléchargement des clés…' : 'Déverrouiller',
                ),
              ),
              if (_restoring)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Le téléchargement des clés peut prendre une minute sur '
                    'un compte ancien.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: WaPalette.textSecondary,
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 28),

            // ---- Status --------------------------------------------------
            const _SectionTitle('État'),
            _StatusRow(
              label: 'Cet appareil',
              value: verified ? 'Vérifié' : 'Non vérifié',
              ok: verified,
            ),
            _StatusRow(
              label: 'Clé de récupération',
              value: hasRecoveryKey ? 'Enregistrée' : 'Absente',
              ok: hasRecoveryKey,
            ),
            _StatusRow(
              label: 'Clés de discussion',
              value: _keysUnlocked ? 'Déverrouillées' : 'Verrouillées',
              ok: _keysUnlocked,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: WaPalette.accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13.5,
        height: 1.45,
        color: WaPalette.textSecondary,
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.icon, required this.color});

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.ok,
  });

  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.remove_circle_outline,
            size: 18,
            color: ok ? WaPalette.accent : WaPalette.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                color: WaPalette.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: WaPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
