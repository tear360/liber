import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

import '../theme.dart';

/// Draws the small pointed flap WhatsApp puts on the first bubble of a group.
class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color, required this.isMine});

  final Color color;
  final bool isMine;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isMine) {
      // Flap sits on the top right, pointing away from the bubble.
      path
        ..moveTo(size.width, 0)
        ..lineTo(0, 0)
        ..lineTo(size.width, size.height)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height)
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isMine != isMine;
}

/// A single message. Green on the right for the caller, white on the left for
/// everyone else, with the timestamp tucked into the bottom corner.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.body,
    required this.isMine,
    required this.timestamp,
    this.senderName,
    this.senderColor,
    this.showTail = true,
    this.status,
    this.isSystem = false,
    this.failed = false,
  });

  final String body;
  final bool isMine;
  final DateTime timestamp;

  /// Only set for messages from someone else in a group conversation.
  final String? senderName;
  final Color? senderColor;

  /// WhatsApp draws its flap on the first bubble of a consecutive run.
  final bool showTail;
  final EventStatus? status;

  /// System notices (joins, name changes) render as a centred pill.
  final bool isSystem;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    if (isSystem) return _buildSystemNotice();

    final color = isMine ? WaPalette.outgoingBubble : WaPalette.incomingBubble;
    const radius = Radius.circular(8);

    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 8, 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: radius,
          topRight: radius,
          bottomLeft: radius,
          bottomRight: radius,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 1, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (senderName != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                senderName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: senderColor ?? WaPalette.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 2),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: SelectableText(
                  body,
                  style: const TextStyle(
                    color: WaPalette.textPrimary,
                    fontSize: 15.4,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (failed)
                    const Icon(Icons.error_outline,
                        size: 14, color: Color(0xFFD33B3B))
                  else if (isMine && status != null)
                    _StatusIcon(status: status!),
                  const SizedBox(width: 3),
                  Text(
                    DateFormat.Hm().format(timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: failed
                          ? const Color(0xFFD33B3B)
                          : WaPalette.incomingTimestamp,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        bottom: 2,
        left: isMine ? 64 : 4,
        right: isMine ? 4 : 64,
      ),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: showTail
                ? Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 0,
                        right: isMine ? -7 : null,
                        left: isMine ? null : -7,
                        child: CustomPaint(
                          size: const Size(8, 11),
                          painter: _BubbleTailPainter(
                            color: color,
                            isMine: isMine,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          left: isMine ? 0 : 7,
                          right: isMine ? 7 : 0,
                        ),
                        child: bubble,
                      ),
                    ],
                  )
                : bubble,
          ),
        ],
      ),
    );
  }

  Widget _buildSystemNotice() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F1D9),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 1, offset: Offset(0, 1)),
          ],
        ),
        child: Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: WaPalette.textSecondary,
            fontSize: 12.8,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final EventStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case EventStatus.error:
        return const Icon(Icons.error_outline, size: 14, color: Color(0xFFD33B3B));
      case EventStatus.sending:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.4),
        );
      case EventStatus.sent:
        // One tick: left the device, not yet confirmed by the server.
        return const Icon(Icons.check, size: 14, color: WaPalette.textSecondary);
      case EventStatus.synced:
        // Double tick: everybody in the room received it.
        return const Icon(Icons.done_all, size: 14, color: Color(0xFF53BDEB));
    }
  }
}

/// WhatsApp puts the date in a grey pill between message runs.
class DaySeparator extends StatelessWidget {
  const DaySeparator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFE1F3FB),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: WaPalette.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
