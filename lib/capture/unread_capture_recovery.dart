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

  static const relaxedOcrAfter = Duration(seconds: 20);
  static const holdingAfter = Duration(seconds: 20);
  static const resendAfter = Duration(seconds: 50);
  static const detectedTurnClockTolerance = Duration(seconds: 15);

  /// Use JD's elapsed unread badge when available, so a scan delayed by
  /// image/video work still inherits the customer's original deadline.
  static DateTime detectedFromBadge(DateTime observedAt, int? ageSeconds) =>
      ageSeconds != null && ageSeconds >= 0 && ageSeconds <= 600
          ? observedAt.subtract(Duration(seconds: ageSeconds))
          : observedAt;

  /// A new badge clock can appear before a poll ever sees the old badge clear.
  /// Allow for the one-second badge display and poll timing jitter.
  static bool badgeStartedAfterHandled(
      DateTime observedAt, int? ageSeconds, DateTime? handledAt) {
    if (handledAt == null ||
        ageSeconds == null ||
        ageSeconds < 0 ||
        ageSeconds > 600) {
      return false;
    }
    return detectedFromBadge(observedAt, ageSeconds)
        .isAfter(handledAt.add(const Duration(seconds: 2)));
  }

  final String customer;
  final int unreadEvidence;
  final DateTime detectedAt;
  final Set<String> knownIncomingIds;
  final Set<String> knownOutgoingIds;
  bool holdingSent = false;
  DateTime? holdingSentAt;
  bool resendSent = false;
  bool videoProcessing = false;
  bool noticeSending = false;
  // A sender-bounded screenshot was identified for this unread turn. Text
  // OCR alone cannot complete the turn until visual evidence for that block
  // is persisted. This prevents image pixels from being mistaken for the
  // customer's chat text and answered without the image.
  bool visualSnapshotRequired = false;
  DateTime? lastCaptureAttemptAt;
  String? latestIncomingSenderKey;
  String? _tentativeRelaxedBody;

  /// Visible chat history can be captured after an unread event even though
  /// those messages were sent earlier. Such a late capture must not resolve
  /// the current unread turn or cancel its fallback timer.
  bool acceptsIncoming(String messageId,
      {DateTime? sentAt, required DateTime capturedAt}) {
    if (knownIncomingIds.contains(messageId)) return false;
    if (sentAt != null) {
      return !sentAt.isBefore(detectedAt.subtract(detectedTurnClockTolerance));
    }
    return !capturedAt.isBefore(detectedAt);
  }

  bool acceptsRecoveredEvidence(
    String messageId, {
    DateTime? sentAt,
    required DateTime capturedAt,
    required bool hasVisualEvidence,
  }) {
    if (visualSnapshotRequired && !hasVisualEvidence) return false;
    return acceptsIncoming(
      messageId,
      sentAt: sentAt,
      capturedAt: capturedAt,
    );
  }

  /// A single low-confidence OCR pass may read JD controls as customer text.
  /// Require the same non-empty body on two separate scans before accepting it.
  bool confirmRelaxedBody(String body) {
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return false;
    if (_tentativeRelaxedBody == normalized) return true;
    _tentativeRelaxedBody = normalized;
    return false;
  }

  bool captureRetryDue(DateTime now) =>
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
      !now.isBefore(holdingSentAt!.add(const Duration(seconds: 30)));

  DateTime get resendDueAt {
    final original = detectedAt.add(resendAfter);
    final afterHolding = holdingSentAt?.add(const Duration(seconds: 30));
    return afterHolding != null && afterHolding.isAfter(original)
        ? afterHolding
        : original;
  }
}
