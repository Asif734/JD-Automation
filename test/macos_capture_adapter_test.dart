import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/platform/macos_capture_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('com.grozziie.jdAutomation/accessibility.identity-test');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('customer identity matching supports independent Unicode names', () {
    expect(customerIdentitiesMatch(' 上海思谆志科技 ', '上海思谆志科技'), isTrue);
    expect(customerIdentitiesMatch('CLFFD520', 'clffd520'), isTrue);
    expect(customerIdentitiesMatch('عميل', 'عميل'), isTrue);
    expect(customerIdentitiesMatch('গ্রাহক', 'গ্রাহক'), isTrue);
    expect(customerIdentitiesMatch('上海思谆志科技', 'jd_41aeec7741d05'), isFalse);
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
