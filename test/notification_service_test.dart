import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:liber/notifications/notification_service.dart';
import 'package:matrix/matrix.dart' show PushRuleState;

void main() {
  group('NotificationService.shouldNotify', () {
    bool decide({
      PushRuleState state = PushRuleState.notify,
      bool isSpace = false,
      AppLifecycleState? lifecycle,
    }) =>
        NotificationService.shouldNotify(
          pushRuleState: state,
          isSpace: isSpace,
          lifecycleState: lifecycle,
        );

    test('stays silent while the app is on screen', () {
      expect(
        decide(lifecycle: AppLifecycleState.resumed),
        isFalse,
      );
    });

    test('announces a message received in the background', () {
      expect(decide(lifecycle: AppLifecycleState.paused), isTrue);
      expect(decide(lifecycle: AppLifecycleState.inactive), isTrue);
    });

    test('honours a room muted through the push rules', () {
      expect(
        decide(state: PushRuleState.dontNotify, lifecycle: AppLifecycleState.paused),
        isFalse,
      );
    });

    test('never notifies for a space', () {
      expect(decide(isSpace: true, lifecycle: AppLifecycleState.paused), isFalse);
    });

    test('falls back to notifying when the lifecycle is unknown', () {
      expect(decide(lifecycle: null), isTrue);
    });
  });

  group('NotificationService.stableId', () {
    test('gives the same room the same id every time', () {
      final first = NotificationService.stableId('!abc:example.org');
      final second = NotificationService.stableId('!abc:example.org');
      expect(first, second);
    });

    test('stays inside the positive 32-bit range Android expects', () {
      for (final roomId in [
        '!abc:example.org',
        '!very-long-room-identifier-with-many-characters:example.org',
        'r',
        '',
        '!日本語:example.org',
      ]) {
        expect(
          NotificationService.stableId(roomId),
          inInclusiveRange(0, 0x7fffffff),
        );
      }
    });

    test('gives different rooms different ids', () {
      expect(
        NotificationService.stableId('!one:example.org'),
        isNot(NotificationService.stableId('!two:example.org')),
      );
    });
  });
}
