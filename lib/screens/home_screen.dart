import 'package:flutter/material.dart';

import '../matrix/matrix_service.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'communities_tab.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'chats_tab.dart';

/// The main shell: a green app bar with the WhatsApp tab strip underneath.
///
/// Discussions and Communautés are live Matrix views; Appels is an honest
/// empty state until call events are surfaced.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _newDiscussion() async {
    final service = MatrixService.instance;
    final client = service.client;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WaPalette.surface,
      appBar: AppBar(
        title: const Text('Liber'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Rechercher',
            onPressed: () => _snack('Recherche : utilisez la barre des discussions.'),
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
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Discussions'),
            Tab(text: 'Communautés'),
            Tab(text: 'Appels'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: _newDiscussion,
              tooltip: 'Nouvelle discussion',
              child: const Icon(Icons.chat, size: 26),
            )
          : null,
      body: Listener(
        onPointerDown: (_) => setState(() {}),
        child: TabBarView(
          controller: _tabController,
          children: [
            ChatsTab(onOpenSettings: _openSettings),
            const CommunitiesTab(),
            const _CallsTab(),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final service = MatrixService.instance;
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

    await service.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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
            child: const Icon(
              Icons.call_outlined,
              size: 44,
              color: WaPalette.accent,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Aucun appel',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: WaPalette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
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
