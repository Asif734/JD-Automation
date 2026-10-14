import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/domain/capture_models.dart';
import 'package:jd_automation/platform/macos_capture_adapter.dart';
import 'package:jd_automation/runtime/serial_delivery_worker.dart';
import 'package:jd_automation/storage/capture_database.dart';
import 'package:jd_automation/storage/diagnostic_log.dart';

const _customers = [
  'jd_6c67c99371fa4',
  'jd_frqocwtljjob',
  '格志打印机贝贝',
  'jd_vpliogabtzoy',
  '上海世亦小关',
  'jd_41aeec7741d05',
];

AiDraft _draft(String owner, {String? reply}) => AiDraft.fromJson({
      'reply': reply ?? 'Offline reply for $owner',
      'decision': 'draft',
      'confidence': 1,
      'risk_level': 'low',
      'model': 'offline-test',
      'used_record_ids': [],
      'actions': [],
      'attachments': [],
    }, mediaBaseUrl: Uri());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jd.delivery.watchdog.offline-test');
  late Directory root;
  late CaptureDatabase database;
  late MacOSCaptureAdapter adapter;
  late DiagnosticLog log;
  late SerialDeliveryWorker<QueuedDelivery> worker;
  var enabled = true;
  var delivering = 0;
  var maxDelivering = 0;
  String? active;
  var fault = '';
  late Completer<Map<Object?, Object?>> lostResponse;
  final sent = <String>[];
  final failures = <Object>[];
  final workerErrors = <Object>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('jd-delivery-watchdog-');
    database = CaptureDatabase(storageRoot: root);
    log = DiagnosticLog(() async => Directory('${root.path}/logs'));
    adapter = MacOSCaptureAdapter(
      channel: channel,
      diagnosticLog: log,
      openResponseTimeout: const Duration(milliseconds: 60),
      sendResponseTimeout: const Duration(milliseconds: 60),
    );
    enabled = true;
    delivering = maxDelivering = 0;
    active = null;
    fault = '';
    lostResponse = Completer<Map<Object?, Object?>>();
    sent.clear();
    failures.clear();
    workerErrors.clear();
    // Read original incoming bodies when the existing archive is supplied;
    // every write below goes only to this test's temporary data root.
    final archive = Platform.environment['JD_REPLAY_DATA_ROOT'];
    for (final owner in _customers) {
      var body = 'Offline question for $owner';
      if (archive != null) {
        final original =
            jsonDecode(await File('$archive/$owner.json').readAsString())
                as Map;
        expect(original['user_id'], owner);
        body = (original['messages'] as List).cast<Map>().lastWhere((m) =>
            m['direction'] == 'incoming' &&
            (m['body'] as String? ?? '').isNotEmpty)['body'] as String;
      }
      await database.saveCapture(CapturedConversation(
        stableKey: 'customer:$owner',
        customerName: owner,
        customerExternalId: owner,
        verifiedCustomerId: owner,
        capturedAt: DateTime.now(),
        messages: [
          CapturedMessage(
              stableId: 'incoming:$owner',
              direction: 'incoming',
              body: body,
              sender: owner,
              axPath: 'offline',
              sentAt: DateTime.now())
        ],
      ));
      final pending = (await database.conversations())
          .singleWhere((c) => c.userId == owner);
      await database.saveDraft(pending.id, _draft(owner),
          expectedMessageId: 'incoming:$owner');
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      final owner = args['expectedCustomer'] as String;
      if (call.method == 'openConversation') {
        if (owner == _customers.first && fault == 'lost_open') {
          return lostResponse.future;
        }
        active = owner;
        return {'opened': true, 'customer': owner};
      }
      expect(call.method, 'sendDraftOnce');
      if (owner == _customers.first) {
        if (fault == 'lost_send') return lostResponse.future;
        if (fault == 'focus_changed') active = _customers[1];
        if (fault == 'wrong_ack') {
          return {
            'sent': true,
            'customer': _customers[1],
            'reply': args['reply']
          };
        }
      }
      if (active != owner) return {'error': 'expected_conversation_missing'};
      expect(args['reply'], _draft(owner).reply);
      sent.add(owner); // Mock acknowledgements only. No OS/JD click exists.
      return {'sent': true, 'customer': owner, 'reply': args['reply']};
    });
    worker = SerialDeliveryWorker<QueuedDelivery>(
      enabled: () => enabled,
      next: () => database.nextReadyDelivery(),
      deliver: (delivery) async {
        delivering++;
        if (delivering > maxDelivering) maxDelivering = delivering;
        try {
          if (!enabled ||
              !await database.isGeneratedDraftReadyForSend(
                  userId: delivery.userId,
                  reply: delivery.draft.reply,
                  expectedDelivery: delivery)) {
            return false;
          }
          await adapter.openConversation(delivery.userId);
          if (!enabled) return false;
          await adapter.sendDraftOnce(
              expectedCustomer: delivery.userId, reply: delivery.draft.reply);
          return await database.markReplySent(
              userId: delivery.userId,
              reply: delivery.draft.reply,
              expectedDelivery: delivery);
        } finally {
          delivering--;
        }
      },
      failed: (delivery, error, stack) async {
        failures.add(error);
        await database.markGeneratedDraftDeliveryFailure(
            userId: delivery.userId,
            error: error.toString(),
            retryDelay: const Duration(days: 1),
            expectedDelivery: delivery);
      },
      onError: (error, stack) => workerErrors.add(error),
    );
  });

  tearDown(() async {
    enabled = false;
    await adapter.close();
    await database.close();
    await log.flush();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  Future<void> retryFirst() async {
    await (await database.database).update(
        'generated_drafts', {'retry_at_ms': 0},
        where: 'user_id=?', whereArgs: [_customers.first]);
    await worker.request();
  }

  for (final scenario in [
    'lost_send',
    'lost_open',
    'focus_changed',
    'wrong_ack'
  ]) {
    test('$scenario retains its exact customer and lets the other five deliver',
        () async {
      fault = scenario;
      await Future.wait(List.generate(30, (_) => worker.request()));
      expect(workerErrors, isEmpty);
      expect(worker.isRunning, isFalse);
      expect(maxDelivering, 1);
      expect(failures, hasLength(1));
      expect(sent, _customers.skip(1).toList());
      expect(await database.hasUndeliveredDraft(_customers.first), isTrue);
      final retained = (await (await database.database).query(
              'generated_drafts',
              where: 'user_id=?',
              whereArgs: [_customers.first]))
          .single;
      expect(retained['batch_end_message_id'], 'incoming:${_customers.first}');
      expect(await database.answeredMessageId(_customers.first), isNull);
      for (final owner in _customers.skip(1)) {
        expect(await database.hasUndeliveredDraft(owner), isFalse);
        expect(await database.answeredMessageId(owner), 'incoming:$owner');
      }
      if (scenario == 'lost_send' || scenario == 'lost_open') {
        // A late, wrong-customer callback must not confirm any saved reply.
        lostResponse.complete({
          'sent': true,
          'opened': true,
          'customer': _customers[1],
          'reply': _draft(_customers.first).reply
        });
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(await database.hasUndeliveredDraft(_customers.first), isTrue);
        expect(
            (failures.single as PlatformException).code,
            scenario == 'lost_send'
                ? 'send_unconfirmed'
                : 'conversation_open_timeout');
        await log.flush();
        final records =
            (await Directory('${root.path}/logs').list().toList()).cast<File>();
        final events = (await records.single.readAsLines())
            .map((s) => jsonDecode(s) as Map);
        expect(
            events.any((e) =>
                e['operation'] ==
                    '${scenario == 'lost_send' ? 'sendDraftOnce' : 'openConversation'}.failed' &&
                e['expected_customer'] == _customers.first),
            isTrue);
      }
      fault = '';
      await retryFirst();
      expect(sent, [..._customers.skip(1), _customers.first]);
      expect(await database.hasUndeliveredDraft(_customers.first), isFalse);
      expect(await database.answeredMessageId(_customers.first),
          'incoming:${_customers.first}');
      expect(maxDelivering, 1);
    });
  }

  test('repeated failures never abandon the retained reply', () async {
    fault = 'focus_changed';
    await worker.request();
    for (var attempt = 0; attempt < 10; attempt++) {
      await retryFirst();
    }
    expect(failures, hasLength(11));
    expect(sent, _customers.skip(1).toList());
    expect(await database.hasUndeliveredDraft(_customers.first), isTrue);
    fault = '';
    await retryFirst();
    expect(await database.hasUndeliveredDraft(_customers.first), isFalse);
  });

  test('retained reply recovers from the durable database after restart',
      () async {
    fault = 'lost_send';
    await worker.request();
    await database.close();
    database = CaptureDatabase(storageRoot: root);
    fault = '';
    await retryFirst();
    expect(await database.answeredMessageId(_customers.first),
        'incoming:${_customers.first}');
    expect(sent, [..._customers.skip(1), _customers.first]);
  });

  test(
      'native timeout can be reconciled by the exact outgoing receipt without resending',
      () async {
    fault = 'lost_send';
    await worker.request();
    final owner = _customers.first;
    await database.saveCapture(CapturedConversation(
        stableKey: 'customer:$owner',
        customerName: owner,
        customerExternalId: owner,
        verifiedCustomerId: owner,
        capturedAt: DateTime.now(),
        messages: [
          CapturedMessage(
              stableId: 'receipt:$owner',
              direction: 'outgoing',
              body: _draft(owner).reply,
              axPath: 'offline',
              deliveryConfirmed: true,
              sentAt: DateTime.now())
        ]));
    expect(await database.hasUndeliveredDraft(owner), isFalse);
    fault = '';
    await worker.request();
    expect(sent, _customers.skip(1).toList());
    expect(await database.answeredMessageId(owner), 'incoming:$owner');
  });

  test('late failure or acknowledgement cannot consume a replacement batch',
      () async {
    final old = (await database.nextReadyDelivery())!;
    final owner = old.userId;
    await database.saveCapture(CapturedConversation(
        stableKey: 'customer:$owner',
        customerName: owner,
        customerExternalId: owner,
        verifiedCustomerId: owner,
        capturedAt: DateTime.now(),
        messages: [
          CapturedMessage(
              stableId: 'new:$owner',
              direction: 'incoming',
              body: 'A newer question',
              sender: owner,
              axPath: 'offline')
        ]));
    final pending =
        (await database.conversations()).singleWhere((c) => c.userId == owner);
    // Use the same reply to ensure owner+text alone cannot claim a newer batch.
    await database.saveDraft(pending.id, old.draft,
        expectedMessageId: 'new:$owner');
    await database.markGeneratedDraftDeliveryFailure(
        userId: owner, error: 'send_unconfirmed', expectedDelivery: old);
    final current = (await (await database.database)
            .query('generated_drafts', where: 'user_id=?', whereArgs: [owner]))
        .single;
    expect(current['delivery_state'], 'ready');
    expect(current['batch_end_message_id'], 'new:$owner');
    expect(
        await database.isGeneratedDraftReadyForSend(
            userId: owner, reply: old.draft.reply, expectedDelivery: old),
        isFalse);
    expect(
        await database.markReplySent(
            userId: owner, reply: old.draft.reply, expectedDelivery: old),
        isFalse);
    expect(await database.hasUndeliveredDraft(owner), isTrue);
    expect(await database.answeredMessageId(owner), isNull);
  });

  test('human-contacting queue head cannot spin or starve other customers',
      () async {
    await (await database.database).insert('conversation_control', {
      'user_id': _customers.first,
      'state': 'human_contacting',
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
    await worker.request();
    expect(sent, _customers.skip(1).toList());
    expect(await database.hasUndeliveredDraft(_customers.first), isTrue);
  });

  test('disabled automation never sends; resuming drains saved replies',
      () async {
    enabled = false;
    await worker.request();
    expect(sent, isEmpty);
    enabled = true;
    await worker.request();
    expect(sent, _customers);
  });
}
