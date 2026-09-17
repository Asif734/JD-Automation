import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/codex/customer_codex_session.dart';

void main() {
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
