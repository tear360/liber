import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_service.dart';
import '../theme.dart';
import 'account_tab.dart';
import 'chat_screen.dart';
import 'chats_tab.dart';
import 'communities_tab.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'verification_screen.dart';

/// The main shell, laid out like WhatsApp's 2025 refresh: a light header with
/// the title and camera-style actions, then a bottom navigation bar of icons
/// with labels.
///
/// Discussions, Communautés and Compte are live Matrix views; Appels is an
/// honest empty state until call events are surfaced.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  StreamSubscription<KeyVerification>? _verificationSub;

  MatrixService get _service => MatrixService.instance;

  @override
  void initState() {
    super.initState();
    // Incoming cross-signing verification requests (e.g. "Verify this device"
    // sent by Element Web or another session) previously went unnoticed —
    // the app never showed any UI for them. Surface them now, and listen on
    // the service so the hook is installed even if the client arrives late.
    _service.addListener(_ensureVerificationListener);
    _ensureVerificationListener();
  }

  void _ensureVerificationListener() {
    final client = _service.client;
    if (client == null || _verificationSub != null) return;
    _verificationSub = client.onKeyVerificationRequest.stream
        .listen(_onIncomingVerification);
  }

  void _onIncomingVerification(KeyVerification request) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vérification demandée'),
        content: Text(
          request.userId == request.client.userID
              ? 'Une autre session de votre compte demande à vérifier cet '
                  'appareil.'
              : '${request.userId} demande à vérifier la sécurité de la '
                  'connexion.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              unawaited(request.cancel('m.user', true));
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Refuser'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(VerificationScreen.open(context, request));
            },
            child: const Text('Vérifier'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _service.removeListener(_ensureVerificationListener);
    unawaited(_verificationSub?.cancel());
    super.dispose();
  }

  /// Unjoined rooms that belong to at least one space: they surface only in
  /// Communautés, like WhatsApp keeps community channels out of Chats.
  Set<String> _spaceRoomIds(Client? client) {
    if (client == null) return const {};
    final ids = <String>{};
    for (final space in client.rooms) {
      if (!space.isSpace || space.membership == Membership.leave) continue;
      for (final child in space.spaceChildren) {
        final roomId = child.roomId;
        if (roomId != null) ids.add(roomId);
      }
    }
    return ids;
  }

  Future<void> _newDiscussion() async {
    final client = _service.client;
    if (client == null) return;

    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle discussion'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: '@alice:example.org',
            labelText: 'Identifiant Matrix',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );

    if (entered == null || entered.isEmpty) return;
    if (!entered.startsWith('@')) {
      _snack('Un identifiant Matrix commence par @ (ex. @alice:example.org).');
      return;
    }

    try {
      final roomId = await client.startDirectChat(entered);
      final room = client.getRoomById(roomId);
      if (room != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ChatScreen(room: room)),
        );
      }
    } catch (e) {
      _snack(MatrixService.describeMatrixError(e));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Les messages reçus restent sur le serveur, mais les données chiffrées '
          'de cet appareil seront effacées.',
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
    if (confirmed != true) return;

    await _service.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = _service.client;

    return Scaffold(
      backgroundColor: WaPalette.surface,
      appBar: AppBar(
        title: Text(
          const ['Liber', 'Communautés', 'Appels', 'Compte'][_tab],
        ),
        actions: [
          if (_tab == 0) ...[
            IconButton(
              icon: const Icon(Icons.photo_camera_outlined),
              tooltip: 'Caméra',
              onPressed: () => _snack(
                "La caméra arrive dans une prochaine version.",
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'new':
                    _newDiscussion();
                  case 'settings':
                    _openSettings();
                  case 'logout':
                    _confirmLogout();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'new', child: Text('Nouvelle discussion')),
                PopupMenuItem(value: 'settings', child: Text('Paramètres')),
                PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
              ],
            ),
          ] else
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'settings':
                    _openSettings();
                  case 'logout':
                    _confirmLogout();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'settings', child: Text('Paramètres')),
                PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
              ],
            ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: _newDiscussion,
              tooltip: 'Nouvelle discussion',
              child: const Icon(Icons.chat, size: 26),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        backgroundColor: WaPalette.surface,
        indicatorColor: Colors.transparent,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            icon: ListenableBuilder(
              listenable: _service,
              builder: (context, _) {
                final unread = _totalUnreadChats(client);
                return Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.chat_bubble_outline),
                );
              },
            ),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: 'Discussions',
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            selectedIcon: const Icon(Icons.groups),
            label: 'Communautés',
          ),
          NavigationDestination(
            icon: const Icon(Icons.call_outlined),
            selectedIcon: const Icon(Icons.call),
            label: 'Appels',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: 'Compte',
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          ChatsTab(spaceOnlyRoomIds: _spaceRoomIds(client)),
          const CommunitiesTab(),
          const _CallsTab(),
          const AccountTab(),
        ],
      ),
    );
  }

  /// WhatsApp's Chats tab badge: rooms with unread messages or invites,
  /// excluding space-only rooms and spaces themselves.
  int _totalUnreadChats(Client? client) {
    if (client == null) return 0;
    final spaceOnly = _spaceRoomIds(client);
    return client.rooms
        .where((room) =>
            room.membership != Membership.leave &&
            !room.isSpace &&
            !spaceOnly.contains(room.id) &&
            room.isUnreadOrInvited)
        .length;
  }
}

class _CallsTab extends StatelessWidget {
  const _CallsTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: Color(0xFFE7F7F3),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.call_outlined,
              size: 44,
              color: WaPalette.accent,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Aucun appel',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WaPalette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Les appels Matrix apparaîtront ici. Liber couvre pour l'instant "
              'la messagerie textuelle et les espaces.',
              textAlign: TextAlign.center,
              style: TextStyle(color: WaPalette.textSecondary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
