import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/failed_send_retry_policy.dart';

void main() {
  bool canRun([String? busy]) => failedSendRetryCanRun(
        captureBusy: busy == 'capture',
        activeSignalBusy: busy == 'active-signal',
        unreadSignalBusy: busy == 'unread-signal',
        deliveryBusy: busy == 'delivery',
        priorityUiBusy: busy == 'priority-ui',
        transferBusy: busy == 'transfer',
        incomingRecoveryPending: busy == 'incoming-recovery',
        fallbackPending: busy == 'fallback',
        draftingPending: busy == 'drafting',
      );

  test('failed icon retry runs only during idle maintenance', () {
    expect(canRun(), isTrue);
  });
  for (final busy in [
    'capture',
    'active-signal',
    'unread-signal',
    'delivery',
    'priority-ui',
    'transfer',
    'incoming-recovery',
    'fallback',
    'drafting'
  ]) {
    test('$busy takes priority over an existing failed-message retry', () {
      expect(canRun(busy), isFalse);
    });
  }
}
