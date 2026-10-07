import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../matrix/matrix_service.dart';
import '../theme.dart';
import '../update/update_service.dart';
import '../widgets/avatar.dart';
import 'login_screen.dart';

/// Profile, encryption status, the update checker and sign-out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _service = MatrixService.instance;

  PackageInfo? _packageInfo;
  ReleaseInfo? _available;
  bool _busy = false;
  bool _downloading = false;
  double _progress = 0;
  String? _status;
  bool _autoUpdate = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _packageInfo = info;
      _autoUpdate = prefs.getBool('auto_update') ?? true;
    });
  }

  Future<void> _toggleAutoUpdate(bool value) async {
    setState(() => _autoUpdate = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_update', value);
  }

  Future<void> _check({bool force = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
      _available = null;
    });
    try {
      final release = await UpdateService.checkForUpdate(force: force);
      if (!mounted) return;
      setState(() => _available = release);
      if (release == null) {
        _setStatus('Vous êtes à jour.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String message) {
    if (mounted) setState(() => _status = message);
  }

  Future<void> _install() async {
    final release = _available;
    if (release == null || _downloading) return;

    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Téléchargement…';
    });

    try {
      final file = await UpdateService.download(
        release,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      final ok = await UpdateService.install(file);
      _setStatus(
        ok
            ? 'Installez la mise à jour proposée par Android.'
            : 'Téléchargé dans ${file.path}. Autorisez les installations de '
                'sources inconnues pour installer.',
      );
    } catch (e) {
      _setStatus('Échec : $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Les messages chiffrés de cet appareil seront effacés de façon '
          'irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _service.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final client = service.client;
    final userId = service.userId ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        children: [
          // ---- Profile -------------------------------------------------
          Material(
            color: WaPalette.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  MatrixAvatar(
                    name: userId.isNotEmpty ? userId : 'L',
                    avatarUri: null,
                    client: client,
                    size: 72,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userId.isEmpty ? 'Non connecté' : userId,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: WaPalette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
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
            ],
          ),
          const SizedBox(height: 12),

          _Section(
            title: 'Mises à jour',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.autorenew),
                title: const Text('Vérifier automatiquement'),
                subtitle: const Text(
                  'Interroge GitHub Releases toutes les 6 heures.',
                ),
                value: _autoUpdate,
                onChanged: _toggleAutoUpdate,
              ),
              const Divider(indent: 56),
              _InfoTile(
                icon: Icons.system_update_outlined,
                title: 'Version installée',
                subtitle: _packageInfo == null
                    ? '…'
                    : 'Liber ${_packageInfo!.version} '
                        '(build ${_packageInfo!.buildNumber})',
              ),
              if (_available != null) ...[
                const Divider(indent: 56),
                _InfoTile(
                  icon: Icons.new_releases_outlined,
                  title: 'Nouvelle version : ${_available!.version}',
                  subtitle: _available!.name ?? 'Disponible sur GitHub',
                  color: WaPalette.accent,
                ),
              ],
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Rechercher une mise à jour'),
                subtitle: _busy
                    ? const Text('Vérification en cours…')
                    : Text(_status ?? 'Touchez pour interroger GitHub.'),
                trailing: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _busy ? null : () => _check(force: true),
              ),
              if (_available != null && _available!.hasApk) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: FilledButton.icon(
                    onPressed: _downloading ? null : _install,
                    icon: _downloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download),
                    label: Text(_downloading
                        ? '${(_progress * 100).toStringAsFixed(0)} %'
                        : 'Télécharger et installer'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          _Section(
            title: 'À propos',
            children: [
              _InfoTile(
                icon: Icons.info_outline,
                title: 'Liber',
                subtitle: 'Client Matrix libre, interface inspirée de WhatsApp.',
              ),
              const Divider(indent: 56),
              _InfoTile(
                icon: Icons.dns_outlined,
                title: 'Serveur Matrix',
                subtitle: service.homeserverUrl ?? '—',
              ),
            ],
          ),
          const SizedBox(height: 12),

          _Section(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.logout,
                  color: Color(0xFFD33B3B),
                ),
                title: const Text(
                  'Se déconnecter',
                  style: TextStyle(color: Color(0xFFD33B3B)),
                ),
                onTap: _logout,
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
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
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? WaPalette.iconMuted),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: color ?? WaPalette.textPrimary,
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
