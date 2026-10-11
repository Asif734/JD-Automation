import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/codex/customer_codex_session.dart';

void main() {
  test('rolls over long model threads while retaining delivered history', () {
    final messages = <Map<String, dynamic>>[
      {'id': 'q', 'direction': 'incoming', 'body': 'TD630?'},
      {'id': 'a', 'direction': 'outgoing', 'body': 'Use USB.'},
      {'id': 'q2', 'direction': 'incoming', 'body': 'Which driver?'},
    ];
    final session = CustomerCodexSession(
        threadId: 'long-thread',
        model: 'gpt-6.1-sol',
        historyCount: 1,
        historyFingerprint: CustomerCodexSession.fingerprint(messages.take(1)),
        lastReply: 'Use USB.',
        updatedAt: DateTime.now(),
        turnCount: 4);
    expect(session.canResume(messages, 'gpt-6.1-sol'), isFalse);
    expect(messages, hasLength(3));
  });
  test('resumes only after the prior reply is actually in delivered history',
      () async {
    final directory = await Directory.systemTemp.createTemp('jd_session_test_');
    addTearDown(() => directory.delete(recursive: true));
    final store = CustomerCodexSessionStore(directory);
    final firstTurn = <Map<String, dynamic>>[
      {'id': 'customer-1', 'direction': 'incoming', 'body': 'M880D date?'}
    ];
    await store.write(
        'buyer-one',
        CustomerCodexSession(
          threadId: 'thread-one',
          model: 'gpt-5.6-sol',
          historyCount: firstTurn.length,
          historyFingerprint: CustomerCodexSession.fingerprint(firstTurn),
          lastReply: 'Please check the date settings.',
          updatedAt: DateTime.now(),
        ));
    final session = (await store.read('buyer-one'))!;
    expect(session.canResume(firstTurn, 'gpt-5.6-sol'), isFalse);
    final delivered = <Map<String, dynamic>>[
      ...firstTurn,
      {
        'id': 'service-1',
        'direction': 'outgoing',
        'body': 'Please check the date settings.'
      },
      {'id': 'customer-2', 'direction': 'incoming', 'body': 'Where?'}
    ];
    expect(session.canResume(delivered, 'gpt-5.6-sol'), isTrue);
    expect(session.canResume(delivered, 'another-model'), isFalse);
    expect(
        session.canResume([
          {
            'id': 'customer-1',
            'direction': 'incoming',
            'body': 'Different question'
          },
          ...delivered.skip(1),
        ], 'gpt-5.6-sol'),
        isFalse);
    expect(await store.read('buyer-two'), isNull);
  });
}
