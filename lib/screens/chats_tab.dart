import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_service.dart';
import '../theme.dart';
import '../update/update_service.dart';
import '../widgets/chat_tile.dart';
import 'chat_screen.dart';
import 'security_screen.dart';

/// The WhatsApp conversation list, driven straight off [Client.onSync] so a
/// new message reorders the rows without a manual refresh.
///
/// [spaceOnlyRoomIds] carries the rooms that belong to a joined space: they
/// surface in Communautés only, like WhatsApp keeps community channels out of
/// the Chats list.
class ChatsTab extends StatefulWidget {
  const ChatsTab({
    super.key,
    required this.spaceOnlyRoomIds,
    this.onOpenSettings,
  });

  final Set<String> spaceOnlyRoomIds;
  final VoidCallback? onOpenSettings;

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  String _query = '';

  ReleaseInfo? _pendingUpdate;
  bool _checkingUpdate = false;
  double _downloadProgress = 0;
  bool _downloading = false;

  /// The encryption notice is dismissible: it must inform a new device, not
  /// follow the user around once they have seen it.
  bool _securityNoticeHidden = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
    unawaited(_checkForUpdate());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    try {
      final release = await UpdateService.checkForUpdate();
      if (mounted) setState(() => _pendingUpdate = release);
    } finally {
      _checkingUpdate = false;
    }
  }

  Future<void> _downloadUpdate() async {
    final release = _pendingUpdate;
    if (release == null || _downloading) return;

    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });

    try {
      final file = await UpdateService.download(
        release,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      final installed = await UpdateService.install(file);
      if (mounted) {
        setState(() => _downloading = false);
        if (!installed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                UpdateService.installError ??
                    "L'installation n'a pas pu démarrer. Réessayez.",
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mise à jour impossible : $e')),
        );
      }
    }
  }

  /// Every conversation the account can see, including invitations. Rooms that
  /// only exist inside a joined space stay out of the list.
  List<Room> _visibleRooms(Client client) {
    final rooms = List<Room>.from(client.rooms);
    rooms.retainWhere((room) {
      if (room.membership == Membership.leave) return false;
      if (room.isSpace) return false;
      if (widget.spaceOnlyRoomIds.contains(room.id)) return false;
      if (_query.isEmpty) return true;
      return room.getLocalizedDisplayname().toLowerCase().contains(_query) ||
          (room.lastEvent?.body.toLowerCase().contains(_query) ?? false);
    });

    rooms.sort((a, b) {
      final aInvite = a.membership == Membership.invite ? 0 : 1;
      final bInvite = b.membership == Membership.invite ? 0 : 1;
      if (aInvite != bInvite) return aInvite.compareTo(bInvite);
      return b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime);
    });
    return rooms;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final service = MatrixService.instance;
    final client = service.client;

    return Column(
      children: [
        if (_pendingUpdate != null) _UpdateBanner(
          release: _pendingUpdate!,
          downloading: _downloading,
          progress: _downloadProgress,
          onInstall: _downloadUpdate,
          onDismiss: () => setState(() => _pendingUpdate = null),
        ),
        // A session that has never been verified shows every encrypted room
        // as unreadable; say why and where to fix it.
        if (!_securityNoticeHidden && _needsSessionVerification(client))
          _SecurityBanner(
            onOpen: _openSecurity,
            onDismiss: () => setState(() => _securityNoticeHidden = true),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Rechercher',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
          ),
        ),
        Expanded(
          child: client == null
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<SyncUpdate>(
                  stream: client.onSync.stream,
                  builder: (context, snapshot) {
                    final rooms = _visibleRooms(client);

                    // Between login and the first completed sync the room list
                    // is still empty: show a spinner, not a wrong "no chats".
                    final waitingForFirstSync =
                        rooms.isEmpty && !snapshot.hasData;

                    if (rooms.isEmpty) {
                      return waitingForFirstSync
                          ? Center(
                              child: CircularProgressIndicator(
                                color: WaPalette.primary,
                              ),
                            )
                          : _EmptyChats(query: _query);
                    }
                    return RefreshIndicator(
                      color: WaPalette.primary,
                      onRefresh: () async {
                        await Future<void>.delayed(
                          const Duration(milliseconds: 600),
                        );
                        if (mounted) setState(() {});
                      },
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: rooms.length,
                        separatorBuilder: (_, _) => const SizedBox.shrink(),
                        itemBuilder: (context, index) {
                          final room = rooms[index];
                          return ChatTile(
                            key: ValueKey(room.id),
                            room: room,
                            timestamp: chatListTimestamp(
                              room.latestEventReceivedTime,
                            ),
                            preview: _preview(room),
                            showTick: _sentByMe(room),
                            unreadCount:
                                room.membership == Membership.invite
                                    ? 0
                                    : room.notificationCount,
                            subtitleOverride:
                                room.membership == Membership.invite
                                    ? 'Invitation reçue'
                                    : null,
                            onTap: () => _open(room),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _open(Room room) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChatScreen(room: room)),
    );
    if (mounted) setState(() {});
  }

  bool _needsSessionVerification(Client? client) =>
      client != null &&
      client.encryptionEnabled &&
      !MatrixService.instance.sessionVerified;

  Future<void> _openSecurity() async {
    await SecurityScreen.open(context);
    if (mounted) setState(() {});
  }

  /// True when the newest message in the room was sent by this account, so
  /// the row can show WhatsApp's tick.
  bool _sentByMe(Room room) {
    final event = room.lastEvent;
    if (event == null) return false;
    if (event.type != EventTypes.Message) return false;
    return event.senderId == room.client.userID;
  }

  String _preview(Room room) {
    final event = room.lastEvent;
    if (event == null) return '';
    final mine = event.senderId == room.client.userID;

    if (event.type == EventTypes.Message) {
      final prefix = mine ? 'Vous : ' : '';
      final body = _describeMessage(event.messageType, event.body);
      return '$prefix$body';
    }
    if (event.type == EventTypes.Sticker) return '${mine ? 'Vous : ' : ''}Sticker';
    if (event.type == EventTypes.Encrypted) {
      return mine ? 'Vous : Message chiffré' : 'Message chiffré';
    }
    if (event.type == EventTypes.RoomMember) {
      return event.body.isEmpty ? 'Mise à jour de membre' : event.body;
    }
    if (event.type == EventTypes.RoomName) {
      return event.body.isEmpty ? 'Nom de la salle modifié' : event.body;
    }
    if (event.type == EventTypes.RoomTopic) {
      return event.body.isEmpty ? 'Sujet modifié' : event.body;
    }
    if (event.type.startsWith('m.call')) return 'Appel';
    return event.body.isEmpty ? 'Nouveau message' : event.body;
  }

  static String _describeMessage(String msgtype, String body) {
    switch (msgtype) {
      case MessageTypes.Image:
        return '📷 Photo';
      case MessageTypes.Video:
        return '🎥 Vidéo';
      case MessageTypes.Audio:
        return '🎤 Message vocal';
      case MessageTypes.File:
        return '📎 Fichier';
      case MessageTypes.Location:
        return '📍 Position';
      default:
        return body.replaceAll('\n', ' ');
    }
  }
}

/// Sits under the update banner when this session is not verified, which is
/// what hides the encrypted history behind locks.
class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.onOpen, required this.onDismiss});

  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WaPalette.notice,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              const Icon(
                Icons.lock_outline,
                size: 20,
                color: Color(0xFFE0902B),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Messages chiffrés masqués : vérifiez cet appareil pour les '
                  'lire.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: WaPalette.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onOpen,
                child: const Text('Sécuriser'),
              ),
              IconButton(
                tooltip: 'Masquer',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.release,
    required this.downloading,
    required this.progress,
    required this.onInstall,
    required this.onDismiss,
  });

  final ReleaseInfo release;
  final bool downloading;
  final double progress;
  final VoidCallback onInstall;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE7F7F3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.system_update, color: WaPalette.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Liber ${release.version} est disponible',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: WaPalette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  downloading
                      ? LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          color: WaPalette.primary,
                          backgroundColor: const Color(0xFFCDEDE6),
                        )
                      : Text(
                          'Touchez pour télécharger et installer.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: WaPalette.textSecondary,
                          ),
                        ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!downloading)
              TextButton(
                onPressed: onInstall,
                child: const Text('Mettre à jour'),
              ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final searching = query.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.chat_bubble_outline,
              size: 56,
              color: WaPalette.accent,
            ),
            const SizedBox(height: 18),
            Text(
              searching ? 'Aucun résultat' : 'Aucune discussion',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: WaPalette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? "Aucune conversation ne correspond à « $query »."
                  : "Appuyez sur le bouton vert pour écrire à quelqu'un par "
                      'son identifiant Matrix.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WaPalette.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
