import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/domain/capture_models.dart';
import 'package:jd_automation/storage/capture_database.dart';

void main() {
  test('demo data uses JSON history and SQLite only as pending queue',
      () async {
    final root = await Directory.systemTemp.createTemp('jd_automation_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    await database.seedDemoData();
    await database.seedDemoData();

    final pending = await database.conversations();
    expect(pending.map((item) => item.customerName),
        containsAll(<String>['tb302030', 'tb32020']));
    expect(pending, hasLength(2));

    final store = await database.history;
    final first = await store.read('tb302030');
    expect(first?['messages'], hasLength(1));
    final second = await store.read('tb32020');
    final secondMessages = second?['messages'] as List<Object?>;
    final media = (secondMessages.single as Map<String, dynamic>)['media']
        as List<Object?>;
    final mediaPath = (media.single as Map<String, dynamic>)['path'] as String;
    expect(await File(mediaPath).exists(), isTrue);
    expect(
        await store.updateMediaDescriptions(
            'tb32020', {mediaPath: 'A one-pixel demo customer image.'}),
        1);
    final described = await store.read('tb32020');
    final describedMessages = described?['messages'] as List<Object?>;
    final describedMedia = (describedMessages.single
        as Map<String, dynamic>)['media'] as List<Object?>;
    expect((describedMedia.single as Map<String, dynamic>)['description'],
        'A one-pixel demo customer image.');
    expect(
        await store.hasSimilarImageFingerprint('tb32020', 'fffffffffffffffe'),
        isTrue);
    expect(
        await store.hasSimilarImageFingerprint('tb32020', 'fffffffffffffffe',
            captureSources: const {'verified_window_crop'}),
        isFalse);
    expect(
        await store.hasSimilarImageFingerprint('tb32020', '0000000000000000'),
        isFalse);

    const rawReply =
        '{"reply":"Hello! How can I help?","decision":"draft","confidence":0.9,"risk_level":"low","model":"demo-codex","used_record_ids":[],"actions":[],"attachments":[]}';
    final draft = AiDraft(
      reply: 'Hello! How can I help?',
      decision: 'draft',
      confidence: 0.9,
      riskLevel: 'low',
      model: 'demo-codex',
      usedRecordIds: const [],
      actions: const [],
      attachments: const [],
      rawJson: rawReply,
    );
    await database.saveDraft(pending.first.id, draft);

    expect(await database.conversations(), hasLength(1));
    final beforeSend = await store.read(pending.first.customerName);
    expect(beforeSend?['messages'], hasLength(1));

    expect(
        await database.markReplySent(
            userId: pending.first.customerName, reply: draft.reply),
        isTrue);
    final completed = await store.read(pending.first.customerName);
    final completedMessages = completed?['messages'] as List<Object?>;
    expect(completedMessages, hasLength(2));
    expect((completedMessages.last as Map<String, dynamic>)['body'],
        'Hello! How can I help?');
    expect((completedMessages.last as Map<String, dynamic>)['delivery_status'],
        'sent');
  });

  test('human contacting pauses AI and contacted resumes only on next message',
      () async {
    final root = await Directory.systemTemp.createTemp('ticket_state_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final first = CapturedConversation(
      stableKey: 'customer:test-buyer',
      customerName: 'test-buyer',
      customerExternalId: 'test-buyer',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(1),
      messages: const [
        CapturedMessage(
            stableId: 'message-1',
            direction: 'incoming',
            body: 'I want a refund',
            axPath: 'ocr'),
      ],
    );
    await database.saveCapture(first);
    final ticket = await database.createHumanReviewTicket(
        userId: 'test-buyer',
        customerRequest: 'I want a refund',
        reason: 'Refund requires a human');
    expect(ticket.status, 'open');
    expect(await database.isHumanContacting('test-buyer'), isFalse);
    expect(await database.hasPendingUnanswered('test-buyer'), isFalse);

    // An open review ticket pauses Codex immediately. Follow-up customer
    // messages are retained for the human but cannot create another reply.
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:test-buyer',
      customerName: 'test-buyer',
      customerExternalId: 'test-buyer',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(2),
      messages: const [
        CapturedMessage(
            stableId: 'open-ticket-follow-up',
            direction: 'incoming',
            body: 'This clarifies the same request',
            axPath: 'ocr'),
      ],
    ));
    expect(await database.conversations(), isEmpty);

    await database.markTicketContacting(ticket.id);
    expect(await database.isHumanContacting('test-buyer'), isTrue);
    expect(await database.conversations(), isEmpty);

    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:test-buyer',
      customerName: 'test-buyer',
      customerExternalId: 'test-buyer',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(3),
      messages: const [
        CapturedMessage(
            stableId: 'message-2',
            direction: 'incoming',
            body: 'Human-handled message',
            axPath: 'ocr'),
      ],
    ));
    expect(await database.conversations(), isEmpty);

    // The manual seller response is captured while human control is active.
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:test-buyer',
      customerName: 'test-buyer',
      customerExternalId: 'test-buyer',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(4),
      messages: const [
        CapturedMessage(
            stableId: 'manual-reply-1',
            direction: 'outgoing',
            body: 'A human handled this question.',
            axPath: 'ocr'),
      ],
    ));
    expect(await database.conversations(), isEmpty);

    // A takeover for one customer must not pause another customer's queue.
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:other-buyer',
      customerName: 'other-buyer',
      customerExternalId: 'other-buyer',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(4),
      messages: const [
        CapturedMessage(
            stableId: 'other-message-1',
            direction: 'incoming',
            body: 'What is the portable printer price?',
            axPath: 'ocr'),
      ],
    ));
    expect((await database.conversations()).single.userId, 'other-buyer');

    await database.markTicketContacted(ticket.id);
    expect(await database.humanReviewTickets(), isEmpty);
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:test-buyer',
      customerName: 'test-buyer',
      customerExternalId: 'test-buyer',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(5),
      messages: const [
        CapturedMessage(
            stableId: 'message-3',
            direction: 'incoming',
            body: 'A genuinely new question',
            axPath: 'ocr'),
      ],
    ));
    expect((await database.conversations()).map((item) => item.userId),
        containsAll(<String>['other-buyer', 'test-buyer']));
  });

  test('deduplicates a recently re-ordered OCR reading of one message',
      () async {
    final root = await Directory.systemTemp.createTemp('ocr_reorder_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final firstTime = DateTime.utc(2026, 8, 30, 5, 58, 41);
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:buyer',
      customerName: 'buyer',
      customerExternalId: 'buyer',
      capturedAt: firstTime,
      messages: const [
        CapturedMessage(
          stableId: 'ocr:first',
          direction: 'incoming',
          body: 'sorry it was slip of pen. typing',
          axPath: 'ocr',
        ),
      ],
    ));
    final pending = (await database.conversations()).single;
    const replyJson =
        '{"reply":"No worries.","decision":"draft","confidence":0.99,'
        '"risk_level":"low","model":"gpt-5.6-sol","used_record_ids":[],'
        '"actions":[],"attachments":[]}';
    await database.saveDraft(
      pending.id,
      const AiDraft(
        reply: 'No worries.',
        decision: 'draft',
        confidence: 0.99,
        riskLevel: 'low',
        model: 'gpt-5.6-sol',
        usedRecordIds: [],
        actions: [],
        attachments: [],
        rawJson: replyJson,
      ),
    );
    await database.markReplySent(userId: 'buyer', reply: 'No worries.');

    final changed = await database.saveCapture(CapturedConversation(
      stableKey: 'customer:buyer',
      customerName: 'buyer',
      customerExternalId: 'buyer',
      capturedAt: firstTime.add(const Duration(seconds: 15)),
      messages: const [
        CapturedMessage(
          stableId: 'ocr:reordered',
          direction: 'incoming',
          body: 'slip of pen. typing sorry it was',
          axPath: 'ocr',
        ),
      ],
    ));

    expect(changed, 0);
    expect(await database.hasPendingUnanswered('buyer'), isFalse);
    final document = await (await database.history).read('buyer');
    expect(document?['messages'], hasLength(2));
  });

  test('upgrades a clipped incoming bubble without replying twice', () async {
    final root = await Directory.systemTemp.createTemp('ocr_upgrade_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final firstTime = DateTime.utc(2026, 8, 31, 8, 35, 47);
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:buyer',
      customerName: 'buyer',
      customerExternalId: 'buyer',
      capturedAt: firstTime,
      messages: const [
        CapturedMessage(
          stableId: 'ocr:partial',
          direction: 'incoming',
          body: 'what is the model no of your face',
          axPath: 'ocr',
        ),
      ],
    ));
    final pending = (await database.conversations()).single;
    const replyJson =
        '{"reply":"Let me help.","decision":"draft","confidence":0.9,'
        '"risk_level":"low","model":"test","used_record_ids":[],'
        '"actions":[],"attachments":[]}';
    await database.saveDraft(
        pending.id,
        const AiDraft(
            reply: 'Let me help.',
            decision: 'draft',
            confidence: 0.9,
            riskLevel: 'low',
            model: 'test',
            usedRecordIds: [],
            actions: [],
            attachments: [],
            rawJson: replyJson));
    await database.markReplySent(userId: 'buyer', reply: 'Let me help.');

    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:buyer',
      customerName: 'buyer',
      customerExternalId: 'buyer',
      capturedAt: firstTime.add(const Duration(seconds: 15)),
      messages: const [
        CapturedMessage(
          stableId: 'ocr:complete',
          direction: 'incoming',
          body: 'what is the model no of your face attendance machine?',
          axPath: 'ocr',
        ),
      ],
    ));

    expect(await database.hasPendingUnanswered('buyer'), isFalse);
    final document = await (await database.history).read('buyer');
    final messages = document!['messages'] as List<Object?>;
    expect(messages, hasLength(2));
    expect((messages.first as Map<String, dynamic>)['body'],
        'what is the model no of your face attendance machine?');
  });

  test('suppresses a middle fragment of an already sent reply', () async {
    final root = await Directory.systemTemp.createTemp('ocr_reply_fragment_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:buyer',
      customerName: 'buyer',
      customerExternalId: 'buyer',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(1),
      messages: const [
        CapturedMessage(
          stableId: 'incoming',
          direction: 'incoming',
          body: 'Are you a real person?',
          axPath: 'ocr',
        ),
      ],
    ));
    final pending = (await database.conversations()).single;
    const fullReply =
        "I'm a virtual customer-service assistant, so I don't have a real face.";
    const replyJson =
        '{"reply":"I\u0027m a virtual customer-service assistant, so I don\u0027t have a real face.","decision":"draft","confidence":0.9,'
        '"risk_level":"low","model":"test","used_record_ids":[],'
        '"actions":[],"attachments":[]}';
    await database.saveDraft(
        pending.id,
        const AiDraft(
            reply: fullReply,
            decision: 'draft',
            confidence: 0.9,
            riskLevel: 'low',
            model: 'test',
            usedRecordIds: [],
            actions: [],
            attachments: [],
            rawJson: replyJson));
    await database.markReplySent(userId: 'buyer', reply: fullReply);

    final changed = await database.saveCapture(CapturedConversation(
      stableKey: 'customer:buyer',
      customerName: 'buyer',
      customerExternalId: 'buyer',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(2),
      messages: const [
        CapturedMessage(
          stableId: 'outgoing-fragment',
          direction: 'outgoing',
          body: 'virtual customer-service assistant',
          axPath: 'ocr',
        ),
      ],
    ));

    expect(changed, 0);
    final document = await (await database.history).read('buyer');
    expect(document!['messages'], hasLength(2));
  });

  test('requeues an unanswered saved message but not an answered one',
      () async {
    final root = await Directory.systemTemp.createTemp('draft_recovery_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final capture = CapturedConversation(
      stableKey: 'customer:recovery',
      customerName: 'recovery-user',
      customerExternalId: 'recovery-user',
      capturedAt: DateTime.now(),
      messages: const [
        CapturedMessage(
          stableId: 'recovery-message-1',
          direction: 'incoming',
          body: 'Need help',
          axPath: 'test',
        ),
      ],
    );
    await database.saveCapture(capture);
    await (await database.database).delete('pending_customers',
        where: 'user_id = ?', whereArgs: ['recovery-user']);

    expect(await database.ensurePendingForUnanswered('recovery-user'), isTrue);
    final pending = await database.conversations();
    final conversation =
        pending.singleWhere((item) => item.userId == 'recovery-user');
    const draft = AiDraft(
      reply: 'How can I help?',
      decision: 'draft',
      confidence: 0.9,
      riskLevel: 'low',
      model: 'test',
      usedRecordIds: [],
      actions: [],
      attachments: [],
      rawJson: '{"reply":"How can I help?"}',
    );
    await database.saveDraft(conversation.id, draft);

    expect(await database.ensurePendingForUnanswered('recovery-user'), isFalse);
  });

  test('seller reply clears pending customer and cannot trigger another draft',
      () async {
    final root = await Directory.systemTemp.createTemp('seller_reply_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final incoming = CapturedConversation(
      stableKey: 'customer:answered',
      customerName: 'answered-user',
      customerExternalId: 'answered-user',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(1),
      messages: const [
        CapturedMessage(
          stableId: 'incoming-1',
          direction: 'incoming',
          body: 'How can I buy this?',
          axPath: 'test',
        ),
      ],
    );
    await database.saveCapture(incoming);
    expect(await database.conversations(), hasLength(1));

    await database.saveCapture(CapturedConversation(
      stableKey: incoming.stableKey,
      customerName: incoming.customerName,
      customerExternalId: incoming.customerExternalId,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(2),
      messages: const [
        CapturedMessage(
          stableId: 'incoming-1',
          direction: 'incoming',
          body: 'How can I buy this?',
          axPath: 'test',
        ),
        CapturedMessage(
          stableId: 'outgoing-1',
          direction: 'outgoing',
          body: 'I will send the purchase link.',
          axPath: 'test',
        ),
      ],
    ));

    expect(await database.conversations(), isEmpty);
    expect(await database.ensurePendingForUnanswered('answered-user'), isFalse);

    // Simulate a stale queue row left by an older build. Eligibility checking
    // must repair it before Codex can run again.
    final db = await database.database;
    await db.insert('pending_customers', {
      'user_id': 'answered-user',
      'display_name': 'answered-user',
      'stable_key': 'customer:answered',
      'newest_message_id': 'incoming-1',
      'enqueued_at_ms': 1,
      'updated_at_ms': 2,
    });
    expect(await database.hasPendingUnanswered('answered-user'), isFalse);
    expect(await database.conversations(), isEmpty);
  });

  test('same JD timestamp suppresses partial OCR re-reads', () async {
    final root = await Directory.systemTemp.createTemp('bubble_time_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final sentAt = DateTime(2026, 8, 31, 18, 18, 16);
    CapturedConversation capture(String id, String body, DateTime capturedAt) =>
        CapturedConversation(
          stableKey: 'customer:timestamp',
          customerName: 'jd_test',
          customerExternalId: 'jd_test',
          capturedAt: capturedAt,
          messages: [
            CapturedMessage(
              stableId: id,
              direction: 'incoming',
              body: body,
              sentAt: sentAt,
              axPath: 'ocr:test',
            ),
          ],
        );

    await database
        .saveCapture(capture('ocr:first', 'not finding the machine', sentAt));
    await database.saveCapture(capture('ocr:partial', 'am not finding',
        sentAt.add(const Duration(seconds: 30))));

    final history = await database.history;
    final document = await history.read('jd_test');
    final messages = document!['messages'] as List<Object?>;
    expect(messages, hasLength(1));
    expect((messages.single as Map<String, dynamic>)['body'],
        'not finding the machine');
  });

  test('exact production sequence keeps one incoming and one outgoing',
      () async {
    final root =
        await Directory.systemTemp.createTemp('exact_jd_sequence_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final history = await database.history;
    final incomingTime = DateTime(2026, 8, 31, 18, 18, 16);
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:exact',
      customerName: 'jd_41aeec7741d05',
      customerExternalId: 'jd_41aeec7741d05',
      capturedAt: incomingTime,
      messages: [
        CapturedMessage(
          stableId: 'ocr:original',
          direction: 'incoming',
          body: 'not finding the machine',
          sender: 'jd_41aeec7741d05',
          sentAt: incomingTime,
          axPath: 'ocr:test',
        ),
      ],
    ));
    const reply =
        'Please make sure your phone’s Bluetooth and location are turned on and that the app has permission to use both, then search again.';
    await history.appendSentReply(
      userId: 'jd_41aeec7741d05',
      displayName: 'jd_41aeec7741d05',
      stableKey: 'customer:exact',
      draft: const AiDraft(
        reply: reply,
        decision: 'ask_clarification',
        confidence: .97,
        riskLevel: 'medium',
        model: 'gpt-5.6-sol',
        usedRecordIds: [],
        actions: [],
        attachments: [],
        rawJson:
            '{"reply":"test","decision":"ask_clarification","confidence":0.97,"risk_level":"medium","model":"gpt-5.6-sol","used_record_ids":[],"actions":[],"attachments":[]}',
      ),
    );
    final documentBefore = await history.read('jd_41aeec7741d05');
    final generated = (documentBefore!['messages'] as List<Object?>)
        .whereType<Map<String, dynamic>>()
        .last;
    final generatedTime = DateTime.parse(generated['sent_at'] as String);

    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:exact',
      customerName: 'jd_41aeec7741d05',
      customerExternalId: 'jd_41aeec7741d05',
      capturedAt: generatedTime.add(const Duration(seconds: 15)),
      messages: [
        CapturedMessage(
          stableId: 'ocr:partial-incoming',
          direction: 'incoming',
          body: 'am not finding',
          sender: 'jd_41aeec7741d05',
          sentAt: incomingTime,
          axPath: 'ocr:test',
        ),
        CapturedMessage(
          stableId: 'ocr:partial-outgoing',
          direction: 'outgoing',
          body: "Please make sure your phone's",
          sender: '18:18:31 格志打印机小甘',
          sentAt: generatedTime.subtract(const Duration(seconds: 1)),
          axPath: 'ocr:test',
        ),
      ],
    ));

    final document = await history.read('jd_41aeec7741d05');
    final messages = document!['messages'] as List<Object?>;
    expect(messages, hasLength(2));
    expect((messages.first as Map<String, dynamic>)['body'],
        'not finding the machine');
    expect((messages.last as Map<String, dynamic>)['body'], reply);
  });
}
