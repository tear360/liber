import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/encryption.dart';

import '../matrix/matrix_service.dart';
import '../theme.dart';

/// Interactive account verification (cross-signing).
///
/// Entry point: the user taps "Vérifier cet appareil" in the Compte tab,
/// which runs a self-verification against the account's own cross-signing
/// key. When the homeserver stores the signing secrets in SSSS (secure
/// secret storage), the user is asked for their recovery key or passphrase.
///
/// Drives a [KeyVerification] through its [KeyVerificationState] machine;
/// every state change rebuilds through [onUpdate].
class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key, required this.request});

  final KeyVerification request;

  static Future<void> open(BuildContext context, KeyVerification request) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VerificationScreen(request: request)),
    );
  }

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late KeyVerification _request;
  final _recoveryKeyController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _request = widget.request;
    _request.onUpdate = _onUpdate;
  }

  @override
  void dispose() {
    _recoveryKeyController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
    // The account now trusts this device: nobody pushes the old room keys on
    // their own, so ask for them (backup first, then the other devices).
    if (_request.state == KeyVerificationState.done && !_keysRequested) {
      _keysRequested = true;
      unawaited(MatrixService.instance.requestMissingKeys());
    }
  }

  bool _keysRequested = false;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _request.acceptVerification();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptSas() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _request.acceptSas();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSSSS({bool skip = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _request.openSSSS(
        keyOrPassphrase: skip ? null : _recoveryKeyController.text.trim(),
        skip: skip,
      );
      _recoveryKeyController.clear();
    } catch (e) {
      setState(() {
        _error = skip ? e.toString() : 'Clé invalide ou secrète inconnue.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    unawaited(_request.cancel('m.user', true));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: AppBarTheme(
          backgroundColor: WaPalette.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: WaPalette.primary,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: WaPalette.surface,
        appBar: AppBar(
          title: const Text('Vérification'),
          actions: [
            IconButton(icon: const Icon(Icons.close), onPressed: _cancel),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_request.state) {
      case KeyVerificationState.askSSSS:
        return _buildSsssForm();
      case KeyVerificationState.askAccept:
      case KeyVerificationState.askChoice:
        return _buildAccept();
      case KeyVerificationState.waitingAccept:
        return _buildWaiting(
          'En attente de l\'autre appareil…',
          "Assurez-vous que l'autre session est ouverte.",
        );
      case KeyVerificationState.askSas:
        return _buildSas();
      case KeyVerificationState.waitingSas:
        return _buildWaiting(
          'Comparaison des émojis…',
          "Confirmez aussi les émojis sur l'autre appareil.",
        );
      case KeyVerificationState.confirmQRScan:
      case KeyVerificationState.showQRSuccess:
        return _buildWaiting(
          'Vérification QR en cours…',
          "Suivez les instructions sur l'autre appareil.",
        );
      case KeyVerificationState.done:
        return _buildDone();
      case KeyVerificationState.error:
        return _buildError();
    }
  }

  Widget _buildSsssForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(
          icon: Icons.key_outlined,
          title: 'Clé de récupération requise',
          text:
              "Vos clés de signature sont protégées par la clé de "
              'récupération de votre compte. Saisissez-la pour continuer, '
              'ou passez cette étape (la vérification restera possible).',
        ),
        TextField(
          controller: _recoveryKeyController,
          decoration: const InputDecoration(
            labelText: 'Clé de récupération ou phrase secrète',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _openSSSS(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _openSSSS,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Déverrouiller'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => _openSSSS(skip: true),
          child: const Text('Passer cette étape'),
        ),
      ],
    );
  }

  Widget _buildAccept() {
    final who = _request.userId == _request.client.userID
        ? 'votre autre appareil'
        : _request.userId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          icon: Icons.verified_user_outlined,
          title: 'Demande de vérification',
          text: '$who demande à vérifier la sécurité de la connexion. '
              'Acceptez pour comparer les clés.',
        ),
        FilledButton(
          onPressed: _busy ? null : _accept,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Accepter'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _cancel,
          child: const Text('Refuser'),
        ),
      ],
    );
  }

  Widget _buildWaiting(String title, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(icon: Icons.hourglass_top, title: title, text: text),
        const SizedBox(height: 20),
        const Center(child: CircularProgressIndicator()),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildSas() {
    final emojis = _request.sasEmojis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(
          icon: Icons.emoji_emotions_outlined,
          title: 'Comparez les émojis',
          text: 'Ces émojis doivent être identiques sur les deux appareils. '
              'Ils prouvent que personne n\'intercepte la connexion.',
        ),
        if (emojis.isEmpty)
          const Center(child: CircularProgressIndicator())
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: emojis.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.8,
            ),
            itemBuilder: (context, index) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emojis[index].emoji,
                    style: const TextStyle(fontSize: 34)),
                const SizedBox(height: 4),
                Text(
                  emojis[index].name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: WaPalette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13),
            ),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _acceptSas,
          child: const Text('Ils correspondent'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => unawaited(_request.rejectSas()),
          child: const Text("Ils ne correspondent pas"),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          icon: Icons.verified,
          title: 'Appareil vérifié',
          text: 'Cet appareil est désormais marqué comme fiable sur votre '
              'compte. Les messages chiffrés seront lisibles.',
          iconColor: WaPalette.accent,
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Terminé'),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(
          icon: Icons.error_outline,
          title: 'Vérification annulée',
          text: 'La vérification a échoué ou a été refusée sur l\'autre '
              'appareil. Vous pouvez réessayer.',
          iconColor: Color(0xFFD33B3B),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.text,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 56, color: iconColor ?? WaPalette.primary),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: WaPalette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: WaPalette.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
