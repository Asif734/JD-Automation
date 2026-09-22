/// A sidebar unread signal is not proof that the message body was captured.
/// Keep a separate clock until the newest incoming content is saved.
class UnreadCaptureRecovery {
  UnreadCaptureRecovery({
    required this.customer,
    required this.unreadEvidence,
    required this.detectedAt,
    required this.knownIncomingIds,
    required this.knownOutgoingIds,
  });

  static const relaxedOcrAfter = Duration(seconds: 6);
  // Fire early to leave time for a verified JD UI send before the 20s SLA.
  static const holdingAfter = Duration(seconds: 12);
  static const resendAfter = Duration(seconds: 60);

  final String customer;
  final int unreadEvidence;
  final DateTime detectedAt;
  final Set<String> knownIncomingIds;
  final Set<String> knownOutgoingIds;
  bool holdingSent = false;
  DateTime? holdingSentAt;
  bool resendSent = false;
  bool videoProcessing = false;
  DateTime? lastCaptureAttemptAt;

  bool captureRetryDue(DateTime now) =>
      !resendSent ||
      lastCaptureAttemptAt == null ||
      !now.isBefore(lastCaptureAttemptAt!.add(const Duration(seconds: 8)));

  bool useRelaxedBodyOcr(DateTime now) =>
      !now.isBefore(detectedAt.add(relaxedOcrAfter));

  bool holdingDue(DateTime now) =>
      !holdingSent && !now.isBefore(detectedAt.add(holdingAfter));

  bool resendDue(DateTime now) =>
      holdingSent &&
      holdingSentAt != null &&
      !resendSent &&
      !now.isBefore(detectedAt.add(resendAfter)) &&
      !now.isBefore(holdingSentAt!.add(const Duration(seconds: 20)));

  DateTime get resendDueAt {
    final original = detectedAt.add(resendAfter);
    final afterHolding = holdingSentAt?.add(const Duration(seconds: 20));
    return afterHolding != null && afterHolding.isAfter(original)
        ? afterHolding
        : original;
  }
}
