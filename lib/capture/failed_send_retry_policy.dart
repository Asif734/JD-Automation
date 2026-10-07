/// Retrying an existing JD icon is idle maintenance. Incoming detection,
/// unanswered-turn deadlines, drafting and normal delivery always go first.
bool failedSendRetryCanRun({
  required bool captureBusy,
  required bool activeSignalBusy,
  required bool unreadSignalBusy,
  required bool deliveryBusy,
  required bool priorityUiBusy,
  required bool transferBusy,
  required bool incomingRecoveryPending,
  required bool fallbackPending,
  required bool draftingPending,
}) =>
    !captureBusy &&
    !activeSignalBusy &&
    !unreadSignalBusy &&
    !deliveryBusy &&
    !priorityUiBusy &&
    !transferBusy &&
    !incomingRecoveryPending &&
    !fallbackPending &&
    !draftingPending;
