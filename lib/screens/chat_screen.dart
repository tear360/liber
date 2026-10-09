import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart';

import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/message_bubble.dart';
import 'security_screen.dart';

/// The conversation screen: green header, WhatsApp's beige wallpaper, message
/// run grouping, day separators and the composer with its send button.
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
  String? _error;
  bool _sending = false;
  bool _joining = false;
  bool _loadingMore = false;

  Room get room => widget.room;

  @override
  void initState() {
    super.initState();
    _composerController.addListener(() => setState(() {}));
    _openTimeline();
  }

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _openTimeline() async {
    setState(() {
      _error = null;
      _timeline = null;
    });

    try {
      // An invitation must be accepted before the server serves any event;
      // without this the screen stays empty forever.
      if (room.membership == Membership.invite) {
        setState(() => _joining = true);
        try {
          await room.join();
        } finally {
          if (mounted) setState(() => _joining = false);
        }
      }

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
      setState(() => _error = e.toString());
    }
  }

  Future<void> _markRead() async {
    final id = room.lastEvent?.eventId;
    if (id == null) return;
    try {
      await room.setReadMarker(id, mRead: id);
    } catch (_) {
      // Best effort: a failed receipt must not disturb the conversation.
    }
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
      if (mounted) setState(() {});
    } catch (_) {
      // Keep the conversation usable if pagination hiccups.
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

    // The conversation screen keeps WhatsApp's green header; only the main
    // tabs moved to the light 2025 header.
    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: const AppBarTheme(
          backgroundColor: WaPalette.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: WaPalette.primary,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
        ),
      ),
      child: Scaffold(
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
                              : (room.directChatMatrixID ??
                                  client.userID ??
                                  '')),
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
                  content:
                      Text("Les appels ne sont pas encore pris en charge."),
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
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return _ChatIssue(
        message: _error!,
        canRetry: room.membership != Membership.ban,
        onRetry: _openTimeline,
      );
    }
    if (_joining) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: WaPalette.primary),
            SizedBox(height: 14),
            Text(
              'Acceptation de l\'invitation…',
              style: TextStyle(color: WaPalette.textSecondary),
            ),
          ],
        ),
      );
    }

    final timeline = _timeline;
    if (timeline == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final children = _renderMessages(timeline.events);
    final locked = _hasUndecryptableEvents(timeline.events);

    return Column(
      children: [
        // A new session gets no room keys until it is trusted: say so instead
        // of letting the locks look like a broken app.
        if (locked)
          _LockedBanner(onUnlock: _unlockMessages, onRetry: _retryKeys),
        Expanded(
          child: NotificationListener<ScrollNotification>(
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
          ),
        ),
      ],
    );
  }

  static bool _hasUndecryptableEvents(List<Event> events) => events.any(
        (event) =>
            event.type == EventTypes.Encrypted &&
            event.messageType == MessageTypes.BadEncrypted,
      );

  /// Sends the user to the security screen, then rebuilds the timeline so the
  /// messages the new keys unlock appear in place.
  Future<void> _unlockMessages() async {
    await SecurityScreen.open(context);
    if (!mounted) return;
    await _openTimeline();
  }

  /// Asks for the missing room keys again — enough once the recovery key has
  /// been entered, or when the other device came back online.
  void _retryKeys() {
    _timeline?.requestKeys();
    unawaited(_openTimeline());
  }

  /// Renders events defensively: one malformed event (missing sender,
  /// redaction race…) must never blank the whole screen — that was the
  /// "black screen after 2 s" bug. A bad event is skipped and logged instead
  /// of throwing through the build method.
  List<Widget> _renderMessages(List<Event> events) {
    final widgets = <Widget>[];
    final ownId = room.client.userID ?? '';
    DateTime? lastDay;
    Event? previous;

    for (final event in events) {
      final kind = _classify(event);
      if (kind == _EventKind.hidden) continue;

      try {
        final ts = event.originServerTs;
        final day = DateTime(ts.year, ts.month, ts.day);
        final isNewDay = lastDay == null || day != lastDay;

        Widget? systemNotice;
        if (kind == _EventKind.system) {
          final text = _systemText(event);
          if (text.isEmpty) continue;
          systemNotice = MessageBubble(
            body: text,
            isMine: false,
            timestamp: ts,
            isSystem: true,
          );
        }

        if (isNewDay) {
          widgets.add(DaySeparator(label: _dayLabel(day)));
          previous = null;
          lastDay = day;
        }

        if (systemNotice != null) {
          widgets.add(systemNotice);
          previous = null;
          continue;
        }

        final senderId = event.senderId;
        final isMine = senderId == ownId;
        final startsRun =
            previous == null ||
            previous.senderId != senderId ||
            ts.difference(previous.originServerTs) >
                const Duration(minutes: 5);

        final group =
            !room.isDirectChat && startsRun && !isMine && events.length > 1;

        widgets.add(
          MessageBubble(
            body: _bubbleBody(event),
            isMine: isMine,
            timestamp: ts,
            showTail: startsRun,
            senderName: group
                ? (event.senderFromMemoryOrFallback.displayName ?? senderId)
                : null,
            senderColor: _senderColor(senderId),
            status: event.status,
            failed: event.status == EventStatus.error,
          ),
        );
        previous = event;
      } catch (e, s) {
        Logs().w('[Liber] Skipping unrenderable event ${event.eventId}', e, s);
      }
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
      if (event.messageType == MessageTypes.BadEncrypted || event.body.isEmpty) {
        return '🔒 Message chiffré illisible';
      }
      return event.body;
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
    if (diff < 7) return DateFormat.EEEE().format(day).toUpperCase();
    if (day.year == now.year) {
      return DateFormat('d MMMM').format(day).toUpperCase();
    }
    return DateFormat.yMMMMd().format(day).toUpperCase();
  }

  /// Stable per-sender hue so group members are easy to tell apart.
  static Color _senderColor(String userId) {
    if (userId.isEmpty) return WaPalette.avatarPalette.first;
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

/// Tells the user that the locks in this conversation are a missing-key
/// problem — not a broken message — and offers the two ways out.
class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.onUnlock, required this.onRetry});

  final VoidCallback onUnlock;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 20, color: Color(0xFFE0902B)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Des messages chiffrés ne peuvent pas être lus sur cet '
                    'appareil.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.35,
                      color: WaPalette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onRetry,
                  child: const Text('Réessayer'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: onUnlock,
                  child: const Text('Déverrouiller'),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains why the conversation could not open instead of leaving a grey
/// void, with a retry for transient failures.
class _ChatIssue extends StatelessWidget {
  const _ChatIssue({
    required this.message,
    required this.canRetry,
    required this.onRetry,
  });

  final String message;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: WaPalette.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Salon indisponible',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: WaPalette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                color: WaPalette.textSecondary,
                height: 1.4,
              ),
            ),
            if (canRetry) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _EventKind { message, system, hidden }
