import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/domain/capture_models.dart';
import 'package:jd_automation/storage/capture_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('transfer welcome reservation rejects the same exact event', () async {
    final root = await Directory.systemTemp.createTemp('welcome_guard_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final now = DateTime(2026, 9, 1, 14);

    expect(
        await database.reserveTransferWelcome(
            userId: 'jd_test', eventKey: 'ocr-shape-a', now: now),
        isTrue);
    expect(
        await database.reserveTransferWelcome(
            userId: 'jd_test',
            eventKey: 'ocr-shape-a',
            now: now.add(const Duration(seconds: 30))),
        isFalse);
    expect(
        await database.reserveTransferWelcome(
            userId: 'jd_test',
            eventKey: 'new-transfer',
            now: now.add(const Duration(seconds: 31))),
        isTrue);

    await database.releaseTransferWelcomeReservation(
      userId: 'jd_test',
      eventKey: 'ocr-shape-a',
    );
    expect(
        await database.reserveTransferWelcome(
            userId: 'jd_test',
            eventKey: 'ocr-shape-a',
            now: now.add(const Duration(minutes: 1))),
        isTrue);
  });

  test('SLA fallback stays separate and final reply remains queued', () async {
    final root = await Directory.systemTemp.createTemp('sla_fallback_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final capturedAt = DateTime(2026, 9, 16, 10);
    const userId = 'sla-customer';
    const messageId = 'customer-message-1';
    const fallback = '请稍等片刻。';

    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:$userId',
      customerName: userId,
      customerExternalId: userId,
      capturedAt: capturedAt,
      messages: const [
        CapturedMessage(
          stableId: messageId,
          direction: 'incoming',
          body: 'Please check this for me.',
          axPath: 'test',
        ),
      ],
    ));

    final job = await database.slaFallbackJob(userId);
    expect(job?.messageId, messageId);
    expect(job?.dueAt, capturedAt.add(const Duration(minutes: 2)));
    expect(
        await database.reserveSlaFallback(userId: userId, messageId: messageId),
        isTrue);
    expect(
        await database.reserveSlaFallback(userId: userId, messageId: messageId),
        isFalse);
    await database.markSlaFallbackSent(
      userId: userId,
      messageId: messageId,
      reply: fallback,
    );

    expect(await database.hasPendingUnanswered(userId), isTrue);
    expect(await database.pendingMessageId(userId), messageId);
    final afterFallback = await (await database.history).read(userId);
    final fallbackMessages = afterFallback!['messages'] as List<Object?>;
    expect(fallbackMessages, hasLength(2));
    expect((fallbackMessages.last as Map<String, dynamic>)['source'],
        'sla_fallback');

    // OCR will later see the fallback in JD. It must be deduplicated instead
    // of being mistaken for a manual seller answer that cancels AI work.
    final changed = await database.saveCapture(CapturedConversation(
      stableKey: 'customer:$userId',
      customerName: userId,
      customerExternalId: userId,
      capturedAt: capturedAt.add(const Duration(minutes: 2, seconds: 2)),
      messages: const [
        CapturedMessage(
          stableId: messageId,
          direction: 'incoming',
          body: 'Please check this for me.',
          axPath: 'test',
        ),
        CapturedMessage(
          stableId: 'ocr-fallback',
          direction: 'outgoing',
          body: fallback,
          axPath: 'test',
        ),
      ],
    ));
    expect(changed, 0);
    expect(await database.hasPendingUnanswered(userId), isTrue);

    final pending = (await database.conversations()).single;
    const finalDraft = AiDraft(
      reply: 'Here is the verified answer.',
      decision: 'draft',
      confidence: 1,
      riskLevel: 'low',
      model: 'test',
      usedRecordIds: [],
      actions: [],
      attachments: [],
      rawJson:
          '{"reply":"Here is the verified answer.","decision":"draft","confidence":1,"risk_level":"low","model":"test","used_record_ids":[],"actions":[],"attachments":[]}',
    );
    await database.saveDraft(pending.id, finalDraft);
    expect((await database.nextReadyDelivery())?.userId, userId);
    expect(
        await database.markReplySent(userId: userId, reply: finalDraft.reply),
        isTrue);

    final completed = await (await database.history).read(userId);
    final completedMessages = completed!['messages'] as List<Object?>;
    expect(completedMessages, hasLength(3));
    expect((completedMessages.last as Map<String, dynamic>)['body'],
        finalDraft.reply);
    final slaRows = await (await database.database)
        .query('sla_fallbacks', where: 'user_id = ?', whereArgs: [userId]);
    expect(slaRows.single['state'], 'completed');
  });

  test('delivery failures retain drafts for retry or reconciliation', () async {
    final root = await Directory.systemTemp.createTemp('delivery_retry_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    const userId = 'retry-customer';
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:$userId',
      customerName: userId,
      customerExternalId: userId,
      capturedAt: DateTime(2026, 9, 16, 10),
      messages: const [
        CapturedMessage(
          stableId: 'retry-message',
          direction: 'incoming',
          body: 'Need an answer',
          axPath: 'test',
        ),
      ],
    ));
    final pending = (await database.conversations()).single;
    const draft = AiDraft(
      reply: 'Retained answer',
      decision: 'draft',
      confidence: 1,
      riskLevel: 'low',
      model: 'test',
      usedRecordIds: [],
      actions: [],
      attachments: [],
      rawJson:
          '{"reply":"Retained answer","decision":"draft","confidence":1,"risk_level":"low","model":"test","used_record_ids":[],"actions":[],"attachments":[]}',
    );
    await database.saveDraft(pending.id, draft);
    await database.markGeneratedDraftDeliveryFailure(
      userId: userId,
      error: 'pre-click verification failed',
      deliveryUnknown: false,
      retryDelay: Duration.zero,
    );
    expect((await database.nextReadyDelivery())?.draft.reply, draft.reply);

    await database.markGeneratedDraftDeliveryFailure(
      userId: userId,
      error: 'send click was not confirmed',
      deliveryUnknown: true,
    );
    expect(await database.nextReadyDelivery(), isNull);
    final rows = await (await database.database)
        .query('generated_drafts', where: 'user_id = ?', whereArgs: [userId]);
    expect(rows, hasLength(1));
    expect(rows.single['delivery_state'], 'delivery_unknown');
  });

  test('SLA deadline uses the JD China-time message clock', () async {
    final root = await Directory.systemTemp.createTemp('sla_clock_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    // JD displayed 13:37:40 China time. On a UTC+6 workstation the OCR
    // parser may initially infer the previous local day because 13:37 looks
    // later than the 11:38 local capture clock.
    final capturedAt = DateTime.utc(2026, 9, 16, 5, 38, 52).toLocal();
    final observedClock = DateTime(2026, 9, 15, 13, 37, 40);
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:clock',
      customerName: 'clock',
      customerExternalId: 'clock',
      capturedAt: capturedAt,
      messages: [
        CapturedMessage(
          stableId: 'clock-message',
          direction: 'incoming',
          body: 'Please check this.',
          sentAt: observedClock,
          axPath: 'test',
        ),
      ],
    ));

    final job = await database.slaFallbackJob('clock');
    expect(job?.dueAt.toUtc(), DateTime.utc(2026, 9, 16, 5, 39, 40));
  });

  test('version 7 migration protects customers already waiting', () async {
    final root = await Directory.systemTemp.createTemp('sla_migration_test_');
    final path = '${root.path}/jd_automation.sqlite3';
    sqfliteFfiInit();
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE pending_customers (
            id INTEGER PRIMARY KEY,
            user_id TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            stable_key TEXT NOT NULL,
            newest_message_id TEXT NOT NULL,
            enqueued_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )''');
          await db.execute('''CREATE TABLE generated_drafts (
            user_id TEXT PRIMARY KEY,
            pending_id INTEGER NOT NULL,
            reply TEXT NOT NULL,
            model TEXT NOT NULL,
            raw_json TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL
          )''');
          await db.execute('''CREATE TABLE conversation_control (
            user_id TEXT PRIMARY KEY,
            state TEXT NOT NULL,
            resume_after_message_id TEXT,
            updated_at_ms INTEGER NOT NULL
          )''');
        },
      ),
    );
    const enqueuedAt = 1800000000000;
    await legacy.insert('pending_customers', {
      'user_id': 'waiting-at-upgrade',
      'display_name': 'Waiting customer',
      'stable_key': 'customer:waiting-at-upgrade',
      'newest_message_id': 'existing-message',
      'enqueued_at_ms': enqueuedAt,
      'updated_at_ms': enqueuedAt,
    });
    await legacy.close();

    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final db = await database.database;
    final slaRows = await db.query('sla_fallbacks');
    expect(slaRows, hasLength(1));
    expect(slaRows.single['message_id'], 'existing-message');
    expect(slaRows.single['due_at_ms'], enqueuedAt + 120000);
    expect(slaRows.single['state'], 'pending');

    final columns = await db.rawQuery('PRAGMA table_info(generated_drafts)');
    final names = columns.map((row) => row['name']).toSet();
    expect(
        names,
        containsAll(<String>{
          'delivery_state',
          'delivery_attempts',
          'retry_at_ms',
          'last_error',
        }));
  });

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

  test('ready replies can be delivered while another customer generates',
      () async {
    final root = await Directory.systemTemp.createTemp('fifo_delivery_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    CapturedConversation capture(String user, int sequence) =>
        CapturedConversation(
          stableKey: 'customer:$user',
          customerName: user,
          customerExternalId: user,
          capturedAt: DateTime.fromMillisecondsSinceEpoch(sequence),
          messages: [
            CapturedMessage(
              stableId: '$user-message',
              direction: 'incoming',
              body: 'Message from $user',
              axPath: 'test',
            ),
          ],
        );

    AiDraft draft(String user) => AiDraft(
          reply: 'Reply to $user',
          decision: 'draft',
          confidence: 1,
          riskLevel: 'low',
          model: 'test',
          usedRecordIds: const [],
          actions: const [],
          attachments: const [],
          rawJson:
              '{"reply":"Reply to $user","decision":"draft","confidence":1,"risk_level":"low","model":"test","used_record_ids":[],"actions":[],"attachments":[]}',
        );

    await database.saveCapture(capture('customer-a', 1));
    await database.saveCapture(capture('customer-b', 2));
    final pending = await database.conversations();
    final first = pending.firstWhere((item) => item.userId == 'customer-a');
    final second = pending.firstWhere((item) => item.userId == 'customer-b');

    // B finishes first, so its ready reply does not wait for A's generation.
    await database.saveDraft(second.id, draft('customer-b'));
    expect((await database.nextReadyDelivery())?.userId, 'customer-b');

    await database.saveDraft(first.id, draft('customer-a'));
    final deliveryA = await database.nextReadyDelivery();
    expect(deliveryA?.userId, 'customer-a');
    await database.markReplySent(
        userId: deliveryA!.userId, reply: deliveryA.draft.reply);

    final deliveryB = await database.nextReadyDelivery();
    expect(deliveryB?.userId, 'customer-b');
  });

  test('a pending generation does not block a ready reply', () async {
    final root = await Directory.systemTemp.createTemp('fifo_failure_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    CapturedConversation capture(String user, int sequence) =>
        CapturedConversation(
          stableKey: 'customer:$user',
          customerName: user,
          customerExternalId: user,
          capturedAt: DateTime.fromMillisecondsSinceEpoch(sequence),
          messages: [
            CapturedMessage(
                stableId: '$user-message',
                direction: 'incoming',
                body: user,
                axPath: 'test'),
          ],
        );
    const secondDraft = AiDraft(
      reply: 'Reply B',
      decision: 'draft',
      confidence: 1,
      riskLevel: 'low',
      model: 'test',
      usedRecordIds: [],
      actions: [],
      attachments: [],
      rawJson:
          '{"reply":"Reply B","decision":"draft","confidence":1,"risk_level":"low","model":"test","used_record_ids":[],"actions":[],"attachments":[]}',
    );

    await database.saveCapture(capture('customer-a', 1));
    await database.saveCapture(capture('customer-b', 2));
    final pending = await database.conversations();
    final second = pending.firstWhere((item) => item.userId == 'customer-b');
    await database.saveDraft(second.id, secondDraft);
    expect((await database.nextReadyDelivery())?.userId, 'customer-b');

    await database.abandonPendingCustomer('customer-a');
    expect((await database.nextReadyDelivery())?.userId, 'customer-b');
  });

  test('pending message identity changes when a later burst line arrives',
      () async {
    final root = await Directory.systemTemp.createTemp('burst_guard_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    CapturedConversation capture(String id, String body, int time) =>
        CapturedConversation(
          stableKey: 'customer:burst',
          customerName: 'burst',
          customerExternalId: 'burst',
          capturedAt: DateTime.fromMillisecondsSinceEpoch(time),
          messages: [
            CapturedMessage(
                stableId: id,
                direction: 'incoming',
                body: body,
                axPath: 'test'),
          ],
        );

    await database.saveCapture(capture('line-1', 'android', 1));
    expect(await database.pendingMessageId('burst'), 'line-1');

    await database.saveCapture(capture('line-2', 'over wifi', 2));
    expect(await database.pendingMessageId('burst'), 'line-2');
  });

  test('frozen image batch can be sent while later text stays pending',
      () async {
    final root = await Directory.systemTemp.createTemp('image_text_batch_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    CapturedConversation capture(CapturedMessage message, int time) =>
        CapturedConversation(
          stableKey: 'customer:buyer',
          customerName: 'buyer',
          customerExternalId: 'buyer',
          capturedAt: DateTime.fromMillisecondsSinceEpoch(time),
          messages: [message],
        );
    await database.saveCapture(capture(
        const CapturedMessage(
          stableId: 'image-1',
          direction: 'incoming',
          body: '[Customer sent an image]',
          axPath: 'test',
          media: [CapturedMedia(type: 'image', path: '/tmp/customer.png')],
        ),
        1));
    final pending = (await database.conversations()).single;
    // OCR sees the new text and the already saved image in one viewport.
    // The old image is last in this capture list, but must not rewind pending.
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:buyer',
      customerName: 'buyer',
      customerExternalId: 'buyer',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(2),
      messages: const [
        CapturedMessage(
          stableId: 'text-2',
          direction: 'incoming',
          body: 'What is this error?',
          axPath: 'test',
        ),
        CapturedMessage(
          stableId: 'image-1',
          direction: 'incoming',
          body: '[Customer sent an image]',
          axPath: 'test',
          media: [CapturedMedia(type: 'image', path: '/tmp/customer.png')],
        ),
      ],
    ));
    const draft = AiDraft(
      reply: 'Old image-only answer',
      decision: 'draft',
      confidence: 1,
      riskLevel: 'low',
      model: 'test',
      usedRecordIds: [],
      actions: [],
      attachments: [],
      rawJson: '{"reply":"Old image-only answer","decision":"draft",'
          '"confidence":1,"risk_level":"low","model":"test",'
          '"used_record_ids":[],"actions":[],"attachments":[]}',
    );
    expect(
        await database.saveDraft(pending.id, draft,
            expectedMessageId: 'image-1'),
        1);
    expect(await database.pendingMessageId('buyer'), 'text-2');
    expect(await database.hasUndeliveredDraft('buyer'), isTrue);
    expect((await database.nextReadyDelivery())?.draft.reply,
        'Old image-only answer');
    expect(await database.markReplySent(userId: 'buyer', reply: draft.reply),
        isTrue);
    expect(await database.answeredMessageId('buyer'), 'image-1');
    expect(await database.hasPendingUnanswered('buyer'), isTrue);
    final messages = ((await (await database.history)
            .read('buyer'))?['messages'] as List<Object?>? ??
        const []);
    expect(messages.map((message) => (message as Map<String, dynamic>)['id']),
        containsAll(['image-1', 'text-2']));
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
    expect(await database.hasPendingUnanswered('test-buyer'), isTrue);

    // An open ticket is informational. Codex keeps processing follow-up
    // messages until an operator explicitly starts contacting the customer.
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
    expect((await database.conversations()).single.userId, 'test-buyer');

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

  test('same customer text at a new timestamp is a new pending message',
      () async {
    final root = await Directory.systemTemp.createTemp('repeat_text_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final firstTime = DateTime.utc(2026, 9, 4, 5, 20, 5);
    CapturedConversation capture(String id, DateTime sentAt) =>
        CapturedConversation(
          stableKey: 'customer:repeat',
          customerName: 'buyer',
          customerExternalId: 'buyer',
          capturedAt: sentAt.add(const Duration(seconds: 3)),
          messages: [
            CapturedMessage(
              stableId: id,
              direction: 'incoming',
              body: 'do i need to add ink on that thermal printer',
              sentAt: sentAt,
              axPath: 'ocr',
            ),
          ],
        );

    await database.saveCapture(capture('first-question', firstTime));
    final secondTime = firstTime.add(const Duration(seconds: 32));
    await database.saveCapture(capture('repeated-question', secondTime));

    expect(await database.pendingMessageId('buyer'), 'repeated-question');
    final document = await (await database.history).read('buyer');
    expect(document!['messages'], hasLength(2));
  });

  test(
      'known generated reply below a late-captured question does not answer it',
      () async {
    final root = await Directory.systemTemp.createTemp('crossed_reply_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final start = DateTime.utc(2026, 9, 4, 5, 19, 51);
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:crossed',
      customerName: 'buyer',
      customerExternalId: 'buyer',
      capturedAt: start,
      messages: [
        CapturedMessage(
          stableId: 'try-message',
          direction: 'incoming',
          body: 'ok.. i will try',
          sentAt: start,
          axPath: 'ocr',
        ),
      ],
    ));
    final pending = (await database.conversations()).single;
    const reply =
        'Okay, please try it. If the paper still jams, let us know what happens.';
    await database.saveDraft(
        pending.id,
        const AiDraft(
          reply: reply,
          decision: 'draft',
          confidence: .99,
          riskLevel: 'low',
          model: 'test',
          usedRecordIds: [],
          actions: [],
          attachments: [],
          rawJson:
              '{"reply":"Okay, please try it. If the paper still jams, let us know what happens.","decision":"draft","confidence":0.99,"risk_level":"low","model":"test","used_record_ids":[],"actions":[],"attachments":[]}',
        ));
    await database.markReplySent(userId: 'buyer', reply: reply);

    final questionTime = start.add(const Duration(seconds: 14));
    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:crossed',
      customerName: 'buyer',
      customerExternalId: 'buyer',
      capturedAt: questionTime.add(const Duration(seconds: 5)),
      messages: [
        CapturedMessage(
          stableId: 'ink-question',
          direction: 'incoming',
          body: 'do i need to add ink on that thermal printer',
          sentAt: questionTime,
          axPath: 'ocr',
        ),
        CapturedMessage(
          stableId: 'visible-known-reply',
          direction: 'outgoing',
          body: reply,
          sentAt: questionTime.add(const Duration(seconds: 2)),
          axPath: 'ocr',
        ),
      ],
    ));

    expect(await database.pendingMessageId('buyer'), 'ink-question');
  });

  test('older seller OCR above a newer customer message keeps AI pending',
      () async {
    final root = await Directory.systemTemp.createTemp('ordered_scan_test_');
    final database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    final now = DateTime.utc(2026, 9, 4, 6, 25, 25);

    await database.saveCapture(CapturedConversation(
      stableKey: 'customer:ordered',
      customerName: 'buyer',
      customerExternalId: 'buyer',
      capturedAt: now,
      messages: [
        CapturedMessage(
          stableId: 'older-seller-ocr',
          direction: 'outgoing',
          body: 'A previously visible seller message',
          sentAt: now.subtract(const Duration(seconds: 39)),
          axPath: 'ocr',
        ),
        CapturedMessage(
          stableId: 'new-customer-question',
          direction: 'incoming',
          body: "isn't it your product?",
          sentAt: now.subtract(const Duration(seconds: 5)),
          axPath: 'ocr',
        ),
      ],
    ));

    expect(await database.pendingMessageId('buyer'), 'new-customer-question');
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
