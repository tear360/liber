import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

import '../theme.dart';
import 'avatar.dart';

/// Formats a list timestamp the way WhatsApp does: time for today, weekday for
/// this week, date otherwise.
String chatListTimestamp(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final difference = today.difference(day).inDays;

  if (difference <= 0) return DateFormat.Hm().format(time);
  if (difference < 7) return DateFormat.EEEE('fr').format(time);
  if (time.year == now.year) return DateFormat('d MMM', 'fr').format(time);
  return DateFormat.yMd('fr').format(time);
}

/// One row of the chat list: avatar, title, last message, timestamp and the
/// unread pill.
class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.room,
    required this.onTap,
    required this.preview,
    required this.timestamp,
    required this.unreadCount,
    required this.showTick,
    this.subtitleOverride,
  });

  final Room room;
  final VoidCallback onTap;
  final String preview;
  final String? subtitleOverride;
  final String timestamp;
  final int unreadCount;
  final bool showTick;

  String get displayName => room.getLocalizedDisplayname();

  /// Encrypted rooms carry an `m.room.encryption` state event.
  bool get isEncrypted =>
      room.getState(EventTypes.Encryption) != null;

  @override
  Widget build(BuildContext context) {
    final unread = unreadCount > 0;
    final titleColor = WaPalette.textPrimary;

    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.only(left: 16, right: 12),
          leading: MatrixAvatar(
            name: displayName,
            avatarUri: room.avatar,
            client: room.client,
            size: 52,
          ),
          title: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
              color: titleColor,
            ),
          ),
          subtitle: Row(
            children: [
              if (showTick) ...[
                Icon(
                  Icons.check,
                  size: 16,
                  color: unread
                      ? WaPalette.accent
                      : WaPalette.textSecondary,
                ),
                const SizedBox(width: 3),
              ],
              if (subtitleOverride != null)
                Expanded(
                  child: Text(
                    subtitleOverride!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: WaPalette.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: unread
                          ? WaPalette.textPrimary
                          : WaPalette.textSecondary,
                      fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
              if (isEncrypted) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.lock,
                  size: 13,
                  color: WaPalette.textSecondary,
                ),
              ],
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timestamp,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                  color: unread ? WaPalette.accent : WaPalette.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              if (unreadCount > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: WaPalette.unreadBadge,
                    borderRadius: BorderRadius.circular(10),
                  ),                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111B21),
                    ),
                  ),
                )
              else
                const SizedBox(height: 20),
            ],
          ),
        ),
        const Divider(indent: 76),
      ],
    );
  }
}
