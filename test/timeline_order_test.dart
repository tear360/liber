import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liber/screens/chat_screen.dart';
import 'package:liber/widgets/message_bubble.dart';
import 'package:matrix/matrix.dart';

/// Minimal stand-ins: the reordering and the tail rule only read the sender
/// and the timestamp of a neighbouring event.
class _FakeEvent implements Event {
  _FakeEvent(this.eventId, this.senderId, this.originServerTs);

  @override
  final String eventId;
  @override
  final String senderId;
  @override
  final DateTime originServerTs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Event _event(String id, String sender, DateTime ts) => _FakeEvent(id, sender, ts);

void main() {
  group('timelineEventsOldestFirst', () {
    test('reverses the SDK order so the newest message renders last', () {
      final now = DateTime(2026, 1, 1, 12);
      final events = [
        _event(r'$newest', '@alice:test', now),
        _event(
            r'$middle', '@bob:test', now.subtract(const Duration(minutes: 5))),
        _event(r'$oldest', '@alice:test',
            now.subtract(const Duration(minutes: 10))),
      ];

      final ordered = timelineEventsOldestFirst(events);

      expect(
          ordered.map((e) => e.eventId).toList(), [r'$oldest', r'$middle', r'$newest']);
      expect(timelineEventsOldestFirst(const []), isEmpty);
      expect(
          timelineEventsOldestFirst([_event(r'$only', '@a:test', now)])
              .single
              .eventId,
          r'$only');
    });
  });

  group('newerEventOf', () {
    final base = DateTime(2026, 1, 1, 12);
    final events = [
      _event(r'$b', '@bob:test', base),
      _event(r'$a', '@alice:test', base.subtract(const Duration(minutes: 1))),
    ];

    test('returns the event ahead of it in the SDK list', () {
      expect(newerEventOf(events, events[1])?.eventId, r'$b');
    });

    test('returns null for the newest event', () {
      expect(newerEventOf(events, events[0]), isNull);
    });

    test('returns null when the event is not in the list', () {
      expect(newerEventOf(events, _event(r'$other', '@a:test', base)), isNull);
    });
  });

  group('endsMessageRun', () {
    final base = DateTime(2026, 1, 1, 12);

    test('closes the run when nothing follows (newest message)', () {
      final e = _event(r'$a', '@alice:test', base);
      expect(endsMessageRun(e, null), isTrue);
    });

    test('closes the run when the next message is from someone else', () {
      final e = _event(r'$a', '@alice:test', base);
      final other =
          _event(r'$b', '@bob:test', base.add(const Duration(minutes: 1)));
      expect(endsMessageRun(e, other), isTrue);
    });

    test('keeps the run open for a follow-up from the same sender', () {
      final e = _event(r'$a', '@alice:test', base);
      final same =
          _event(r'$b', '@alice:test', base.add(const Duration(minutes: 1)));
      expect(endsMessageRun(e, same), isFalse);
    });

    test('closes the run after a gap longer than five minutes', () {
      final e = _event(r'$a', '@alice:test', base);
      final later = _event(
          r'$b', '@alice:test', base.add(const Duration(minutes: 5, seconds: 1)));
      expect(endsMessageRun(e, later), isTrue);
    });

    test('keeps the run open at exactly five minutes', () {
      final e = _event(r'$a', '@alice:test', base);
      final later =
          _event(r'$b', '@alice:test', base.add(const Duration(minutes: 5)));
      expect(endsMessageRun(e, later), isFalse);
    });
  });

  group('MessageBubble tap on a locked bubble', () {
    testWidgets('invokes onTapLock and leaves other bubbles inert',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: Column(
            children: [
              MessageBubble(
                body: '🔒 Message chiffré illisible',
                isMine: false,
                timestamp: DateTime(2026, 1, 1, 12),
                onTapLock: () => taps++,
              ),
              MessageBubble(
                body: 'Message ordinaire',
                isMine: false,
                timestamp: DateTime(2026, 1, 1, 12),
              ),
            ],
          ),
        ),
      ));

      expect(find.text('🔒 Message chiffré illisible'), findsOneWidget);
      expect(find.text('Message ordinaire'), findsOneWidget);

      await tester.tap(find.text('🔒 Message chiffré illisible'));
      expect(taps, 1);

      await tester.tap(find.text('Message ordinaire'));
      expect(taps, 1, reason: 'a plain bubble must not open the lock dialog');
    });
  });
}
