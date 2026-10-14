import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/capture_coordinator.dart';
import 'package:jd_automation/domain/capture_models.dart';
import 'package:jd_automation/platform/macos_capture_adapter.dart';
import 'package:jd_automation/storage/capture_database.dart';
import 'package:jd_automation/storage/diagnostic_log.dart';

const customers = [
  'jd_6c67c99371fa4',
  'jd_frqocwtljjob',
  '格志打印机贝贝',
  'jd_vpliogabtzoy',
  '上海世亦小关',
  'jd_41aeec7741d05',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jd.isolation.offline-test');
  late Directory root;
  late CaptureDatabase database;
  late MacOSCaptureAdapter adapter;
  late CaptureCoordinator coordinator;
  late DiagnosticLog log;
  late StreamSubscription subscription;
  final rejected = <Object>[];
  var updates = 0;
  var nativeSendCalls = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('jd-six-customer-replay-');
    database = CaptureDatabase(storageRoot: root);
    log = DiagnosticLog(() async => Directory('${root.path}/logs'));
    adapter = MacOSCaptureAdapter(channel: channel, diagnosticLog: log);
    coordinator = CaptureCoordinator(adapter, database);
    rejected.clear();
    updates = 0;
    nativeSendCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'startCapture' || call.method == 'stopCapture') {
        return null;
      }
      if (call.method == 'sendDraftOnce') nativeSendCalls++;
      throw StateError(
          'Live UI operation prohibited in offline history replay: ${call.method}');
    });
    subscription = coordinator.updates
        .listen((_) => updates++, onError: (Object e) => rejected.add(e));
    await coordinator.start();
  });
  tearDown(() async {
    await coordinator.stop();
    await subscription.cancel();
    await adapter.close();
    await database.close();
    await log.flush();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  Future<void> inject(String owner, List<Map<String, Object?>> messages,
      {String? observed, String? name}) async {
    final done = Completer<void>();
    // This is the actual native-to-Flutter entry point, with the OS replaced
    // by a mock channel. There is no running JD app or model in this test.
    // ignore: deprecated_member_use
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(MethodCall('capture', {
              'stableKey': 'customer:$owner',
              'customerName': name ?? owner,
              'customerExternalId': owner,
              'verifiedCustomerId': observed ?? owner,
              'capturedAtMs': DateTime.now().millisecondsSinceEpoch,
              'messages': messages,
            })),
            (_) => done.complete());
    await done.future;
  }

  Future<void> drain(int count) async {
    final priorRejections = rejected.length;
    // This drains 600 durable writes, not a JD UI response deadline. Allow
    // slower fsync under a concurrent build without weakening count/ownership
    // assertions; actual rejected events still fail immediately.
    final until = DateTime.now().add(const Duration(minutes: 2));
    while (updates < count && DateTime.now().isBefore(until)) {
      expect(rejected, hasLength(priorRejections),
          reason: 'Valid replay events must not produce additional failures.');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(updates, greaterThanOrEqualTo(count));
  }

  test(
      'replays real JSON messages from all six customers with concurrent duplicates',
      () async {
    final archive = Platform.environment['JD_REPLAY_DATA_ROOT']!;
    final messagesByOwner = <String, List<Map<String, Object?>>>{};
    final bodiesByOwner = <String, Set<String>>{};
    var messageCount = 0;
    for (final owner in customers) {
      final document =
          jsonDecode(await File('$archive/$owner.json').readAsString())
              as Map<String, dynamic>;
      expect(document['user_id'], owner);
      final rows = (document['messages'] as List)
          .cast<Map<String, dynamic>>()
          .where((m) =>
              m['direction'] == 'incoming' &&
              (m['body'] as String? ?? '').isNotEmpty)
          .toList();
      final recent = rows.skip(max(0, rows.length - 80)).toList();
      expect(recent, isNotEmpty,
          reason: 'The replay must exercise every requested customer.');
      bodiesByOwner[owner] = recent.map((m) => m['body'] as String).toSet();
      messagesByOwner[owner] = [
        for (final m in recent)
          {
            'stableId': m['id'],
            'direction': 'incoming',
            'body': m['body'],
            'sender': m['sender'],
            'sentAtMs': DateTime.tryParse(m['sent_at']?.toString() ?? '')
                ?.millisecondsSinceEpoch,
            'axPath': 'history-replay',
          }
      ];
      messageCount += recent.length;
    }
    // Race startup/persistence, interleave customers, then replay exact old
    // observations in shuffled order. Duplicates must not create new owners.
    await Future.wait(customers.map((c) => inject(c, messagesByOwner[c]!)));
    await drain(7);
    final baseline = <String, int>{};
    for (final c in customers) {
      baseline[c] =
          ((await (await database.history).read(c))!['messages'] as List)
              .length;
    }
    final random = Random(20261013);
    for (var round = 0; round < 100; round++) {
      final order = [...customers]..shuffle(random);
      await Future.wait(
          order.map((c) => inject(c, [messagesByOwner[c]!.last])));
    }
    await drain(607);
    final pending = await database.conversations();
    expect(pending.map((c) => c.userId).toSet(), customers.toSet());
    for (final c in customers) {
      final document = (await (await database.history).read(c))!;
      expect(document['user_id'], c);
      final messages =
          (document['messages'] as List).cast<Map<String, dynamic>>();
      expect(messages.length, baseline[c]);
      expect(
          messages.every((m) => bodiesByOwner[c]!.contains(m['body'])), isTrue);
      final ids = messagesByOwner[c]!.map((m) => m['stableId']).toSet();
      expect(messages.every((m) => ids.contains(m['id'])), isTrue);
      expect(await database.pendingMessageId(c), messages.last['id']);
    }
    expect(rejected, isEmpty);
    expect(nativeSendCalls, 0);
    // Only counts are printed; customer message contents remain private.
    // ignore: avoid_print
    print(
        'Six-customer replay: $messageCount original incoming messages, 600 shuffled duplicate events, zero live sends, zero cross-customer writes.');
  },
      skip: Platform.environment['JD_REPLAY_DATA_ROOT'] == null
          ? 'Set JD_REPLAY_DATA_ROOT to a read-only archive of the six JSON histories.'
          : false,
      timeout: const Timeout(Duration(minutes: 3)));

  test(
      'rejects all 30 wrong-customer capture permutations and still accepts six valid events',
      () async {
    for (final owner in customers) {
      for (final other in customers.where((c) => c != owner)) {
        await inject(
            owner,
            [
              {
                'stableId': '$owner:bad',
                'direction': 'incoming',
                'body': 'wrong-owner'
              }
            ],
            observed: other);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rejected, hasLength(30));
    expect((await database.conversations()), isEmpty);
    for (final c in customers) {
      expect(await (await database.history).read(c), isNull);
      await inject(c, [
        {
          'stableId': '$c:good',
          'direction': 'incoming',
          'body': 'valid-owner:$c'
        }
      ]);
    }
    await drain(7);
    expect((await database.conversations()).map((c) => c.userId).toSet(),
        customers.toSet());
    expect(nativeSendCalls, 0);
  });

  test('similar IDs, missing proof, and truncated headers are rejected',
      () async {
    const owner = 'jd_41aeec7741d05';
    for (final observed in [
      'jd_4laeec7741d05',
      'jd_41aeec7741d0S',
      'jd_41aee…',
      '',
      'JD_41AEEC7741D05'
    ]) {
      await inject(owner, [], observed: observed);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(rejected, hasLength(5));
    expect(await (await database.history).read(owner), isNull);
  });

  test('foreign media and corrupted history ownership cannot be persisted',
      () async {
    final store = await database.history;
    final foreign = await store.saveMedia(
        userId: customers[1], filename: 'customer.png', bytes: [1, 2, 3]);
    await expectLater(
        () => store.appendCapture(CapturedConversation(
              stableKey: customers[0],
              customerName: customers[0],
              customerExternalId: customers[0],
              verifiedCustomerId: customers[0],
              capturedAt: DateTime.now(),
              messages: [
                CapturedMessage(
                    stableId: 'foreign',
                    direction: 'incoming',
                    body: 'video',
                    axPath: 'test',
                    media: [CapturedMedia(type: 'image', path: foreign)])
              ],
            )),
        throwsStateError);
    expect(await store.read(customers[0]), isNull);
    await File('${root.path}/${customers[0]}.json').writeAsString(jsonEncode({
      'user_id': customers[1],
      'messages': [],
    }));
    await expectLater(store.read(customers[0]), throwsStateError);
    expect(
        jsonDecode(await File('${root.path}/${customers[0]}.json')
            .readAsString())['user_id'],
        customers[1]);
  });

  test('persistent diagnostics retain exact exception without message text',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'stopCapture') return null;
      return {
        'error': 'conversation_not_found',
        'message': 'Exact customer was not found.'
      };
    });
    await expectLater(adapter.openConversation(customers.first),
        throwsA(isA<PlatformException>()));
    await log.flush();
    final files = await Directory('${root.path}/logs')
        .list()
        .where((e) => e is File)
        .toList();
    final events = (await File(files.single.path).readAsLines())
        .map((l) => jsonDecode(l) as Map)
        .toList();
    expect(events.last['error'], 'conversation_not_found');
    expect(events.last['expected_customer'], customers.first);
    expect(events.last.containsKey('reply'), isFalse);
    expect(events.last.containsKey('messages'), isFalse);
  });

  test(
      'six-customer sends require matching recipient and reply acknowledgements',
      () async {
    String? active;
    var simulatedClicks = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'stopCapture') return null;
      final args = call.arguments as Map;
      if (call.method == 'openConversation') {
        return {'opened': true, 'customer': active};
      }
      if (call.method == 'sendDraftOnce') {
        if (active != args['expectedCustomer']) {
          return {
            'error': 'expected_conversation_missing',
            'message': 'Active customer differs.'
          };
        }
        simulatedClicks++;
        return {'sent': true, 'customer': active, 'reply': args['reply']};
      }
      throw StateError('Unexpected mock method');
    });
    for (final owner in customers) {
      active = owner;
      await adapter.openConversation(owner);
      for (final other in customers.where((c) => c != owner)) {
        active =
            other; // Another customer takes focus after the open succeeded.
        await expectLater(
            adapter.sendDraftOnce(
                expectedCustomer: owner, reply: 'isolated test'),
            throwsA(isA<PlatformException>().having(
                (e) => e.code, 'code', 'expected_conversation_missing')));
      }
      active = owner;
      await adapter.sendDraftOnce(
          expectedCustomer: owner, reply: 'isolated test');
    }
    expect(simulatedClicks, 6); // Mock receipts only, never OS/UI sends.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'stopCapture') return null;
      return {'sent': true, 'customer': customers[1], 'reply': 'isolated test'};
    });
    await expectLater(
        adapter.sendDraftOnce(
            expectedCustomer: customers[0], reply: 'isolated test'),
        throwsA(isA<PlatformException>().having(
            (e) => e.code, 'code', 'send_confirmation_identity_mismatch')));
  });

  test(
      'sender labels cannot inherit a longer ID or an arbitrary timestamp suffix',
      () {
    for (final owner in customers) {
      expect(customerSenderLabelMatches('$owner 18:12:59', owner), isTrue);
      expect(customerSenderLabelMatches('${owner}x 18:12:59', owner), isFalse);
      expect(customerSenderLabelMatches('$owner wrong-user 18:12:59', owner),
          isFalse);
      expect(
          customerSenderLabelMatches(
              '${owner.substring(0, owner.length - 1)}…', owner),
          isFalse);
    }
  });

  test('verified owner rejects a foreign sender but accepts its own media',
      () async {
    final store = await database.history;
    await expectLater(
        () => store.appendCapture(CapturedConversation(
              stableKey: customers[0],
              customerName: customers[0],
              customerExternalId: customers[0],
              verifiedCustomerId: customers[0],
              capturedAt: DateTime.now(),
              messages: [
                CapturedMessage(
                    stableId: 'wrong-sender',
                    direction: 'incoming',
                    sender: customers[1],
                    body: 'foreign turn',
                    axPath: 'test')
              ],
            )),
        throwsStateError);
    expect(await store.read(customers[0]), isNull);
    final ownMedia = await store.saveMedia(
        userId: customers[0], filename: 'frame.jpg', bytes: [1, 2, 3]);
    await store.appendCapture(CapturedConversation(
      stableKey: customers[0],
      customerName: customers[0],
      customerExternalId: customers[0],
      verifiedCustomerId: customers[0],
      capturedAt: DateTime.now(),
      messages: [
        CapturedMessage(
            stableId: 'valid-media',
            direction: 'incoming',
            sender: customers[0],
            body: 'owned frame',
            axPath: 'test',
            media: [CapturedMedia(type: 'image', path: ownMedia)])
      ],
    ));
    expect((await store.read(customers[0]))!['messages'], hasLength(1));
  });
}
