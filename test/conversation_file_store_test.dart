import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/domain/capture_models.dart';
import 'package:jd_automation/storage/conversation_file_store.dart';

void main() {
  late Directory root;
  late ConversationFileStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('conversation_store_test_');
    store = ConversationFileStore(root);
  });

  tearDown(() => root.delete(recursive: true));

  CapturedMessage incoming(String id, String body, DateTime sentAt) =>
      CapturedMessage(
        stableId: id,
        direction: 'incoming',
        body: body,
        sender: 'customer',
        sentAt: sentAt,
        axPath: 'test/$id',
      );

  test('preserves separate customer messages sent within three seconds',
      () async {
    final start = DateTime.utc(2026, 9, 3, 17, 55, 23);
    final result = await store.appendCapture(CapturedConversation(
      stableKey: 'customer-1',
      customerName: 'customer-1',
      customerExternalId: 'customer-1',
      capturedAt: start.add(const Duration(seconds: 4)),
      messages: [
        incoming('first', 'm880打不开了', start),
        incoming('second', '怎么回事', start.add(const Duration(seconds: 2))),
      ],
    ));

    final document = await store.read('customer-1');
    final bodies = (document!['messages'] as List)
        .cast<Map<String, Object?>>()
        .map((message) => message['body'])
        .toList();
    expect(result.insertedIncomingIds, ['first', 'second']);
    expect(bodies, ['m880打不开了', '怎么回事']);
  });

  test('still upgrades a partial OCR observation of the same bubble', () async {
    final start = DateTime.utc(2026, 9, 3, 17, 55, 23);
    await store.appendCapture(CapturedConversation(
      stableKey: 'customer-2',
      customerName: 'customer-2',
      customerExternalId: 'customer-2',
      capturedAt: start.add(const Duration(seconds: 4)),
      messages: [
        incoming('partial', 'how to connect', start),
        incoming('complete', 'how to connect tp732 with macos', start),
      ],
    ));

    final document = await store.read('customer-2');
    final messages =
        (document!['messages'] as List).cast<Map<String, Object?>>();
    expect(messages, hasLength(1));
    expect(messages.single['body'], 'how to connect tp732 with macos');
  });
}
