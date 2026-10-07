import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/domain/capture_models.dart';
import 'package:jd_automation/storage/capture_database.dart';

const _reply = 'Please download the official app from https://example.com/app';
const _draft = AiDraft(
  reply: _reply,
  decision: 'draft',
  confidence: 1,
  riskLevel: 'low',
  model: 'test',
  usedRecordIds: [],
  actions: [],
  attachments: [],
  rawJson:
      '{"reply":"Please download the official app from https://example.com/app","decision":"draft","confidence":1,"risk_level":"low","model":"test","used_record_ids":[],"actions":[],"attachments":[]}',
);

void main() {
  late CaptureDatabase database;
  late DateTime created;
  final firstAt = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
  CapturedConversation capture(List<CapturedMessage> messages) =>
      CapturedConversation(
        stableKey: 'customer:customer',
        customerName: 'customer',
        customerExternalId: 'customer',
        capturedAt: DateTime.now().toUtc(),
        messages: messages,
      );
  CapturedMessage outgoing(
          {bool receipt = true,
          DateTime? sentAt,
          String body = _reply,
          String id = 'observed'}) =>
      CapturedMessage(
        stableId: id,
        direction: 'outgoing',
        body: body,
        axPath: 'test',
        deliveryConfirmed: receipt,
        sentAt: sentAt ?? DateTime.now().toUtc(),
      );
  setUp(() async {
    final root = await Directory.systemTemp.createTemp('jd_confirmation_');
    database = CaptureDatabase(storageRoot: root);
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    await database.saveCapture(capture([
      CapturedMessage(
          stableId: 'first',
          direction: 'incoming',
          body: 'Where is the app?',
          sentAt: firstAt,
          axPath: 'test'),
    ]));
    final pending = (await database.conversations()).single;
    await database.saveDraft(pending.id, _draft, expectedMessageId: 'first');
    final row =
        (await (await database.database).query('generated_drafts')).single;
    created = DateTime.fromMillisecondsSinceEpoch(row['created_at_ms']! as int);
    await database.markGeneratedDraftDeliveryFailure(
        userId: 'customer', error: 'send_unconfirmed', deliveryUnknown: true);
    await database.saveCapture(capture([
      CapturedMessage(
          stableId: 'later',
          direction: 'incoming',
          body: 'Can this other app work?',
          sentAt: firstAt.add(const Duration(minutes: 1)),
          axPath: 'test'),
    ]));
  });

  test(
      'receipt releases old frozen draft but preserves newer unanswered question',
      () async {
    final observed = outgoing();
    await database.saveCapture(capture([observed]));
    expect(await database.hasUndeliveredDraft('customer'), isFalse);
    expect(await database.answeredMessageId('customer'), 'first');
    expect(await database.pendingMessageId('customer'), 'later');
    expect(await database.hasPendingUnanswered('customer'), isTrue);
    final history = await (await database.history).read('customer');
    final replies = (history!['messages'] as List)
        .cast<Map<String, dynamic>>()
        .where((message) => message['direction'] == 'outgoing')
        .toList();
    expect(replies, hasLength(1));
    expect(
        replies.single['sent_at'], observed.sentAt!.toUtc().toIso8601String());
  });

  test(
      'failed bubble without receipt cannot clear draft or answer later question',
      () async {
    await database.saveCapture(capture([outgoing(receipt: false)]));
    expect(await database.hasUndeliveredDraft('customer'), isTrue);
    expect(await database.nextReadyDelivery(), isNull);
    expect(await database.hasPendingUnanswered('customer'), isTrue);
    expect(await database.answeredMessageId('customer'), isNull);
  });

  test(
      'receipt appearing on an already stored bubble reconciles without duplicates',
      () async {
    final sentAt = DateTime.now().toUtc();
    await database
        .saveCapture(capture([outgoing(receipt: false, sentAt: sentAt)]));
    expect(await database.saveCapture(capture([outgoing(sentAt: sentAt)])), 1);
    expect(await database.hasUndeliveredDraft('customer'), isFalse);
    final history = await (await database.history).read('customer');
    expect(
        (history!['messages'] as List)
            .where((m) => m['direction'] == 'outgoing'),
        hasLength(1));
    expect(await database.pendingMessageId('customer'), 'later');
  });

  test('historical matching reply cannot confirm new uncertain send', () async {
    final message =
        outgoing(sentAt: created.subtract(const Duration(minutes: 10)));
    expect(
        await database.confirmObservedGeneratedDraft(
            userId: 'customer',
            message: message,
            capturedAt: DateTime.now().toUtc()),
        isFalse);
    expect(await database.hasUndeliveredDraft('customer'), isTrue);
  });

  test('stale reconciliation cannot consume a replacement ready draft',
      () async {
    final pending = (await database.conversations()).single;
    await database.saveDraft(pending.id, _draft, expectedMessageId: 'later');
    expect(
        await database.markReplySent(
            userId: 'customer',
            reply: _reply,
            recordHistory: false,
            expectedUnconfirmedCreatedAt: created.millisecondsSinceEpoch),
        isFalse);
    expect((await database.nextReadyDelivery())?.draft.reply, _reply);
    expect(await database.answeredMessageId('customer'), isNull);
  });

  test('incoming text or another customer cannot confirm a send', () async {
    final incoming = CapturedMessage(
        stableId: 'incoming-copy',
        direction: 'incoming',
        body: _reply,
        axPath: 'test',
        deliveryConfirmed: true,
        sentAt: DateTime.now().toUtc());
    expect(
        await database.confirmObservedGeneratedDraft(
            userId: 'customer',
            message: incoming,
            capturedAt: DateTime.now().toUtc()),
        isFalse);
    expect(
        await database.confirmObservedGeneratedDraft(
            userId: 'other-customer',
            message: outgoing(),
            capturedAt: DateTime.now().toUtc()),
        isFalse);
    expect(await database.hasUndeliveredDraft('customer'), isTrue);
  });

  test('manual 1 remains a real seller reply and releases stale AI work',
      () async {
    await database.saveCapture(capture([outgoing(body: '1', id: 'manual-1')]));
    expect(await database.hasUndeliveredDraft('customer'), isFalse);
    expect(await database.hasPendingUnanswered('customer'), isFalse);
    expect(await database.answeredMessageId('customer'), 'later');
  });
}
