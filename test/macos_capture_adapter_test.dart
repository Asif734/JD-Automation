import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/platform/macos_capture_adapter.dart';

void main() {
  test('background failed-send snapshots preserve identity and screenshot time',
      () {
    final time = DateTime.utc(2026, 10, 7, 6, 25, 10);
    final inspection = FailedSendInspection.fromMap({
      'customer': ' jd_41aeec7741d05 ',
      'capturedAtMs': time.millisecondsSinceEpoch,
      'candidates': [
        {'fingerprint': 'bubble', 'x': 20.0, 'y': 30.0}
      ],
    });
    expect(inspection.customer, 'jd_41aeec7741d05');
    expect(inspection.capturedAt, time);
    expect(inspection.candidates.single['fingerprint'], 'bubble');
    // Missing timestamp is stale, never silently replaced with now.
    expect(
        FailedSendInspection.fromMap({'customer': 'customer'})
            .capturedAt
            .millisecondsSinceEpoch,
        0);
  });

  const candidate = <String, Object?>{
    'x': 200.0,
    'y': 300.0,
    'fingerprint': 'verified-bubble',
    'windowId': 42,
  };
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('com.grozziie.jdAutomation/accessibility.identity-test');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('background retry events do not depend on an unfinished OCR request',
      () async {
    final ocrResponse = Completer<Map<String, Object?>>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      expect(call.method, 'inspectOCR');
      return ocrResponse.future;
    });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);
    final pendingOcr = adapter.inspectOcr(windowId: 42, fast: true);
    final event = adapter.failedSendInspections.first;
    final handled = Completer<void>();
    // Simulate a native-to-Flutter event; no UI action is invoked.
    // ignore: deprecated_member_use
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('failedSendCandidates', {
        'customer': 'jd_customer',
        'capturedAtMs': 1791354310000,
        'candidates': [candidate],
      })),
      (_) => handled.complete(),
    );
    final inspection = await event;
    await handled.future;
    expect(inspection.customer, 'jd_customer');
    expect(inspection.candidates.single['fingerprint'], 'verified-bubble');
    expect(ocrResponse.isCompleted, isFalse);
    ocrResponse.complete({
      'activeCustomerId': 'jd_customer',
      'capturedAtMs': 1791354310000,
      'observations': <Object?>[]
    });
    expect((await pendingOcr).activeCustomerId, 'jd_customer');
    expect(calls, 1); // No send, retry click, or extra screenshot request.
  });

  test('customer identity matching supports independent Unicode names', () {
    expect(customerIdentitiesMatch(' 上海思谆志科技 ', '上海思谆志科技'), isTrue);
    expect(customerIdentitiesMatch('CLFFD520', 'clffd520'), isTrue);
    expect(customerIdentitiesMatch('عميل', 'عميل'), isTrue);
    expect(customerIdentitiesMatch('গ্রাহক', 'গ্রাহক'), isTrue);
    expect(customerIdentitiesMatch('上海思谆志科技', 'jd_41aeec7741d05'), isFalse);
    expect(customerIdentitiesMatch('jd_4laeec7741d05', 'jd_41aeec7741d05'),
        isFalse);
  });

  test('failed message retry never requests a new send or inserts text',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'retryFailedOutgoingMessage');
      expect(call.arguments,
          {'expectedCustomer': 'customer', 'candidate': candidate});
      return {'retried': true};
    });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);
    expect(
        (await adapter.retryFailedOutgoingMessage(
            expectedCustomer: 'customer', candidate: candidate))['retried'],
        isTrue);
  });

  test('retry uses independently verified active customer identity', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openConversation') {
        return {'opened': true, 'customer': 'verified-customer'};
      }
      expect(call.method, 'retryFailedOutgoingMessage');
      expect(call.arguments,
          {'expectedCustomer': 'verified-customer', 'candidate': candidate});
      return {'retried': false};
    });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);
    await adapter.openConversation('row-name');
    expect(
        (await adapter.retryFailedOutgoingMessage(
            expectedCustomer: 'row-name', candidate: candidate))['retried'],
        isFalse);
  });

  test('keeps OCR row name while using separately verified active identity',
      () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      final arguments = call.arguments! as Map<Object?, Object?>;
      if (calls == 1) {
        expect(call.method, 'openConversation');
        expect(arguments['expectedCustomer'], 'jd_4laeec7741d05');
        return <String, Object?>{
          'opened': true,
          'customer': 'jd_41aeec7741d05',
        };
      }
      expect(call.method, 'sendDraftOnce');
      expect(arguments['expectedCustomer'], 'jd_41aeec7741d05');
      return <String, Object?>{'sent': true};
    });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);

    await adapter.openConversation('jd_4laeec7741d05');
    await adapter.sendDraftOnce(
      expectedCustomer: 'jd_4laeec7741d05',
      reply: 'test',
    );
    expect(calls, 2);
  });

  test('preserves a genuine l in the independently verified customer name',
      () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      final arguments = call.arguments! as Map<Object?, Object?>;
      expect(arguments['expectedCustomer'], 'jd_4laeec7741d05');
      if (call.method == 'openConversation') {
        return <String, Object?>{
          'opened': true,
          'customer': 'jd_4laeec7741d05',
        };
      }
      expect(call.method, 'sendDraftOnce');
      return <String, Object?>{'sent': true};
    });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);

    await adapter.openConversation('jd_4laeec7741d05');
    await adapter.sendDraftOnce(
      expectedCustomer: 'jd_4laeec7741d05',
      reply: 'test',
    );
    expect(calls, 2);
  });

  test('previews active accounts and transfers only the verified customer',
      () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      final arguments = (call.arguments as Map<Object?, Object?>?) ?? const {};
      switch (call.method) {
        case 'openConversation':
          expect(arguments['expectedCustomer'], 'jd_4laeec7741d05');
          return <String, Object?>{
            'opened': true,
            'customer': 'jd_41aeec7741d05',
          };
        case 'listActiveTransferAccounts':
          expect(arguments['expectedCustomer'], 'jd_41aeec7741d05');
          return <String, Object?>{
            'sourceAccount': '格志打印机小甘',
            'accounts': <String>['格志打印机小秦', '格志打印机小雨(小雨)'],
          };
        case 'transferConversation':
          expect(arguments['expectedCustomer'], 'jd_41aeec7741d05');
          expect(arguments['targetAccount'], '格志打印机小秦');
          return <String, Object?>{
            'transferred': true,
            'targetAccount': '格志打印机小秦',
          };
      }
      fail('Unexpected method ${call.method}');
    });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);

    await adapter.openConversation('jd_4laeec7741d05');
    final preview =
        await adapter.listActiveTransferAccounts('jd_4laeec7741d05');
    expect(preview.sourceAccount, '格志打印机小甘');
    expect(preview.activeAccounts, ['格志打印机小秦', '格志打印机小雨(小雨)']);
    final result = await adapter.transferConversation(
      expectedCustomer: 'jd_4laeec7741d05',
      targetAccount: preview.activeAccounts.first,
    );

    expect(result['transferred'], isTrue);
    expect(calls, 3);
  });

  test('cancels an open transfer selection without choosing an account',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'cancelTransferSelection');
      return <String, Object?>{'closed': true};
    });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);

    await adapter.cancelTransferSelection();
  });

  test('passes image time and preserves a verified JD cache source', () async {
    final expectedAt = DateTime.utc(2026, 9, 24, 2, 54, 58);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'captureImageRegion');
      final arguments = call.arguments! as Map<Object?, Object?>;
      expect(arguments['expectedCustomer'], '上海胜价信息技术');
      expect(arguments['expectedMediaAtMs'], expectedAt.millisecondsSinceEpoch);
      return <String, Object?>{
        'kind': 'image',
        'mimeType': 'image/png',
        'extension': 'png',
        'originalName': 'cached-original.png',
        'visualFingerprint': 'fc7cfdffff030000',
        'captureSource': 'jd-image-cache',
        'dataBase64': 'AQID',
      };
    });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);

    final image = await adapter.captureImageRegion(
      expectedCustomer: '上海胜价信息技术',
      windowId: 7,
      x: .2,
      y: .3,
      width: .2,
      height: .3,
      expectedMediaAt: expectedAt,
    );

    expect(image.captureSource, 'jd-image-cache');
    expect(image.originalName, 'cached-original.png');
    expect(image.bytes, <int>[1, 2, 3]);
  });

  test('checks the cache directly for a new customer turn', () async {
    final expectedAt = DateTime.utc(2026, 9, 24, 6, 0, 2);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'captureRecentCachedMedia');
      final arguments = call.arguments! as Map<Object?, Object?>;
      expect(arguments['expectedCustomer'], 'customer-a');
      expect(arguments['expectedMediaAtMs'], expectedAt.millisecondsSinceEpoch);
      expect(arguments['destinationDirectory'], '/private/media/videos');
      return <String, Object?>{
        'kind': 'image',
        'cacheKey': 'cache-key-1',
        'cacheModifiedAtMs':
            expectedAt.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
        'mimeType': 'image/png',
        'extension': 'png',
        'originalName': 'pale-image.png',
        'visualFingerprint': 'fc7cfdffff030000',
        'captureSource': 'jd-image-cache',
        'dataBase64': 'AQID',
      };
    });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);

    final media = await adapter.captureRecentCachedMedia(
      expectedCustomer: 'customer-a',
      expectedMediaAt: expectedAt,
      destinationDirectory: '/private/media/videos',
    );

    expect(media, isNotNull);
    expect(media!.cacheKey, 'cache-key-1');
    expect(media.image?.originalName, 'pale-image.png');
    expect(media.video, isNull);
  });

  test('waits for the requested customer before returning OCR', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'inspectOCR');
      calls++;
      return <String, Object?>{
        'windowId': 7,
        'activeCustomerId': calls == 1 ? 'jd_41aeec7741d05' : '上海思谆志科技',
        'chatRegion': <String, Object?>{'left': .35, 'right': .93},
        'capturedAtMs': 1,
        'observations': <Object?>[],
      };
    });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);

    final inspection = await adapter.inspectExpectedCustomer(
      windowId: 7,
      expectedCustomer: '上海思谆志科技',
      maximumAttempts: 2,
      retryDelay: Duration.zero,
    );

    expect(calls, 2);
    expect(inspection.activeCustomerId, '上海思谆志科技');
    expect(inspection.chatLeft, .35);
    expect(inspection.chatRight, .93);
  });

  test('rejects OCR when the row switch remains on another customer', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (_) async => <String, Object?>{
                  'windowId': 7,
                  'activeCustomerId': 'jd_41aeec7741d05',
                  'capturedAtMs': 1,
                  'observations': <Object?>[],
                });
    final adapter = MacOSCaptureAdapter(channel: channel);
    addTearDown(adapter.close);

    expect(
      () => adapter.inspectExpectedCustomer(
        windowId: 7,
        expectedCustomer: '上海思谆志科技',
        maximumAttempts: 2,
        retryDelay: Duration.zero,
      ),
      throwsA(isA<PlatformException>().having(
          (error) => error.code, 'code', 'customer_switch_not_verified')),
    );
  });
}
