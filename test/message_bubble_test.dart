import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liber/widgets/message_bubble.dart';

void main() {
  Future<void> pumpBubble(
    WidgetTester tester, {
    String? replySender,
    String? replyText,
    bool edited = false,
    bool isMine = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            body: 'Corps du message',
            isMine: isMine,
            timestamp: DateTime(2026, 10, 9, 14, 30),
            replySender: replySender,
            replyText: replyText,
            edited: edited,
          ),
        ),
      ),
    );
  }

  testWidgets('shows the quoted message above the body', (tester) async {
    await pumpBubble(
      tester,
      replySender: 'Alice',
      replyText: 'Message auquel on répond',
    );
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Message auquel on répond'), findsOneWidget);
    expect(find.text('Corps du message'), findsOneWidget);
  });

  testWidgets('labels a message that was edited', (tester) async {
    await pumpBubble(tester, edited: true);
    expect(find.text('modifié'), findsOneWidget);

    await pumpBubble(tester, edited: false);
    expect(find.text('modifié'), findsNothing);
  });

  testWidgets('renders a plain message without a quote', (tester) async {
    await pumpBubble(tester, isMine: true);
    expect(find.text('Corps du message'), findsOneWidget);
    expect(find.text('modifié'), findsNothing);
  });
}
