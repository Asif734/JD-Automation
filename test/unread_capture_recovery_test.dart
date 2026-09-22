import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/unread_capture_recovery.dart';

void main() {
  test('relaxes after six seconds and holds before twenty', () {
    final start = DateTime.utc(2026, 9, 22, 8);
    final recovery = UnreadCaptureRecovery(
      customer: 'jd_customer',
      unreadEvidence: 12,
      detectedAt: start,
      knownIncomingIds: const {},
      knownOutgoingIds: const {},
    );

    expect(recovery.useRelaxedBodyOcr(start.add(const Duration(seconds: 5))),
        isFalse);
    expect(recovery.useRelaxedBodyOcr(start.add(const Duration(seconds: 6))),
        isTrue);
    expect(
        recovery.holdingDue(start.add(const Duration(seconds: 11))), isFalse);
    expect(recovery.holdingDue(start.add(const Duration(seconds: 12))), isTrue);
    recovery.holdingSent = true;
    recovery.holdingSentAt = start.add(const Duration(seconds: 16));
    expect(
        recovery.holdingDue(start.add(const Duration(seconds: 20))), isFalse);
    expect(recovery.resendDue(start.add(const Duration(seconds: 59))), isFalse);
    expect(recovery.resendDue(start.add(const Duration(seconds: 60))), isTrue);
    recovery.resendSent = true;
    expect(recovery.resendDue(start.add(const Duration(seconds: 90))), isFalse);
    recovery.lastCaptureAttemptAt = start.add(const Duration(seconds: 60));
    expect(recovery.captureRetryDue(start.add(const Duration(seconds: 67))),
        isFalse);
    expect(recovery.captureRetryDue(start.add(const Duration(seconds: 68))),
        isTrue);
  });

  test('late holding message does not cause immediate second message', () {
    final start = DateTime.utc(2026, 9, 22, 8);
    final recovery = UnreadCaptureRecovery(
      customer: 'jd_customer',
      unreadEvidence: 12,
      detectedAt: start,
      knownIncomingIds: const {},
      knownOutgoingIds: const {},
    )
      ..holdingSent = true
      ..holdingSentAt = start.add(const Duration(seconds: 65));

    expect(recovery.resendDueAt, start.add(const Duration(seconds: 85)));
    expect(recovery.resendDue(start.add(const Duration(seconds: 65))), isFalse);
    expect(recovery.resendDue(start.add(const Duration(seconds: 85))), isTrue);
  });
}
