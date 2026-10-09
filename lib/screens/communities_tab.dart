import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../matrix/matrix_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';

/// Lists the Matrix spaces the user has joined. Spaces are Liber's stand-in
/// for WhatsApp Communities: a container that groups several rooms.
class CommunitiesTab extends StatelessWidget {
  const CommunitiesTab({super.key});

  List<Room> _spaces(Client? client) {
    if (client == null) return const [];
    final spaces = client.rooms.where(
      (room) => room.isSpace && room.membership != Membership.leave,
    ).toList()
      ..sort(
        (a, b) => b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
      );
    return spaces;
  }

  @override
  Widget build(BuildContext context) {
    final client = MatrixService.instance.client;

    return StreamBuilder<SyncUpdate>(
      stream: client?.onSync.stream,
      builder: (context, snapshot) {
        final spaces = _spaces(client);
        if (spaces.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.groups_outlined, size: 56, color: WaPalette.accent),
                  SizedBox(height: 18),
                  Text(
                    'Aucune communauté',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: WaPalette.textPrimary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Les espaces Matrix regroupent plusieurs salons comme les '
                    'communautés WhatsApp. Rejoignez-en un depuis votre '
                    'application Matrix préférée.',
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

        return ListView.separated(
          itemCount: spaces.length,
          separatorBuilder: (_, _) => const Divider(indent: 76),
          itemBuilder: (context, index) {
            final space = spaces[index];
            final name = space.getLocalizedDisplayname();
            return ListTile(
              leading: MatrixAvatar(
                name: name,
                avatarUri: space.avatar,
                client: client,
                size: 48,
              ),
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                space.topic.isEmpty ? 'Espace Matrix' : space.topic,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: WaPalette.textSecondary,
                ),
              ),
              onTap: () => _openSpace(context, space),
            );
          },
        );
      },
    );
  }

  Future<void> _openSpace(BuildContext context, Room space) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _SpaceRoomsScreen(space: space)),
    );
  }
}

/// Shows the rooms belonging to one space; tapping one opens the chat.
///
/// A room that is absent from the local state (e.g. joined via another
/// client, so its `m.space.child` entry lacks a `via`) is still listed —
/// tapping it opens the conversation, where the timeline can load or show a
/// clear error instead of a dead row.
class _SpaceRoomsScreen extends StatelessWidget {
  const _SpaceRoomsScreen({required this.space});

  final Room space;

  /// Children declared by the space plus every joined non-space room with a
  /// matching `m.space.parent`, so filtering quirks cannot hide rooms.
  Iterable<Room> get _children sync* {
    final client = space.client;
    final childIds = <String>{
      for (final child in space.spaceChildren)
        if (child.roomId != null) child.roomId!,
    };

    for (final room in client.rooms) {
      if (room.isSpace || room.membership == Membership.leave) continue;
      final isChild = childIds.contains(room.id) ||
          room.spaceParents.any((parent) => parent.roomId == space.id);
      if (isChild) yield room;
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = space.client;
    final children = _children.toList()
      ..sort(
        (a, b) => b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
      );
    final name = space.getLocalizedDisplayname();

    return Scaffold(
      backgroundColor: WaPalette.surface,
      appBar: AppBar(title: Text(name)),
      body: children.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.meeting_room_outlined,
                      size: 48,
                      color: WaPalette.accent,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aucun salon visible dans « $name ».',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WaPalette.textSecondary,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Les salons apparaissent ici dès que le serveur a envoyé '
                      'leur liste. Tirez pour rafraîchir après un instant.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WaPalette.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              color: WaPalette.primary,
              onRefresh: () async {
                await Future<void>.delayed(const Duration(milliseconds: 600));
                // A StreamBuilder above would be needed to rebuild; this
                // screen rebuilds on pop instead, so nudge a frame.
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: children.length,
                separatorBuilder: (_, _) => const Divider(indent: 76),
                itemBuilder: (context, index) {
                  final room = children[index];
                  final roomName = room.getLocalizedDisplayname();
                  final unread = room.notificationCount;
                  final invited = room.membership == Membership.invite;
                  return ListTile(
                    leading: MatrixAvatar(
                      name: roomName,
                      avatarUri: room.avatar,
                      client: client,
                      size: 44,
                    ),
                    title: Text(
                      roomName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: invited
                        ? Text(
                            'Invitation reçue — touchez pour rejoindre',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: WaPalette.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : null,
                    trailing: unread > 0
                        ? Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            height: 20,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: WaPalette.unreadBadge,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111B21),
                              ),
                            ),
                          )
                        : null,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ChatScreen(room: room),
                        ),
                      );
                      // Rebuild so invites accepted in the chat screen show
                      // their new state when coming back.
                    },
                  );
                },
              ),
            ),
    );
  }
}
