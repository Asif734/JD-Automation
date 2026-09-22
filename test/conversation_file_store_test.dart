import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
    expect(messages.single['id'], 'partial');
    expect(messages.single['body'], 'how to connect tp732 with macos');
  });

  test('keeps parallel customer histories in customer-named JSON files',
      () async {
    final capturedAt = DateTime.utc(2026, 9, 15, 12, 46);
    final captures = {
      'jd_41aeec7741d05': 'what is the feature of this?',
      '上海思谆志科技': 'what its feature?',
      'clffd520': 'hello',
    };

    await Future.wait(captures.entries.map((entry) => store.appendCapture(
          CapturedConversation(
            stableKey: 'customer:${entry.key}',
            customerName: entry.key,
            customerExternalId: entry.key,
            capturedAt: capturedAt,
            messages: [incoming('${entry.key}-1', entry.value, capturedAt)],
          ),
        )));

    for (final entry in captures.entries) {
      expect(File('${root.path}/${entry.key}.json').existsSync(), isTrue);
      final document = await store.read(entry.key);
      final messages =
          (document!['messages'] as List).cast<Map<String, Object?>>();
      expect(messages.single['body'], entry.value);
      for (final other
          in captures.entries.where((item) => item.key != entry.key)) {
        expect(messages.single['body'], isNot(other.value));
      }
    }
  });

  test('migrates a legacy hashed Unicode customer file without losing data',
      () async {
    const customer = '上海思谆志科技';
    final legacyName = 'user_${sha256.convert(utf8.encode(customer))}.json';
    final legacyFile = File('${root.path}/$legacyName');
    await legacyFile.writeAsString('''{
      "schema_version": 1,
      "user_id": "$customer",
      "display_name": "$customer",
      "stable_key": "customer:legacy",
      "messages": []
    }''');

    final document = await store.read(customer);

    expect(document?['user_id'], customer);
    expect(File('${root.path}/$customer.json').existsSync(), isTrue);
    expect(legacyFile.existsSync(), isFalse);
  });
}
