import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'verification_screen.dart';

/// The Compte tab: avatar, profile fields, device/session details and
/// encryption status — everything identifying this account at a glance.
class AccountTab extends StatefulWidget {
  const AccountTab({super.key});

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  final _service = MatrixService.instance;

  Profile? _profile;
  String? _profileError;
  bool _editingName = false;
  bool _savingName = false;
  final _nameController = TextEditingController();

  Client? get _client => _service.client;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final client = _client;
    if (client == null || client.userID == null) return;
    setState(() {
      _profileError = null;
    });
    try {
      final profile = await client.fetchOwnProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (e) {
      if (mounted) {
        setState(() => _profileError = MatrixService.describeMatrixError(e));
      }
    }
  }

  Future<void> _saveName() async {
    final client = _client;
    final userId = client?.userID;
    if (client == null || userId == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty || _savingName) return;

    setState(() => _savingName = true);
    try {
      await client.setProfileField(userId, 'displayname', {
        'displayname': name,
      });
      if (!mounted) return;
      setState(() {
        _editingName = false;
        _profile = null;
      });
      unawaited(_loadProfile());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(MatrixService.describeMatrixError(e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  void _startEditName() {
    final current = _profile?.displayName ?? _service.userId ?? '';
    _nameController.text = current;
    setState(() => _editingName = true);
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final client = service.client;
    final userId = service.userId ?? '';
    final displayName = _profile?.displayName;
    final avatarUri = _profile?.avatarUrl;

    if (!service.isLoggedIn) {
      return const Center(
        child: Text(
          'Non connecté',
          style: TextStyle(color: WaPalette.textSecondary, fontSize: 15),
        ),
      );
    }

    return ListView(
      children: [
        const SizedBox(height: 8),
        // ---- Identity card -------------------------------------------
        Material(
          color: WaPalette.surface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                MatrixAvatar(
                  name: displayName?.isNotEmpty == true
                      ? displayName!
                      : (userId.isNotEmpty ? userId : 'L'),
                  avatarUri: avatarUri,
                  client: client,
                  size: 72,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_editingName)
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _nameController,
                                autofocus: true,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  labelText: 'Nom affiché',
                                ),
                                onSubmitted: (_) => _saveName(),
                              ),
                            ),
                            IconButton(
                              onPressed:
                                  _savingName ? null : _saveName,
                              icon: _savingName
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check),
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName?.isNotEmpty == true
                                    ? displayName!
                                    : 'Aucun nom défini',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  color: WaPalette.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Modifier le nom',
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: _startEditName,
                            ),
                          ],
                        ),
                      const SizedBox(height: 2),
                      Text(
                        userId,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: WaPalette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_profileError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Profil : $_profileError',
              style: const TextStyle(
                color: Color(0xFFB3261E),
                fontSize: 12.5,
              ),
            ),
          ),
        const SizedBox(height: 8),

        _Section(
          title: 'Appareil',
          children: [
            _InfoTile(
              icon: Icons.dns_outlined,
              title: 'Serveur Matrix',
              subtitle: service.homeserverUrl ?? '—',
            ),
            const Divider(indent: 56),
            _InfoTile(
              icon: Icons.phone_android,
              title: 'Cet appareil',
              subtitle: 'Liber (Android) · ${client?.deviceID ?? 'inconnu'}',
            ),
          ],
        ),
        const SizedBox(height: 12),

        _Section(
          title: 'Sécurité',
          children: [
            _InfoTile(
              icon: Icons.lock_outline,
              title: 'Chiffrement de bout en bout',
              subtitle: !service.e2eeReady
                  ? 'Bibliothèque crypto indisponible — les salons chiffrés '
                      'sont illisibles.'
                  : service.encryptionEnabled
                      ? 'Actif sur cet appareil'
                      : 'Disponible, activé dès qu’un salon chiffré est ouvert',
              trailing: Icon(
                service.e2eeReady ? Icons.check_circle : Icons.warning_amber,
                color: service.e2eeReady
                    ? WaPalette.accent
                    : const Color(0xFFE0902B),
              ),
            ),
            const Divider(indent: 56),
            _VerificationTile(),
          ],
        ),
        const SizedBox(height: 12),

        _Section(
          title: 'Statistiques',
          children: [
            ListenableBuilder(
              listenable: service,
              builder: (context, _) {
                final rooms = client?.rooms ?? const <Room>[];
                final chats = rooms
                    .where((r) =>
                        r.membership != Membership.leave && !r.isSpace)
                    .length;
                final spaces = rooms
                    .where((r) =>
                        r.isSpace && r.membership != Membership.leave)
                    .length;
                return Column(
                  children: [
                    _InfoTile(
                      icon: Icons.forum_outlined,
                      title: 'Discussions',
                      subtitle:
                          '$chats salon${chats > 1 ? 's' : ''} · $spaces '
                          'communauté${spaces > 1 ? 's' : ''}',
                    ),
                    const Divider(indent: 56),
                    _InfoTile(
                      icon: Icons.badge_outlined,
                      title: 'Identifiant complet',
                      subtitle: userId.isEmpty ? '—' : userId,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _VerificationTile extends StatefulWidget {
  @override
  State<_VerificationTile> createState() => _VerificationTileState();
}

class _VerificationTileState extends State<_VerificationTile> {
  bool _busy = false;

  /// Cross-signing is usable only when both the crypto stack and the
  /// account's cross-signing keys are in place; otherwise the tile hides.
  bool _verificationAvailable(Client client) {
    final encryption = client.encryption;
    if (encryption == null || client.userID == null) return false;
    final keyList = client.userDeviceKeys[client.userID!];
    return keyList != null;
  }

  Future<void> _startSelfVerification() async {
    final client = MatrixService.instance.client;
    if (client == null || _busy) return;

    setState(() => _busy = true);
    KeyVerification? request;
    try {
      final keyList = client.userDeviceKeys[client.userID!];
      if (keyList == null) throw Exception('Clés du compte indisponibles.');
      request = await keyList.startVerification();
      request.onUpdate = () {};
      if (!mounted) return;
      await VerificationScreen.open(context, request);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Vérification impossible : '
              '${MatrixService.describeMatrixError(e)}',
            ),
          ),
        );
      }
      try {
        await request?.cancel('m.user', true);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = MatrixService.instance.client;
    if (client == null || !_verificationAvailable(client)) {
      return const SizedBox.shrink();
    }
    final verified =
        client.userDeviceKeys[client.userID!]?.verified ==
        UserVerifiedStatus.verified;

    return _InfoTile(
      icon: verified ? Icons.verified : Icons.gpp_maybe_outlined,
      title: 'Vérifier cet appareil',
      subtitle: verified
          ? 'Cet appareil est vérifié. Vous pouvez revérifier à tout moment.'
          : 'Confirmez que cet appareil est bien le vôtre pour débloquer les '
              'messages chiffrés.',
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              Icons.chevron_right,
              color: verified ? WaPalette.accent : const Color(0xFFE0902B),
            ),
      onTap: _busy ? null : _startSelfVerification,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              title!.toUpperCase(),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: WaPalette.accent,
                letterSpacing: 0.5,
              ),
            ),
          ),
        Material(
          color: WaPalette.surface,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          color: WaPalette.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13.5, color: WaPalette.textSecondary),
      ),
      trailing: trailing,
    );
  }
}
