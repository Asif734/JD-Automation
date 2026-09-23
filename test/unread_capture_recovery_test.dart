import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/unread_capture_recovery.dart';

void main() {
  test('an unread badge preserves the original 20 and 50 second deadlines', () {
    final observedAt = DateTime.utc(2026, 9, 22, 8, 58, 33);
    final detectedAt = UnreadCaptureRecovery.detectedFromBadge(observedAt, 85);
    expect(detectedAt, DateTime.utc(2026, 9, 22, 8, 57, 8));
    expect(detectedAt.add(UnreadCaptureRecovery.holdingAfter),
        DateTime.utc(2026, 9, 22, 8, 57, 28));
    expect(detectedAt.add(UnreadCaptureRecovery.resendAfter),
        DateTime.utc(2026, 9, 22, 8, 57, 58));
    expect(
        UnreadCaptureRecovery.detectedFromBadge(observedAt, 9999), observedAt);
  });

  test('a later badge starts a new turn without an observed clear state', () {
    final handledAt = DateTime.utc(2026, 9, 22, 10, 44, 36);
    final observedAt = DateTime.utc(2026, 9, 22, 10, 46, 18);
    expect(
        UnreadCaptureRecovery.badgeStartedAfterHandled(
            observedAt, 80, handledAt),
        isTrue);
    expect(
        UnreadCaptureRecovery.badgeStartedAfterHandled(
            observedAt, 110, handledAt),
        isFalse);
    expect(
        UnreadCaptureRecovery.badgeStartedAfterHandled(
            observedAt, null, handledAt),
        isFalse);
  });

  test('a late scan uses the actual manual reply time', () {
    final manualReplyAt = DateTime.utc(2026, 9, 23, 2, 33, 47);
    final observedAt = DateTime.utc(2026, 9, 23, 2, 37, 39);
    expect(
        UnreadCaptureRecovery.badgeStartedAfterHandled(
            observedAt, 120, manualReplyAt),
        isTrue);
  });

  test('visible history cannot resolve a newly detected unread turn', () {
    final detectedAt = DateTime.utc(2026, 9, 23, 2, 35, 39);
    final recovery = UnreadCaptureRecovery(
      customer: 'jd_customer',
      unreadEvidence: 12,
      detectedAt: detectedAt,
      knownIncomingIds: const {'known'},
      knownOutgoingIds: const {},
    );

    expect(
        recovery.acceptsIncoming(
          'old-message-captured-late',
          sentAt: DateTime.utc(2026, 9, 22, 4, 29, 23),
          capturedAt: detectedAt.add(const Duration(seconds: 20)),
        ),
        isFalse);
    expect(
        recovery.acceptsIncoming(
          'current-message',
          sentAt: detectedAt,
          capturedAt: detectedAt.add(const Duration(seconds: 2)),
        ),
        isTrue);
    expect(
        recovery.acceptsIncoming(
          'current-image-without-clock',
          capturedAt: detectedAt.add(const Duration(seconds: 2)),
        ),
        isTrue);
    expect(
        recovery.acceptsIncoming(
          'known',
          sentAt: detectedAt,
          capturedAt: detectedAt,
        ),
        isFalse);
  });

  test('late recovery keeps current captured messages out of its baseline', () {
    final detectedAt = DateTime.utc(2026, 9, 23, 3, 6, 53);
    final currentMessageAt = DateTime.utc(2026, 9, 23, 3, 7, 50);
    expect(
        currentMessageAt.isBefore(detectedAt
            .subtract(UnreadCaptureRecovery.detectedTurnClockTolerance)),
        isFalse);
    expect(
        DateTime.utc(2026, 9, 22, 4, 29, 23).isBefore(detectedAt
            .subtract(UnreadCaptureRecovery.detectedTurnClockTolerance)),
        isTrue);
  });

  test('relaxes and holds at twenty seconds, then asks again thirty later', () {
    final start = DateTime.utc(2026, 9, 22, 8);
    final recovery = UnreadCaptureRecovery(
      customer: 'jd_customer',
      unreadEvidence: 12,
      detectedAt: start,
      knownIncomingIds: const {},
      knownOutgoingIds: const {},
    );

    expect(recovery.useRelaxedBodyOcr(start.add(const Duration(seconds: 19))),
        isFalse);
    expect(recovery.useRelaxedBodyOcr(start.add(const Duration(seconds: 20))),
        isTrue);
    expect(
        recovery.holdingDue(start.add(const Duration(seconds: 19))), isFalse);
    expect(recovery.holdingDue(start.add(const Duration(seconds: 20))), isTrue);
    recovery.lastCaptureAttemptAt = start.add(const Duration(seconds: 5));
    expect(recovery.captureRetryDue(start.add(const Duration(seconds: 7))),
        isFalse);
    expect(recovery.captureRetryDue(start.add(const Duration(seconds: 13))),
        isTrue);
    recovery.holdingSent = true;
    recovery.holdingSentAt = start.add(const Duration(seconds: 20));
    expect(
        recovery.holdingDue(start.add(const Duration(seconds: 20))), isFalse);
    expect(recovery.resendDue(start.add(const Duration(seconds: 49))), isFalse);
    expect(recovery.resendDue(start.add(const Duration(seconds: 50))), isTrue);
    recovery.resendSent = true;
    expect(recovery.resendDue(start.add(const Duration(seconds: 90))), isFalse);
    recovery.lastCaptureAttemptAt = start.add(const Duration(seconds: 50));
    expect(recovery.captureRetryDue(start.add(const Duration(seconds: 57))),
        isFalse);
    expect(recovery.captureRetryDue(start.add(const Duration(seconds: 58))),
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

    expect(recovery.resendDueAt, start.add(const Duration(seconds: 95)));
    expect(recovery.resendDue(start.add(const Duration(seconds: 65))), isFalse);
    expect(recovery.resendDue(start.add(const Duration(seconds: 95))), isTrue);
  });

  test('low-confidence text requires two matching OCR scans', () {
    final recovery = UnreadCaptureRecovery(
      customer: 'jd_customer',
      unreadEvidence: 12,
      detectedAt: DateTime.utc(2026, 9, 22, 8),
      knownIncomingIds: const {},
      knownOutgoingIds: const {},
    );
    expect(recovery.confirmRelaxedBody('  random  text '), isFalse);
    expect(recovery.confirmRelaxedBody('other text'), isFalse);
    expect(recovery.confirmRelaxedBody('other   text'), isTrue);
  });
}
