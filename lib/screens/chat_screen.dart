import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/message_bubble.dart';

/// The conversation screen: WhatsApp's wallpaper, message run grouping,
/// day separators and the composer with its morphing send button.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.room});

  final Room room;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _composerController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  Timeline? _timeline;
  bool _sending = false;
  bool _loadingMore = false;

  Room get room => widget.room;

  @override
  void initState() {
    super.initState();
    _composerController.addListener(() => setState(() {}));
    unawaited(_openTimeline());
  }

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _openTimeline() async {
    try {
      final timeline = await room.getTimeline(
        onNewEvent: () => _refresh(),
        onUpdate: () => _refresh(),
        onChange: (_) => _refresh(),
        onInsert: (_) => _refresh(),
        onRemove: (_) => _refresh(),
      );
      if (!mounted) return;
      setState(() => _timeline = timeline);
      unawaited(_markRead());
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _markRead() async {
    final id = room.lastEvent?.eventId;
    if (id == null) return;
    await room.setReadMarker(id, mRead: id);
  }

  void _refresh() {
    if (mounted) setState(() {});
    unawaited(_markRead());
  }

  Future<void> _loadOlder() async {
    final timeline = _timeline;
    if (timeline == null || _loadingMore) return;
    if (!timeline.canRequestHistory) return;
    _loadingMore = true;
    try {
      await timeline.requestHistory();
    } finally {
      _loadingMore = false;
    }
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _sending) return;

    _composerController.clear();
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);

    try {
      await room.sendTextEvent(
        text,
        parseMarkdown: false,
        parseCommands: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message non envoyé : $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          room.isDirectChat ? 'Quitter la discussion' : 'Quitter le salon',
        ),
        content: Text(
          room.isDirectChat
              ? 'La conversation restera sur le serveur.'
              : 'Vous ne recevrez plus les messages de ce salon.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await room.leave();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = room.getLocalizedDisplayname();
    final client = room.client;
    final isGroup = !room.isDirectChat;
    final participants = room.getParticipants();

    return Scaffold(
      backgroundColor: WaPalette.wallpaper,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pop(),
            ),
            MatrixAvatar(
              name: title,
              avatarUri: room.avatar,
              client: client,
              size: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    isGroup
                        ? '${participants.length} participants'
                        : (room.typingUsers.isNotEmpty
                            ? 'en train d\'écrire…'
                            : (room.directChatMatrixID ?? client.userID ?? '')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFD6EFE8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Appel',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Les appels ne sont pas encore pris en charge."),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'leave') _leave();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'info',
                child: Text(
                  isGroup ? 'Informations du salon' : 'Informations de contact',
                ),
              ),
              const PopupMenuItem(value: 'leave', child: Text('Quitter')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final timeline = _timeline;
    if (timeline == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final children = _renderMessages(timeline.events);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels <= 40 && !_loadingMore) {
          unawaited(_loadOlder());
        }
        return false;
      },
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: children.isEmpty
            ? [
                const SizedBox(height: 160),
                const Center(
                  child: Text(
                    'Aucun message pour le moment.',
                    style: TextStyle(color: WaPalette.textSecondary),
                  ),
                ),
              ]
            : children,
      ),
    );
  }

  List<Widget> _renderMessages(List<Event> events) {
    final widgets = <Widget>[];
    final ownId = room.client.userID;
    DateTime? lastDay;
    Event? previous;

    for (final event in events) {
      final kind = _classify(event);
      if (kind == _EventKind.hidden) {
        continue;
      }

      final ts = event.originServerTs;
      final day = DateTime(ts.year, ts.month, ts.day);
      if (lastDay == null || day != lastDay) {
        widgets.add(DaySeparator(label: _dayLabel(day)));
        previous = null;
      }
      lastDay = day;

      if (kind == _EventKind.system) {
        final text = _systemText(event);
        if (text.isNotEmpty) {
          widgets.add(
            MessageBubble(
              body: text,
              isMine: false,
              timestamp: ts,
              isSystem: true,
            ),
          );
        }
        previous = null;
        continue;
      }

      final isMine = event.senderId == ownId;
      final gap = previous == null
          ? const Duration(days: 1)
          : ts.difference(previous.originServerTs);
      final startsRun =
          previous == null ||
          previous.senderId != event.senderId ||
          gap > const Duration(minutes: 5);

      final group =
          !room.isDirectChat && startsRun && !isMine && events.length > 1;

      widgets.add(
        MessageBubble(
          body: _bubbleBody(event),
          isMine: isMine,
          timestamp: ts,
          showTail: startsRun,
          senderName: group
              ? event.senderFromMemoryOrFallback.displayName ?? event.senderId
              : null,
          senderColor: _senderColor(event.senderId),
          status: event.status,
          failed: event.status == EventStatus.error,
        ),
      );
      previous = event;
    }

    return widgets;
  }

  static _EventKind _classify(Event event) {
    switch (event.type) {
      case EventTypes.Message:
      case EventTypes.Sticker:
      case EventTypes.Encrypted:
        return _EventKind.message;
      case EventTypes.RoomMember:
      case EventTypes.RoomName:
      case EventTypes.RoomTopic:
      case EventTypes.RoomCreate:
      case EventTypes.Encryption:
      case EventTypes.Redaction:
        return _EventKind.system;
      default:
        return _EventKind.hidden;
    }
  }

  String _bubbleBody(Event event) {
    if (event.type == EventTypes.Encrypted) {
      return event.body.isEmpty ? 'Message chiffré illisible' : event.body;
    }
    if (event.type == EventTypes.Sticker) return 'Sticker';
    switch (event.messageType) {
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
        return event.body;
    }
  }

  static String _systemText(Event event) {
    switch (event.type) {
      case EventTypes.RoomMember:
        if (event.body.isNotEmpty) return event.body;
        final membership = event.content['membership'];
        final who = event.stateKey ?? '';
        if (membership == 'join') return '$who a rejoint.';
        if (membership == 'leave') return '$who a quitté.';
        if (membership == 'invite') return '$who a été invité.';
        if (membership == 'ban') return '$who a été banni.';
        return '';
      case EventTypes.RoomName:
        return event.body.isNotEmpty
            ? 'Nom du salon : ${event.body}'
            : 'Nom du salon modifié.';
      case EventTypes.RoomTopic:
        return event.body.isNotEmpty
            ? 'Sujet : ${event.body}'
            : 'Sujet modifié.';
      case EventTypes.Encryption:
        return 'Le chiffrement de bout en bout a été activé.';
      case EventTypes.RoomCreate:
        return 'Salon créé.';
      case EventTypes.Redaction:
        return 'Message supprimé.';
      default:
        return '';
    }
  }

  static String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return "AUJOURD'HUI";
    if (diff == 1) return 'HIER';
    if (diff < 7) return DateFormat.EEEE('fr').format(day).toUpperCase();
    if (day.year == now.year) {
      return DateFormat('d MMMM', 'fr').format(day).toUpperCase();
    }
    return DateFormat.yMMMMd('fr').format(day).toUpperCase();
  }

  /// Stable per-sender hue so group members are easy to tell apart.
  static Color _senderColor(String userId) {
    var hash = 0;
    for (var i = 0; i < userId.length; i++) {
      hash = (hash * 31 + userId.codeUnitAt(i)) & 0x7fffffff;
    }
    return WaPalette.avatarPalette[hash % WaPalette.avatarPalette.length];
  }

  Widget _buildComposer() {
    final hasText = _composerController.text.trim().isNotEmpty;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        color: WaPalette.wallpaper,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: WaPalette.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.emoji_emotions_outlined,
                        color: WaPalette.textSecondary,
                      ),
                      onPressed: () {},
                    ),
                    Expanded(
                      child: TextField(
                        controller: _composerController,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.attach_file,
                        color: WaPalette.textSecondary,
                      ),
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                        const SnackBar(
                          content: Text(
                            "L'envoi de fichiers arrive dans une prochaine version.",
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 46,
              height: 46,
              child: Material(
                color: hasText ? WaPalette.accent : Colors.transparent,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: Icon(
                    hasText ? Icons.send : Icons.mic,
                    color: hasText ? Colors.white : WaPalette.textSecondary,
                    size: 22,
                  ),
                  onPressed: hasText
                      ? _send
                      : () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Les messages vocaux arrivent prochainement.",
                              ),
                            ),
                          ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _EventKind { message, system, hidden }
