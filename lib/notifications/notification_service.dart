import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';

/// Turns the SDK's notification events into system notifications.
///
/// There is no push gateway behind this app: the matrix SDK already decides
/// what deserves a notification by evaluating the account's push rules
/// (`Client.onNotification` only fires for events whose rules say *notify*,
/// which already excludes muted rooms), and this service shows them while
/// the app is in the background.
///
/// Tapping a notification records the room in [pendingRoomId]; the home
/// screen consumes it and opens the conversation.
class NotificationService {
  NotificationService._();

  static const String _channelId = 'liber_messages';
  static const String _channelName = 'Messages';
  static const String _channelDescription =
      'Nouveaux messages et invitations';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Room the user tapped on, waiting for the home screen to open it.
  static final ValueNotifier<String?> pendingRoomId = ValueNotifier(null);

  static bool _initialized = false;

  /// Prepares the plugin and its channel. Must run before the first
  /// notification is shown, and once per process.
  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          pendingRoomId.value = payload;
        }
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
    _initialized = true;
  }

  /// Asks for the Android 13+ notification permission. Called after login so
  /// the user is asked in context instead of at first launch.
  static Future<void> requestPermission() async {
    try {
      final status = await Permission.notification.status;
      if (status.isGranted || status.isPermanentlyDenied) return;
      await Permission.notification.request();
    } catch (_) {
      // A device without the permission model must not break the login.
    }
  }

  /// Subscribes to the client for the rest of the process. Safe to call more
  /// than once per client — bootstrap only runs once, but the guard costs
  /// nothing.
  static void bind(Client client) {
    client.onNotification.stream.listen(
      (event) => showForEvent(event),
      onError: (Object _) {},
    );
  }

  /// Shows [event] as a system notification when the app is not on screen.
  static Future<void> showForEvent(Event event) async {
    if (!_initialized) return;
    final room = event.room;
    final isInvite = event.eventId.startsWith('invite_for_');

    if (!shouldNotify(
      pushRuleState: room.pushRuleState,
      isSpace: room.isSpace,
      lifecycleState: WidgetsBinding.instance.lifecycleState,
    )) {
      return;
    }

    final sender =
        event.senderFromMemoryOrFallback.displayName ?? event.senderId;
    final roomName = room.getLocalizedDisplayname();
    final title = isInvite
        ? 'Invitation à $roomName'
        : (room.isDirectChat ? sender : '$roomName · $sender');

    try {
      await _plugin.show(
        id: stableId(room.id),
        title: title,
        body: _body(event, isInvite: isInvite),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            autoCancel: true,
          ),
        ),
        payload: room.id,
      );
    } catch (_) {
      // A device that refuses notifications must not take the sync down.
    }
  }

  /// Whether a system notification should be posted for this event.
  ///
  /// Kept free of platform calls so it can be unit tested: the decision only
  /// depends on the room's push rule state, whether the room is a space, and
  /// whether the app is already showing the conversation list.
  static bool shouldNotify({
    required PushRuleState pushRuleState,
    required bool isSpace,
    required AppLifecycleState? lifecycleState,
  }) {
    // The user is in the app and can see the message themselves.
    if (lifecycleState == AppLifecycleState.resumed) return false;
    // Spaces are containers, not conversations.
    if (isSpace) return false;
    // Room muted from this app or from another client of the account.
    if (pushRuleState == PushRuleState.dontNotify) return false;
    return true;
  }

  /// Notification text. Never invents content: an encrypted event the device
  /// cannot read is announced as such rather than leaking placeholder text.
  static String _body(Event event, {required bool isInvite}) {
    if (isInvite) return 'Vous a invité à rejoindre la conversation.';
    if (event.type == EventTypes.Encrypted &&
        (event.messageType == MessageTypes.BadEncrypted ||
            event.body.isEmpty)) {
      return 'Message chiffré';
    }
    final text = event.body.replaceAll('\n', ' ').trim();
    if (text.isEmpty) return 'Nouveau message';
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  /// Deterministic id per room, so a second message updates the existing
  /// notification instead of stacking another one — and the mapping is stable
  /// across app restarts.
  static int stableId(String roomId) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < roomId.length; i++) {
      hash ^= roomId.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    // Android rejects negative ids, and the empty room id above skips the
    // loop, so the mask has to happen here too.
    return hash & 0x7fffffff;
  }
}
