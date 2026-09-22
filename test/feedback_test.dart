import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leasegauge/data/feedback_client.dart';
import 'package:leasegauge/screens/feedback_screen.dart';

void main() {
  test('only the intended endpoint receives bounded user fields', () async {
    http.Request? captured;
    final client = FeedbackClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"status":"sent"}', 200);
      }),
    );
    await client.send(
      kind: FeedbackKind.bug,
      message: '  Saving did not work.  ',
      replyEmail: '  test@example.com  ',
    );
    expect(
      captured!.url.toString(),
      'https://leasegauge.jonaspettersen.no/leasegauge/api/feedback',
    );
    expect(jsonDecode(captured!.body), {
      'kind': 'bug',
      'message': 'Saving did not work.',
      'reply_email': 'test@example.com',
    });
    expect(captured!.headers['content-type'], 'application/json');
    client.close();
  });

  test('rate limit and network failure use safe user messages', () async {
    final limited = FeedbackClient(
      httpClient: MockClient((_) async => http.Response('', 429)),
    );
    expect(
      () => limited.send(kind: FeedbackKind.idea, message: 'A valid idea.'),
      throwsA(isA<FeedbackException>()),
    );
    limited.close();
  });

  testWidgets('feedback form sends once and confirms success', (tester) async {
    var calls = 0;
    final client = FeedbackClient(
      httpClient: MockClient((request) async {
        calls++;
        return http.Response('{"status":"sent"}', 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(home: FeedbackScreen(client: client)));
    await tester.enterText(
      find.byKey(const Key('feedbackMessage')),
      'Please make the daily number easier to read.',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('sendFeedbackButton')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('sendFeedbackButton')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Thank you — your message was sent.'), findsOneWidget);
    client.close();
  });

  testWidgets('failed delivery keeps the written message for retry', (
    tester,
  ) async {
    final client = FeedbackClient(
      httpClient: MockClient((_) async => http.Response('', 503)),
    );
    await tester.pumpWidget(MaterialApp(home: FeedbackScreen(client: client)));
    const message = 'The odometer did not update after connecting.';
    await tester.enterText(find.byKey(const Key('feedbackMessage')), message);
    await tester.scrollUntilVisible(
      find.byKey(const Key('sendFeedbackButton')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('sendFeedbackButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feedbackError')), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    client.close();
  });
}
