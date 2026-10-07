import 'dart:async';

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

  Future<void> _openSpace(BuildContext context, Room space) async {
    final client = space.client;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SpaceRoomsScreen(space: space, client: client),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = MatrixService.instance.client;

    return StreamBuilder<SyncUpdate>(
      stream: client?.onSync.stream,
      builder: (context, snapshot) {
        final spaces = _spaces(client);
        if (spaces.isEmpty) {
          return const Center(
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
                style: const TextStyle(
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
}

/// Shows the rooms belonging to one space; tapping one opens the chat.
class _SpaceRoomsScreen extends StatelessWidget {
  const _SpaceRoomsScreen({required this.space, required this.client});

  final Room space;
  final Client client;

  List<Room> get _children {
    final result = <Room>[];
    final childStates = space.states['m.space.child'];
    if (childStates != null) {
      for (final entry in childStates.entries) {
        final roomId = entry.value.stateKey;
        if (roomId == null) continue;
        final room = client.getRoomById(roomId);
        if (room != null && room.membership != Membership.leave) {
          result.add(room);
        }
      }
    }
    result.sort(
      (a, b) => b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    final name = space.getLocalizedDisplayname();

    return Scaffold(
      backgroundColor: WaPalette.surface,
      appBar: AppBar(title: Text(name)),
      body: children.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  "Aucun salon accessible dans cet espace.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: WaPalette.textSecondary, fontSize: 15),
                ),
              ),
            )
          : ListView.separated(
              itemCount: children.length,
              separatorBuilder: (_, _) => const Divider(indent: 76),
              itemBuilder: (context, index) {
                final room = children[index];
                final roomName = room.getLocalizedDisplayname();
                final unread = room.notificationCount;
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
                  trailing: unread > 0
                      ? Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
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
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatScreen(room: room),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
