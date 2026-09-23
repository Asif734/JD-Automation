import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

import 'capture/capture_coordinator.dart';
import 'capture/ocr_capture_extractor.dart';
import 'capture/ocr_image_candidate_selector.dart';
import 'capture/unread_capture_recovery.dart';
import 'capture/video_audio_extractor.dart';
import 'capture/video_frame_extractor.dart';
import 'codex/codex_reply_service.dart';
import 'codex/holding_replies.dart';
import 'codex/local_reply_router.dart';
import 'domain/capture_models.dart';
import 'platform/macos_capture_adapter.dart';
import 'storage/capture_database.dart';

typedef _RunVideoProcessingUnlocked = Future<CapturedMessage?> Function(
    Future<CapturedMessage?> Function() work);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JdAutomationApp());
}

class JdAutomationApp extends StatelessWidget {
  const JdAutomationApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'JD Automation',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xfff26b21),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfffaf8f6),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
        ),
        home: const CaptureHome(),
      );
}

class CaptureHome extends StatefulWidget {
  const CaptureHome({super.key});

  @override
  State<CaptureHome> createState() => _CaptureHomeState();
}

class _CaptureHomeState extends State<CaptureHome> {
  // Covers native window capture, Apple Vision recognition, and JD UI delays.
  static const _captureOperationTimeout = Duration(seconds: 90);
  static const _unreadOperationTimeout = Duration(seconds: 12);
  // A holding message must not sit behind a full 90-second OCR/media pass.
  static const _fallbackInspectionTimeout = Duration(seconds: 4);
  static const _scanInterval = Duration(seconds: 2);
  static const _batchCollectionWindow = Duration(milliseconds: 2500);
  static const _draftFailureRetryDelay = Duration(seconds: 10);
  static const _deliveryFailureRetryDelay = Duration(seconds: 10);
  late final MacOSCaptureAdapter _adapter;
  late final CaptureCoordinator _coordinator;
  late final CaptureDatabase _database;
  StreamSubscription? _updateSubscription;
  StreamSubscription? _diagnosticSubscription;
  List<ConversationSummary> _conversations = const [];
  Map<String, Object?> _status = const {};
  String _diagnostics = 'No AX inspection yet.';
  Object? _error;
  Map<String, HumanReviewTicket> _tickets = const {};
  OcrInspection? _ocrInspection;
  bool _autoCaptureRunning = false;
  bool _autoCaptureStarting = false;
  bool _autoCaptureBusy = false;
  Timer? _autoCaptureTimer;
  Timer? _unreadSignalTimer;
  Timer? _activeChatSignalTimer;
  bool _unreadSignalBusy = false;
  bool _activeChatSignalBusy = false;
  final Map<String, Timer> _draftRetryTimers = {};
  final Map<String, Timer> _batchCollectionTimers = {};
  final Map<String, Timer> _slaFallbackTimers = {};
  Timer? _deliveryRetryTimer;
  final Set<String> _draftQueue = {};
  // Each active customer owns a separate Codex CLI turn. Twenty
  // workers let the normal multi-chat workload generate concurrently without
  // launching an unbounded number of local model processes.
  static const int _maxConcurrentDraftWorkers = 20;
  final Set<String> _activeDraftUsers = {};
  final Map<String, CodexGenerationCancellation> _activeDraftCancellations = {};
  final Map<String, String> _activeDraftMessageIds = {};
  Future<void> _jdUiTail = Future<void>.value();
  bool _deliveryWorkerRunning = false;
  bool _deliveryRequested = false;
  final Map<String, int> _processingUnreadEvidence = {};
  final Map<String, int> _handledUnreadEvidence = {};
  final Map<String, DateTime> _handledUnreadAt = {};
  final Map<String, String> _handledIncomingSenderKeys = {};
  final Map<String, DateTime> _lastUnreadProbeAt = {};
  final Map<String, UnreadCaptureRecovery> _unreadRecovery = {};
  final Set<String> _startingUnreadRecovery = {};
  final Map<String, Timer> _unreadHoldingTimers = {};
  final Map<String, Timer> _unreadResendTimers = {};
  final Set<String> _visibleTransferWelcomes = {};
  String _visibleMediaTrace = 'visible image candidates=0, saved=0';

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _adapter = MacOSCaptureAdapter();
      _database = CaptureDatabase();
      _coordinator = CaptureCoordinator(_adapter, _database);
      _updateSubscription = _coordinator.updates.listen(
        (value) {
          setState(() => _conversations = value);
          _refreshTickets();
        },
        onError: (Object error) => setState(() => _error = error),
      );
      _diagnosticSubscription = _adapter.diagnostics.listen(
        (value) => setState(() =>
            _diagnostics = const JsonEncoder.withIndent('  ').convert(value)),
      );
      _refreshStatus();
      _refreshTickets();
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _adapter.status();
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _refreshTickets() async {
    try {
      await _database.improveGenericTicketReasons();
      final tickets = await _database.humanReviewTickets();
      if (!mounted) return;
      setState(() => _tickets = {
            for (final ticket in tickets)
              if (ticket.status != 'resolved' && ticket.status != 'cancelled')
                ticket.conversationId: ticket,
          });
    } catch (_) {
      // Capture remains available if local ticket storage is unavailable.
    }
  }

  Future<void> _markContacting(HumanReviewTicket ticket) async {
    try {
      _finishUnreadRecovery(ticket.conversationId);
      _draftRetryTimers.remove(ticket.conversationId)?.cancel();
      _slaFallbackTimers.remove(ticket.conversationId)?.cancel();
      _draftQueue.remove(ticket.conversationId);
      await _database.markTicketContacting(ticket.id);
      await _coordinator.refresh();
      await _refreshTickets();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _markContacted(HumanReviewTicket ticket) async {
    try {
      // Snapshot the human-handled chat before reopening AI eligibility. This
      // records both the customer's existing question and a manual seller
      // reply while the conversation is still in human_contacting state.
      final windows = await _adapter.listOcrWindows();
      if (windows.isEmpty) {
        throw StateError(
            'Keep the JD conversation visible before marking it Contacted.');
      }
      final reception = windows.firstWhere(
          (window) => window.title.contains('咚咚融合工作台'),
          orElse: () => windows.first);
      final inspection =
          await _adapter.inspectOcr(windowId: reception.windowId);
      if (inspection.activeCustomerId?.trim() != ticket.conversationId) {
        throw StateError('Open ${ticket.conversationId} in JD before marking '
            'the ticket Contacted. The current chat was not changed.');
      }
      final baseline = const OcrCaptureExtractor().analyze(inspection).capture;
      if (baseline == null) {
        throw StateError('The visible human-handled conversation could not be '
            'verified. Keep it open and try Contacted again.');
      }
      await _database.saveCapture(baseline);
      await _database.markTicketContacted(ticket.id);
      await _coordinator.refresh();
      await _refreshTickets();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _start() async {
    if (_autoCaptureStarting) return;
    if (_autoCaptureRunning) {
      _autoCaptureTimer?.cancel();
      _unreadSignalTimer?.cancel();
      _activeChatSignalTimer?.cancel();
      for (final timer in _unreadHoldingTimers.values) {
        timer.cancel();
      }
      for (final timer in _unreadResendTimers.values) {
        timer.cancel();
      }
      setState(() => _autoCaptureRunning = false);
      return;
    }
    setState(() {
      _autoCaptureStarting = true;
      _error = null;
      _diagnostics = 'Opening the JD reception window…';
    });
    try {
      await _adapter
          .ensureReceptionWindow(allowActivation: true)
          .timeout(_captureOperationTimeout);
    } catch (error) {
      if (mounted) setState(() => _error = error);
      return;
    } finally {
      if (mounted) setState(() => _autoCaptureStarting = false);
    }
    if (!mounted) return;
    setState(() {
      _autoCaptureRunning = true;
      _error = null;
      _diagnostics =
          'Automatic OCR capture started. The sidebar is checked every 2 seconds; saved customer evidence is queued for drafting immediately.';
    });
    _autoCaptureTimer =
        Timer.periodic(_scanInterval, (_) => unawaited(_runAutoCaptureCycle()));
    // This read-only sidebar poll is intentionally independent of the slower
    // OCR/media capture cycle. A busy video extraction cannot prevent the
    // unread clock from starting for another customer.
    _unreadSignalTimer =
        Timer.periodic(_scanInterval, (_) => unawaited(_pollUnreadSignals()));
    _activeChatSignalTimer = Timer.periodic(
        const Duration(seconds: 3), (_) => unawaited(_pollActiveChatSignal()));
    unawaited(_pollUnreadSignals());
    unawaited(_pollActiveChatSignal());
    for (final recovery in _unreadRecovery.values) {
      _armUnreadRecoveryTimers(recovery);
    }
    unawaited(_recoverAutomationQueues());
    unawaited(_runAutoCaptureCycle());
  }

  Future<void> _recoverAutomationQueues() async {
    final pending = await _database.conversations();
    for (final conversation in pending) {
      _scheduleDraftGeneration(conversation.userId, newEvidence: true);
    }
    for (final job in await _database.pendingSlaFallbackJobs()) {
      _armSlaFallback(job);
    }
    _requestDelivery();
  }

  static const _uncapturedHoldingReply = '请稍等，我正在核对您刚发来的消息。';
  static const _uncapturedResendReply =
      '抱歉，我这边暂时没能看清您刚才发送的内容。方便您再描述一下遇到的问题，或重新发送图片、视频吗？我会继续帮您查看。';

  bool _isOwnHoldingReply(String? body) =>
      body == _uncapturedHoldingReply || chineseHoldingReplies.contains(body);

  OcrExtractionAttempt _analyzeUnreadInspection(
      OcrInspection inspection, UnreadCaptureRecovery? recovery) {
    final strict = const OcrCaptureExtractor().analyze(inspection);
    if (recovery?.useRelaxedBodyOcr(DateTime.now()) != true) return strict;
    final relaxed = const OcrCaptureExtractor(bodyConfidenceThreshold: 0.30)
        .analyze(inspection);
    final latest = relaxed.capture?.messages.reversed
        .where((message) => message.direction == 'incoming')
        .firstOrNull;
    if (latest == null ||
        recovery!.knownIncomingIds.contains(latest.stableId)) {
      return relaxed;
    }
    final strictIds = strict.capture?.messages
            .where((message) => message.direction == 'incoming')
            .map((message) => message.stableId)
            .toSet() ??
        const <String>{};
    if (strictIds.contains(latest.stableId) ||
        recovery.confirmRelaxedBody(latest.body)) {
      return relaxed;
    }
    return strict;
  }

  Future<void> _beginUnreadRecovery(String customer, int evidence,
      {DateTime? detectedAt}) async {
    if (_unreadRecovery.containsKey(customer) ||
        !_startingUnreadRecovery.add(customer)) {
      return;
    }
    try {
      final document = await (await _database.history).read(customer);
      final messages = (document?['messages'] as List<Object?>? ?? const [])
          .whereType<Map<String, dynamic>>();
      final eventAt = detectedAt ?? DateTime.now();
      DateTime? messageAt(Map<String, dynamic> message) =>
          DateTime.tryParse(message['sent_at']?.toString() ?? '') ??
          DateTime.tryParse(message['captured_at']?.toString() ?? '');
      final recovery = UnreadCaptureRecovery(
        customer: customer,
        unreadEvidence: evidence,
        detectedAt: eventAt,
        knownIncomingIds: messages
            .where((message) =>
                message['direction'] == 'incoming' &&
                (messageAt(message)?.isBefore(eventAt.subtract(
                        UnreadCaptureRecovery.detectedTurnClockTolerance)) ??
                    false))
            .map((message) => message['id']?.toString() ?? '')
            .toSet(),
        knownOutgoingIds: messages
            .where((message) =>
                message['direction'] == 'outgoing' &&
                (messageAt(message)?.isBefore(eventAt) ?? false))
            .map((message) => message['id']?.toString() ?? '')
            .toSet(),
      );
      _unreadRecovery[customer] = recovery;
      _armUnreadRecoveryTimers(recovery);
    } finally {
      _startingUnreadRecovery.remove(customer);
    }
  }

  DateTime _unreadDetectedAt(QianniuConversationRow row) {
    return UnreadCaptureRecovery.detectedFromBadge(
        DateTime.now(), row.unreadAgeSeconds);
  }

  void _refreshHandledUnread(QianniuConversationRow row) {
    if (!row.unread ||
        UnreadCaptureRecovery.badgeStartedAfterHandled(DateTime.now(),
            row.unreadAgeSeconds, _handledUnreadAt[row.customer])) {
      _handledUnreadEvidence.remove(row.customer);
      _handledUnreadAt.remove(row.customer);
    }
  }

  Future<void> _pollUnreadSignals() async {
    if (!_autoCaptureRunning || _unreadSignalBusy) return;
    _unreadSignalBusy = true;
    try {
      final rows = await _adapter
          .listConversationRows()
          .timeout(_unreadOperationTimeout);
      for (final row in rows) {
        _refreshHandledUnread(row);
        if (!row.unread) {
          continue;
        }
        if (_unreadRecovery.containsKey(row.customer) ||
            _handledUnreadEvidence.containsKey(row.customer) ||
            await _database.isHumanContacting(row.customer)) {
          continue;
        }
        await _beginUnreadRecovery(row.customer, row.unreadEvidence,
            detectedAt: _unreadDetectedAt(row));
      }
    } catch (_) {
      // The capture cycle continues to inspect the active chat even if a
      // transient sidebar read fails. The next signal poll retries.
    } finally {
      _unreadSignalBusy = false;
    }
  }

  /// A selected JD row may not expose an unread flag. Observe its verified
  /// sender clock independently of the slow full capture/media cycle so the
  /// 20-second deadline starts even when content extraction fails.
  Future<void> _pollActiveChatSignal() async {
    if (!_autoCaptureRunning || _activeChatSignalBusy) return;
    _activeChatSignalBusy = true;
    try {
      final windows =
          await _adapter.listOcrWindows().timeout(_unreadOperationTimeout);
      if (windows.isEmpty) return;
      final reception = windows.firstWhere(
          (window) => window.title.contains('咚咚融合工作台'),
          orElse: () => windows.first);
      final inspection = await _adapter
          .inspectOcr(windowId: reception.windowId, fast: true)
          .timeout(_unreadOperationTimeout);
      final customer = inspection.activeCustomerId?.trim();
      if (customer == null ||
          customer.isEmpty ||
          await _database.isHumanContacting(customer)) {
        return;
      }
      final extraction = const OcrCaptureExtractor().analyze(inspection);
      final senderKey = extraction.latestIncomingSenderKey;
      final incomingAt = extraction.latestIncomingSentAt;
      if (!extraction.latestVisibleSenderIsIncoming ||
          senderKey == null ||
          incomingAt == null ||
          incomingAt.isBefore(
              inspection.capturedAt.subtract(const Duration(minutes: 10))) ||
          incomingAt
              .isAfter(inspection.capturedAt.add(const Duration(minutes: 1))) ||
          _handledIncomingSenderKeys[customer] == senderKey) {
        return;
      }
      final recovery = _unreadRecovery[customer];
      if (recovery != null) {
        recovery.latestIncomingSenderKey = senderKey;
        return;
      }
      await _beginUnreadRecovery(customer, 0, detectedAt: incomingAt);
      _unreadRecovery[customer]?.latestIncomingSenderKey = senderKey;
    } catch (_) {
      // The full capture and sidebar signal paths remain available.
    } finally {
      _activeChatSignalBusy = false;
    }
  }

  void _armUnreadRecoveryTimers(UnreadCaptureRecovery recovery) {
    final customer = recovery.customer;
    _unreadHoldingTimers.remove(customer)?.cancel();
    _unreadResendTimers.remove(customer)?.cancel();
    final now = DateTime.now();
    if (!recovery.holdingSent) {
      final due = recovery.detectedAt.add(UnreadCaptureRecovery.holdingAfter);
      _unreadHoldingTimers[customer] = Timer(
        due.isAfter(now) ? due.difference(now) : Duration.zero,
        () => unawaited(_sendUnreadRecoveryNotice(recovery, resend: false)),
      );
    }
  }

  void _finishUnreadRecovery(String customer, {DateTime? handledAt}) {
    final recovery = _unreadRecovery.remove(customer);
    _unreadHoldingTimers.remove(customer)?.cancel();
    _unreadResendTimers.remove(customer)?.cancel();
    if (recovery != null) {
      _handledUnreadEvidence[customer] = recovery.unreadEvidence;
      _handledUnreadAt[customer] = handledAt ?? DateTime.now();
      _processingUnreadEvidence[customer] = recovery.unreadEvidence;
      if (recovery.latestIncomingSenderKey case final senderKey?) {
        _handledIncomingSenderKeys[customer] = senderKey;
      }
    }
  }

  Future<bool> _hasRecoveredIncoming(UnreadCaptureRecovery recovery) async {
    final document = await (await _database.history).read(recovery.customer);
    final messages = (document?['messages'] as List<Object?>? ?? const [])
        .whereType<Map<String, dynamic>>();
    return messages.any((message) {
      if (message['direction'] != 'incoming') return false;
      final capturedAt =
          DateTime.tryParse(message['captured_at']?.toString() ?? '');
      if (capturedAt == null) return false;
      return recovery.acceptsIncoming(
        message['id']?.toString() ?? '',
        sentAt: DateTime.tryParse(message['sent_at']?.toString() ?? ''),
        capturedAt: capturedAt,
      );
    });
  }

  Future<DateTime?> _newOutgoingAt(UnreadCaptureRecovery recovery) async {
    final document = await (await _database.history).read(recovery.customer);
    final messages = (document?['messages'] as List<Object?>? ?? const [])
        .whereType<Map<String, dynamic>>();
    DateTime? newest;
    for (final message in messages) {
      if (message['direction'] != 'outgoing' ||
          message['source'] == 'sla_fallback' ||
          recovery.knownOutgoingIds.contains(message['id']?.toString() ?? '') ||
          message['body'] == _uncapturedHoldingReply ||
          message['body'] == _uncapturedResendReply) {
        continue;
      }
      final sentAt = DateTime.tryParse(message['sent_at']?.toString() ?? '') ??
          DateTime.tryParse(message['captured_at']?.toString() ?? '');
      if (sentAt == null || sentAt.isBefore(recovery.detectedAt)) continue;
      if (newest == null || sentAt.isAfter(newest)) newest = sentAt;
    }
    return newest;
  }

  Future<DateTime?> _holdingSentSinceRecovery(
      UnreadCaptureRecovery recovery) async {
    final document = await (await _database.history).read(recovery.customer);
    final messages = (document?['messages'] as List<Object?>? ?? const [])
        .whereType<Map<String, dynamic>>();
    DateTime? newest;
    for (final message in messages) {
      if (message['direction'] != 'outgoing' ||
          message['source'] != 'sla_fallback') {
        continue;
      }
      final sentAt = DateTime.tryParse(message['sent_at']?.toString() ?? '');
      if (sentAt == null ||
          sentAt.isBefore(recovery.detectedAt
              .subtract(UnreadCaptureRecovery.detectedTurnClockTolerance))) {
        continue;
      }
      if (newest == null || sentAt.isAfter(newest)) newest = sentAt;
    }
    return newest;
  }

  Future<void> _sendUnreadRecoveryNotice(UnreadCaptureRecovery recovery,
      {required bool resend}) async {
    if (!_autoCaptureRunning ||
        !identical(_unreadRecovery[recovery.customer], recovery) ||
        recovery.noticeSending) {
      return;
    }
    recovery.noticeSending = true;
    try {
      await _withFallbackPriority(() async {
        if (!identical(_unreadRecovery[recovery.customer], recovery)) return;
        if (await _database.isHumanContacting(recovery.customer)) {
          _finishUnreadRecovery(recovery.customer);
          return;
        }
        if (await _newOutgoingAt(recovery) case final sentAt?) {
          _finishUnreadRecovery(recovery.customer, handledAt: sentAt);
          return;
        }
        if (await _holdingSentSinceRecovery(recovery) case final sentAt?) {
          recovery.holdingSent = true;
          recovery.holdingSentAt = sentAt;
          _finishUnreadRecovery(recovery.customer, handledAt: sentAt);
          return;
        }
        if (await _hasRecoveredIncoming(recovery)) {
          if (recovery.holdingSentAt case final sentAt?) {
            await _database.acknowledgeUncapturedHolding(
                userId: recovery.customer, sentAt: sentAt);
            _slaFallbackTimers.remove(recovery.customer)?.cancel();
          }
          _finishUnreadRecovery(recovery.customer);
          _scheduleDraftGeneration(recovery.customer, newEvidence: false);
          return;
        }
        if (await _database.hasActiveSlaFallback(recovery.customer)) {
          // OCR already captured this turn. Its durable SLA row owns the only
          // holding message and draft generation; never race a second send.
          _finishUnreadRecovery(recovery.customer);
          unawaited(_scheduleSlaFallback(recovery.customer));
          _scheduleDraftGeneration(recovery.customer, newEvidence: false);
          return;
        }
        final now = DateTime.now();
        if (resend ? !recovery.resendDue(now) : !recovery.holdingDue(now)) {
          return;
        }
        if (recovery.videoProcessing) {
          // A verified video is already being copied and decoded. Let that
          // operation persist the message and cancel recovery; send a holding
          // message only if media processing actually exits without evidence.
          _retryUnreadRecoveryNotice(recovery, resend: resend);
          return;
        }
        await _adapter
            .openConversation(recovery.customer, allowActivation: true)
            .timeout(const Duration(seconds: 8));
        // This is only a bounded check for a colleague's visible reply. The
        // capture loop owns text/media extraction; OCR failure must not block
        // the 20-second notice. sendDraftOnce verifies the customer again.
        try {
          final windows = await _adapter
              .listOcrWindows()
              .timeout(_fallbackInspectionTimeout);
          if (windows.isNotEmpty) {
            final reception = windows.firstWhere(
                (window) => window.title.contains('咚咚融合工作台'),
                orElse: () => windows.first);
            final inspection = await _adapter
                .inspectExpectedCustomer(
                  windowId: reception.windowId,
                  expectedCustomer: recovery.customer,
                )
                .timeout(_fallbackInspectionTimeout);
            final visible =
                const OcrCaptureExtractor().analyze(inspection).capture;
            final colleagueReply = visible?.messages.reversed
                .where((message) =>
                    message.direction == 'outgoing' &&
                    !recovery.knownOutgoingIds.contains(message.stableId) &&
                    !_isOwnHoldingReply(message.body) &&
                    message.body != _uncapturedResendReply &&
                    (message.sentAt?.isBefore(recovery.detectedAt) == false))
                .firstOrNull;
            if (colleagueReply != null) {
              _finishUnreadRecovery(recovery.customer,
                  handledAt: colleagueReply.sentAt);
              return;
            }
          }
        } on TimeoutException {
          // The verified send remains possible even if OCR is slow.
        } on PlatformException {
          // The send performs its own exact-customer verification.
        }
        if (!identical(_unreadRecovery[recovery.customer], recovery)) return;
        if (await _database.isHumanContacting(recovery.customer)) {
          _finishUnreadRecovery(recovery.customer);
          return;
        }
        if (await _newOutgoingAt(recovery) case final sentAt?) {
          _finishUnreadRecovery(recovery.customer, handledAt: sentAt);
          return;
        }
        if (await _holdingSentSinceRecovery(recovery) case final sentAt?) {
          recovery.holdingSent = true;
          recovery.holdingSentAt = sentAt;
          _finishUnreadRecovery(recovery.customer, handledAt: sentAt);
          return;
        }
        if (await _hasRecoveredIncoming(recovery)) {
          if (recovery.holdingSentAt case final sentAt?) {
            await _database.acknowledgeUncapturedHolding(
                userId: recovery.customer, sentAt: sentAt);
            _slaFallbackTimers.remove(recovery.customer)?.cancel();
          }
          _finishUnreadRecovery(recovery.customer);
          _scheduleDraftGeneration(recovery.customer, newEvidence: false);
          return;
        }
        final reply = resend ? _uncapturedResendReply : _uncapturedHoldingReply;
        await _adapter.sendDraftOnce(
          expectedCustomer: recovery.customer,
          reply: reply,
          mediaPaths: const [],
        );
        final sentAt = DateTime.now();
        if (resend) {
          recovery.resendSent = true;
        } else {
          recovery.holdingSent = true;
          recovery.holdingSentAt = sentAt;
        }
        try {
          await (await _database.history).appendSlaFallbackSent(
            userId: recovery.customer,
            messageId:
                'unread-recovery:${recovery.detectedAt.microsecondsSinceEpoch}:${resend ? 'resend' : 'holding'}',
            reply: reply,
          );
          if (!resend) {
            await _database.acknowledgeUncapturedHolding(
                userId: recovery.customer, sentAt: sentAt);
            _slaFallbackTimers.remove(recovery.customer)?.cancel();
          }
        } catch (error) {
          // JD already confirmed the send. Never repeat it merely because
          // local history storage failed afterward.
          if (mounted) setState(() => _error = error);
        }
        if (mounted) {
          setState(() => _diagnostics = resend
              ? 'Asked ${recovery.customer} to resend content that could not be captured.'
              : 'Sent a holding message to ${recovery.customer} while capture retries continue.');
        }
      });
    } on PlatformException catch (error) {
      // The send may have succeeded even if JD did not confirm it. Never
      // retry an uncertain send and risk a duplicate customer message.
      if (error.code == 'send_unconfirmed') {
        _finishUnreadRecovery(recovery.customer);
      } else {
        _retryUnreadRecoveryNotice(recovery, resend: resend);
      }
      if (mounted) setState(() => _error = error);
    } catch (error) {
      _retryUnreadRecoveryNotice(recovery, resend: resend);
      if (mounted) setState(() => _error = error);
    } finally {
      recovery.noticeSending = false;
    }
  }

  void _retryUnreadRecoveryNotice(UnreadCaptureRecovery recovery,
      {required bool resend}) {
    if (!identical(_unreadRecovery[recovery.customer], recovery)) return;
    final timers = resend ? _unreadResendTimers : _unreadHoldingTimers;
    timers.remove(recovery.customer)?.cancel();
    timers[recovery.customer] = Timer(
      const Duration(seconds: 2),
      () => unawaited(_sendUnreadRecoveryNotice(recovery, resend: resend)),
    );
  }

  void _scheduleDraftGeneration(String userId, {required bool newEvidence}) {
    unawaited(_scheduleSlaFallback(userId));
    if (newEvidence) {
      _draftRetryTimers.remove(userId)?.cancel();
      _batchCollectionTimers.remove(userId)?.cancel();
      _batchCollectionTimers[userId] = Timer(_batchCollectionWindow, () {
        _batchCollectionTimers.remove(userId);
        unawaited(_queueDraftIfPending(userId));
      });
      return;
    }
    if (_batchCollectionTimers.containsKey(userId)) return;
    if (!newEvidence &&
        (_draftRetryTimers.containsKey(userId) ||
            _draftQueue.contains(userId) ||
            _activeDraftUsers.contains(userId))) {
      return;
    }
    unawaited(_queueDraftIfPending(userId));
  }

  Future<void> _queueDraftIfPending(String userId) async {
    if (!await _database.hasPendingUnanswered(userId) ||
        await _database.isHumanContacting(userId)) {
      return;
    }
    if (_activeDraftUsers.contains(userId) ||
        await _database.hasUndeliveredDraft(userId)) {
      return;
    }
    final pendingMessageId = await _database.pendingMessageId(userId);
    if (pendingMessageId == null) return;
    _draftQueue.add(userId);
    _runDraftWorkers();
  }

  Future<void> _scheduleSlaFallback(String userId) async {
    final job = await _database.slaFallbackJob(userId);
    if (job == null) {
      _slaFallbackTimers.remove(userId)?.cancel();
      return;
    }
    _armSlaFallback(job);
  }

  void _armSlaFallback(SlaFallbackJob job) {
    _slaFallbackTimers.remove(job.userId)?.cancel();
    final remaining = job.dueAt.difference(DateTime.now());
    final delay = remaining.isNegative ? Duration.zero : remaining;
    _slaFallbackTimers[job.userId] = Timer(delay, () {
      _slaFallbackTimers.remove(job.userId);
      unawaited(_sendSlaFallback(job));
    });
  }

  Future<bool> _hasReplySinceSlaMessage(SlaFallbackJob job) async {
    final document = await (await _database.history).read(job.userId);
    final messages = (document?['messages'] as List<Object?>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final incoming = messages
        .where((message) =>
            message['id'] == job.messageId &&
            message['direction'] == 'incoming')
        .firstOrNull;
    final incomingAt =
        DateTime.tryParse(incoming?['sent_at']?.toString() ?? '');
    if (incomingAt == null) return false;
    return messages.any((message) {
      if (message['direction'] != 'outgoing' ||
          message['source'] == 'sla_fallback' ||
          _isOwnHoldingReply(message['body']?.toString())) {
        return false;
      }
      final sentAt = DateTime.tryParse(message['sent_at']?.toString() ?? '');
      return sentAt != null && !sentAt.isBefore(incomingAt);
    });
  }

  Future<void> _sendSlaFallback(SlaFallbackJob job) async {
    if (!_autoCaptureRunning) return;
    try {
      final document = await (await _database.history).read(job.userId);
      final incomingBodies =
          (document?['messages'] as List<Object?>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .where((message) => message['direction'] == 'incoming')
              .map((message) => message['body']?.toString() ?? '')
              .where((body) => body.trim().isNotEmpty)
              .toList(growable: false);
      final latestCustomerText = incomingBodies
              .where((body) => !body.startsWith('[Customer sent'))
              .lastOrNull ??
          incomingBodies.lastOrNull ??
          '';
      final holdingReply = chooseHoldingReply(latestCustomerText);
      await _withFallbackPriority(() async {
        if (!await _database.reserveSlaFallback(
            userId: job.userId, messageId: job.messageId, dueAt: job.dueAt)) {
          return;
        }
        try {
          await _adapter
              .openConversation(job.userId, allowActivation: true)
              .timeout(const Duration(seconds: 8));
          // The timer may have reserved this job before a generated or manual
          // reply completed. Recheck at the last possible point so a holding
          // message can never follow a real reply from the same SLA window.
          if (!await _database.isSlaFallbackReservedForSend(
              userId: job.userId, messageId: job.messageId)) {
            return;
          }
          if (await _hasReplySinceSlaMessage(job)) {
            await _database.releaseSlaFallback(
              userId: job.userId,
              messageId: job.messageId,
            );
            return;
          }
          await _adapter.sendDraftOnce(
            expectedCustomer: job.userId,
            reply: holdingReply,
            mediaPaths: const [],
          );
          final recorded = await _database.markSlaFallbackSent(
            userId: job.userId,
            messageId: job.messageId,
            reply: holdingReply,
          );
          if (recorded && mounted) {
            setState(() => _diagnostics =
                'Sent a holding message to ${job.userId}; the final answer remains queued.');
          }
        } on PlatformException catch (error) {
          if (error.code == 'send_unconfirmed') {
            await _database.markSlaFallbackDeliveryUnknown(
              userId: job.userId,
              messageId: job.messageId,
            );
          } else {
            await _database.releaseSlaFallback(
              userId: job.userId,
              messageId: job.messageId,
            );
            unawaited(_scheduleSlaFallback(job.userId));
          }
          rethrow;
        } catch (_) {
          await _database.releaseSlaFallback(
            userId: job.userId,
            messageId: job.messageId,
          );
          unawaited(_scheduleSlaFallback(job.userId));
          rethrow;
        }
      });
      await _coordinator.refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _runAutoCaptureCycle() async {
    if (!_autoCaptureRunning || _autoCaptureBusy) return;
    _autoCaptureBusy = true;
    final previousUiOperation = _jdUiTail;
    var releaseUiOperation = Completer<void>();
    var captureCycleExited = false;
    _jdUiTail = releaseUiOperation.future;
    await previousUiOperation;
    final scanStartedAt = DateTime.now();
    if (mounted) {
      setState(() {
        _error = null;
        _diagnostics =
            'Checking JD unread messages at ${_formatClock(scanStartedAt)}…';
      });
    }
    try {
      // Baseline polling does not activate JD. A verified unread media bubble
      // may briefly bring it forward to inspect the video play overlay, then
      // restore the operator's previous frontmost application.
      await _adapter
          .ensureReceptionWindow(allowActivation: false)
          .timeout(_captureOperationTimeout);
      final rows = await _adapter
          .listConversationRows()
          .timeout(_captureOperationTimeout);
      if (rows.isEmpty) {
        throw StateError('No JD conversation rows are available.');
      }
      for (final row in rows) {
        _refreshHandledUnread(row);
      }
      final evidenceAvailable = rows.any((row) => row.evidenceAvailable);
      for (final row in rows.where((row) => !row.unread)) {
        _processingUnreadEvidence.remove(row.customer);
        _lastUnreadProbeAt.remove(row.customer);
      }
      for (final row in rows.where((row) => row.unread)) {
        if (!_unreadRecovery.containsKey(row.customer) &&
            !_handledUnreadEvidence.containsKey(row.customer) &&
            !await _database.isHumanContacting(row.customer)) {
          await _beginUnreadRecovery(row.customer, row.unreadEvidence,
              detectedAt: _unreadDetectedAt(row));
        }
      }
      final orderedRows = rows
          .where((row) =>
              (_unreadRecovery[row.customer]?.captureRetryDue(DateTime.now()) ??
                  false) ||
              (evidenceAvailable &&
                  row.unread &&
                  !_processingUnreadEvidence.containsKey(row.customer) &&
                  !_handledUnreadEvidence.containsKey(row.customer)) ||
              (row.unread &&
                  _unreadRecovery[row.customer] == null &&
                  (_lastUnreadProbeAt[row.customer] == null ||
                      DateTime.now()
                              .difference(_lastUnreadProbeAt[row.customer]!) >=
                          const Duration(seconds: 8))))
          .toList(growable: false);
      if (orderedRows.isEmpty) {
        var insertedFromActiveChat = 0;
        final windows =
            await _adapter.listOcrWindows().timeout(_captureOperationTimeout);
        if (windows.isNotEmpty) {
          final reception = windows.firstWhere(
              (window) => window.title.contains('咚咚融合工作台'),
              orElse: () => windows.first);
          final inspection =
              await _inspectStableConversation(reception.windowId);
          if (mounted) setState(() => _ocrInspection = inspection);
          // JD does not expose an unread flag for the active sidebar row.
          // Poll the already-open chat independently; durable message IDs
          // prevent duplicate saves while keeping the unread count truthful.
          final activeCustomer = inspection.activeCustomerId?.trim();
          if (activeCustomer != null &&
              activeCustomer.isNotEmpty &&
              rows.any((row) => row.customer == activeCustomer)) {
            final activeRow =
                rows.firstWhere((row) => row.customer == activeCustomer);
            var recovery = _unreadRecovery[activeCustomer];
            final extraction = _analyzeUnreadInspection(inspection, recovery);
            final senderKey = extraction.latestIncomingSenderKey;
            final incomingTime = extraction.latestIncomingSentAt;
            final recentIncoming = incomingTime != null &&
                !incomingTime.isBefore(inspection.capturedAt
                    .subtract(const Duration(minutes: 10))) &&
                !incomingTime.isAfter(
                    inspection.capturedAt.add(const Duration(minutes: 1)));
            if (recovery == null &&
                (activeRow.unread || recentIncoming) &&
                extraction.latestVisibleSenderIsIncoming &&
                senderKey != null &&
                _handledIncomingSenderKeys[activeCustomer] != senderKey &&
                !await _database.isHumanContacting(activeCustomer)) {
              await _beginUnreadRecovery(
                  activeCustomer, activeRow.unreadEvidence,
                  detectedAt: activeRow.unread
                      ? _unreadDetectedAt(activeRow)
                      : incomingTime);
              recovery = _unreadRecovery[activeCustomer];
            }
            if (recovery != null && senderKey != null) {
              recovery.latestIncomingSenderKey = senderKey;
            }
            if (!extraction.transferNoticeVisible) {
              _visibleTransferWelcomes.remove(activeCustomer);
            }
            if (!await _database.isHumanContacting(activeCustomer)) {
              // The selected chat may never show a sidebar unread badge.
              // Its sender clock can start recovery, and this same pass must
              // inspect the media bubble instead of waiting for a row scan.
              final capture = await _captureWithVisibleMedia(
                inspection,
                extraction,
                // A media-only turn can have no OCR sender/body and JD may
                // clear its unread badge as soon as this chat is opened.
                // Let the bounded visual candidate check recover that turn.
                allowUnlabeledLatestImage:
                    recovery != null || extraction.capture == null,
                allowRecoveryAfterHolding: recovery?.holdingSent == true,
                allowVideoDetectionActivation: recovery != null,
                runVideoProcessingUnlocked: (work) async {
                  if (!releaseUiOperation.isCompleted) {
                    releaseUiOperation.complete();
                  }
                  try {
                    return await work();
                  } finally {
                    if (!captureCycleExited) {
                      final queuedUiOperation = _jdUiTail;
                      releaseUiOperation = Completer<void>();
                      _jdUiTail = releaseUiOperation.future;
                      await queuedUiOperation;
                    }
                  }
                },
              );
              if (capture != null) {
                insertedFromActiveChat = await _database.saveCapture(capture);
              }
              if (recovery != null &&
                  insertedFromActiveChat > 0 &&
                  capture != null &&
                  capture.messages.any((message) =>
                      message.direction == 'incoming' &&
                      recovery!.acceptsIncoming(message.stableId,
                          sentAt: message.sentAt,
                          capturedAt: capture.capturedAt))) {
                await _database.capSlaFallbackDue(
                  userId: activeCustomer,
                  dueAt: recovery.detectedAt
                      .add(UnreadCaptureRecovery.holdingAfter),
                );
                if (recovery.holdingSentAt case final sentAt?) {
                  await _database.acknowledgeUncapturedHolding(
                      userId: activeCustomer, sentAt: sentAt);
                  _slaFallbackTimers.remove(activeCustomer)?.cancel();
                }
                _finishUnreadRecovery(activeCustomer);
              }
              await _database.ensurePendingForUnanswered(activeCustomer);
              if (await _database.hasPendingUnanswered(activeCustomer)) {
                _scheduleDraftGeneration(activeCustomer,
                    newEvidence: insertedFromActiveChat > 0);
              }
              if (insertedFromActiveChat > 0) await _coordinator.refresh();
            }
            if (extraction.transferNoticeVisible) {
              await _handleTransferNotice(
                activeCustomer,
                extraction.transferNoticeKey ??
                    'visible-transfer-${inspection.capturedAt.day}',
              );
            }
          }
        }
        if (mounted) {
          setState(() => _diagnostics = evidenceAvailable
              ? insertedFromActiveChat > 0
                  ? 'Scan ${_formatClock(scanStartedAt)}: no unread conversations were detected; saved $insertedFromActiveChat unseen message(s) from the already-open JD chat.'
                  : 'Scan ${_formatClock(scanStartedAt)}: checked ${rows.length} customer rows; no unread conversations were detected. The already-open JD chat was checked and contained no unseen messages.'
              : 'Scan ${_formatClock(scanStartedAt)}: unread screenshot evidence was unavailable. Automatic row switching was skipped to avoid stealing keyboard focus.');
        }
        return;
      }
      final windows =
          await _adapter.listOcrWindows().timeout(_captureOperationTimeout);
      if (windows.isEmpty) {
        throw StateError('No visible JD 咚咚 window is available.');
      }
      final reception = windows.firstWhere(
          (window) => window.title.contains('咚咚融合工作台'),
          orElse: () => windows.first);
      var insertedTotal = 0;
      for (final row in orderedRows) {
        if (!_autoCaptureRunning) break;
        final customer = row.customer;
        if (row.unread) _lastUnreadProbeAt[customer] = DateTime.now();
        // Human takeover is scoped to one customer. Keep monitoring every
        // other row while leaving this customer's Qianniu chat untouched.
        if (await _database.isHumanContacting(customer)) continue;
        try {
          await _adapter
              .openConversation(customer, allowActivation: false)
              .timeout(_unreadOperationTimeout);
          final inspection = await _adapter
              .inspectExpectedCustomer(
                windowId: reception.windowId,
                expectedCustomer: customer,
              )
              .timeout(_unreadOperationTimeout);
          if (mounted) setState(() => _ocrInspection = inspection);
          var recovery = _unreadRecovery[customer];
          final extraction = _analyzeUnreadInspection(inspection, recovery);
          final senderKey = extraction.latestIncomingSenderKey;
          if (recovery == null &&
              row.unread &&
              extraction.latestVisibleSenderIsIncoming &&
              senderKey != null &&
              _handledIncomingSenderKeys[customer] != senderKey) {
            await _beginUnreadRecovery(customer, row.unreadEvidence,
                detectedAt: _unreadDetectedAt(row));
            recovery = _unreadRecovery[customer];
          }
          if (recovery != null && senderKey != null) {
            recovery.latestIncomingSenderKey = senderKey;
          }
          if (recovery != null) {
            recovery.lastCaptureAttemptAt = DateTime.now();
          }
          if (!extraction.transferNoticeVisible) {
            _visibleTransferWelcomes.remove(customer);
          }
          final capture = await _captureWithVisibleMedia(inspection, extraction,
              allowUnlabeledLatestImage: row.unread || recovery != null,
              allowRecoveryAfterHolding: recovery?.holdingSent == true,
              allowVideoDetectionActivation: recovery != null,
              runVideoProcessingUnlocked: (work) async {
            if (!releaseUiOperation.isCompleted) releaseUiOperation.complete();
            try {
              return await work();
            } finally {
              if (!captureCycleExited) {
                final queuedUiOperation = _jdUiTail;
                releaseUiOperation = Completer<void>();
                _jdUiTail = releaseUiOperation.future;
                await queuedUiOperation;
              }
            }
          }).timeout(_captureOperationTimeout);
          var insertedForCustomer = 0;
          if (capture != null) {
            insertedForCustomer = await _database.saveCapture(capture);
            insertedTotal += insertedForCustomer;
          }
          final capturedNewIncoming = recovery != null &&
              insertedForCustomer > 0 &&
              (extraction.latestVisibleSenderIsIncoming ||
                  extraction.capture == null ||
                  (recovery.holdingSent &&
                      _isOwnHoldingReply(
                          extraction.capture?.messages.lastOrNull?.body)) ||
                  (recovery.holdingSent &&
                      capture?.messages.any((message) =>
                              message.direction == 'incoming' &&
                              message.media.isNotEmpty) ==
                          true)) &&
              capture != null &&
              capture.messages.any((message) =>
                  message.direction == 'incoming' &&
                  recovery!.acceptsIncoming(message.stableId,
                      sentAt: message.sentAt, capturedAt: capture.capturedAt));
          if (capturedNewIncoming) {
            await _database.capSlaFallbackDue(
              userId: customer,
              dueAt:
                  recovery.detectedAt.add(UnreadCaptureRecovery.holdingAfter),
            );
            if (recovery.holdingSentAt case final sentAt?) {
              await _database.acknowledgeUncapturedHolding(
                  userId: customer, sentAt: sentAt);
              _slaFallbackTimers.remove(customer)?.cancel();
            }
            _finishUnreadRecovery(customer);
          }
          if (capturedNewIncoming ||
              (recovery == null &&
                  (capture != null || extraction.transferNoticeVisible))) {
            _processingUnreadEvidence[customer] = row.unreadEvidence;
          }
          await _database.ensurePendingForUnanswered(customer);
          // Queue the durable current message immediately. Optional history
          // scrolling must never prevent an already-saved customer turn from
          // reaching Codex.
          if (await _database.hasPendingUnanswered(customer)) {
            _scheduleDraftGeneration(customer,
                newEvidence: insertedForCustomer > 0);
          }
          if (extraction.transferNoticeVisible) {
            await _handleTransferNotice(
              customer,
              extraction.transferNoticeKey ?? row.unreadEvidence.toString(),
            );
          }

          // Never scroll into history. Only the current bottom viewport may
          // create work, so one unread turn cannot produce one historical
          // reply followed by another reply for the actual latest item.
          if (mounted) setState(() => _ocrInspection = inspection);
        } on PlatformException catch (error) {
          if (error.code == 'composer_not_empty') break;
          if (error.code == 'qianniu_not_frontmost') {
            if (mounted) {
              setState(() => _diagnostics =
                  'Unread conversation detected, but JD 咚咚 is not the active application. Capture deferred without stealing focus.');
            }
            break;
          }
          rethrow;
        }
        // Give an already-due holding message or delivery a turn before
        // switching to another customer. A busy multi-chat scan must not
        // monopolize the single JD UI queue past the response deadline.
        if (!releaseUiOperation.isCompleted) releaseUiOperation.complete();
        final queuedUiOperation = _jdUiTail;
        releaseUiOperation = Completer<void>();
        _jdUiTail = releaseUiOperation.future;
        await queuedUiOperation;
      }
      await _coordinator.refresh();
      if (mounted) {
        final unreadCount = rows.where((row) => row.unread).length;
        final unreadEvidenceAvailable =
            rows.any((row) => row.evidenceAvailable);
        setState(() => _diagnostics = insertedTotal == 0
            ? 'Scan ${_formatClock(scanStartedAt)} completed for ${rows.length} customers; '
                '${unreadEvidenceAvailable ? '$unreadCount unread row(s) were prioritized' : 'unread screenshot evidence was unavailable'}; '
                'no unseen messages were saved; $_visibleMediaTrace.'
            : 'Scan ${_formatClock(scanStartedAt)} prioritized $unreadCount unread row(s) and saved '
                '$insertedTotal unseen message(s) across ${rows.length} customers. '
                'Draft generation is queued separately.');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _diagnostics =
            'Scan ${_formatClock(scanStartedAt)} timed out during a JD operation. It was released; the next 2-second sidebar check will retry.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      captureCycleExited = true;
      if (!releaseUiOperation.isCompleted) releaseUiOperation.complete();
      _autoCaptureBusy = false;
      _requestDelivery();
    }
  }

  /// Let a newly selected JD conversation settle, then perform one Apple
  /// Vision pass over the complete visible conversation.
  Future<OcrInspection> _inspectStableConversation(int windowId) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return _adapter
        .inspectOcr(windowId: windowId)
        .timeout(_captureOperationTimeout);
  }

  String _formatClock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}:'
      '${value.second.toString().padLeft(2, '0')}';

  Future<void> _handleTransferNotice(String userId, String eventKey) async {
    if (!_visibleTransferWelcomes.add(userId)) return;
    // A transferred chat can already contain the customer's real question.
    // Preserve that queued answer and record the transfer as handled without
    // inserting a generic welcome in front of it.
    if (await _database.hasPendingUnanswered(userId) ||
        await _database.hasUndeliveredDraft(userId)) {
      await _database.reserveTransferWelcome(
          userId: userId, eventKey: eventKey);
      return;
    }
    await _sendTransferWelcomeOnce(userId, eventKey);
  }

  Future<bool> _sendTransferWelcomeOnce(String userId, String eventKey) async {
    if (!await _database.reserveTransferWelcome(
        userId: userId, eventKey: eventKey)) {
      return false;
    }
    const welcome = LocalReplyRouter.transferWelcome;
    try {
      await _adapter.sendDraftOnce(
        expectedCustomer: userId,
        reply: welcome,
        mediaPaths: const [],
      );
    } on PlatformException catch (error) {
      // Every native error except send_unconfirmed occurs before the physical
      // Send click. Release those reservations so a still-visible transfer is
      // retried on the next scan. An unconfirmed click remains reserved to
      // avoid greeting the customer twice.
      if (error.code != 'send_unconfirmed') {
        await _database.releaseTransferWelcomeReservation(
          userId: userId,
          eventKey: eventKey,
        );
        _visibleTransferWelcomes.remove(userId);
      }
      rethrow;
    }
    await _database.appendAutomatedNoticeSent(userId: userId, reply: welcome);
    _handledUnreadEvidence[userId] = int.tryParse(eventKey) ?? 0;
    _handledUnreadAt[userId] = DateTime.now();
    if (mounted) {
      setState(() => _diagnostics =
          'Detected a JD transfer and sent one welcome message to $userId.');
    }
    return true;
  }

  void _runDraftWorkers() {
    while (_activeDraftUsers.length < _maxConcurrentDraftWorkers &&
        _draftQueue.isNotEmpty) {
      String? userId;
      for (final candidate in _draftQueue) {
        // One customer owns at most one active Codex process. A later turn
        // waits until the frozen reply is delivered, while up to twenty
        // different customers generate in parallel. Every
        // worker starts its own Codex CLI turn with its own input and output
        // file; customer sessions and histories are never shared.
        if (!_activeDraftUsers.contains(candidate)) {
          userId = candidate;
          break;
        }
      }
      if (userId == null) break;
      _draftQueue.remove(userId);
      _activeDraftUsers.add(userId);
      final cancellation = CodexGenerationCancellation();
      _activeDraftCancellations[userId] = cancellation;
      unawaited(_runDraftWorker(userId, cancellation));
    }
  }

  Future<void> _runDraftWorker(
      String userId, CodexGenerationCancellation cancellation) async {
    try {
      await _processDraftUser(userId, cancellation);
    } on CodexGenerationCancelled {
      // A later saved customer message owns the queued replacement turn.
    } on CodexGenerationTimedOut {
      final messageId = _activeDraftMessageIds[userId];
      final job = await _database.slaFallbackJob(userId);
      if (job != null && job.messageId == messageId) {
        _slaFallbackTimers.remove(userId)?.cancel();
        await _sendSlaFallback(job);
      }
      _scheduleDraftRetry(userId);
    } catch (error) {
      if (mounted) setState(() => _error = error);
      _scheduleDraftRetry(userId);
    } finally {
      if (identical(_activeDraftCancellations[userId], cancellation)) {
        _activeDraftCancellations.remove(userId);
        _activeDraftMessageIds.remove(userId);
      }
      _activeDraftUsers.remove(userId);
      _runDraftWorkers();
      _requestDelivery();
    }
  }

  void _scheduleDraftRetry(String userId) {
    _draftRetryTimers.remove(userId)?.cancel();
    _draftRetryTimers[userId] = Timer(_draftFailureRetryDelay, () async {
      _draftRetryTimers.remove(userId);
      if (!await _database.hasPendingUnanswered(userId) ||
          await _database.isHumanContacting(userId)) {
        return;
      }
      _draftQueue.add(userId);
      _runDraftWorkers();
    });
  }

  Future<void> _processDraftUser(
      String userId, CodexGenerationCancellation cancellation) async {
    cancellation.throwIfCancelled();
    final pending = await _database.conversations();
    final matches = pending
        .where((conversation) => conversation.userId == userId)
        .toList(growable: false);
    if (matches.isEmpty) return;
    if (!await _database.hasPendingUnanswered(userId)) return;
    final conversation = matches.first;
    final messageIdAtGenerationStart = await _database.pendingMessageId(userId);
    if (messageIdAtGenerationStart == null) return;
    _activeDraftMessageIds[userId] = messageIdAtGenerationStart;
    final service = await CodexReplyService.discover(_database);
    cancellation.throwIfCancelled();
    final draft = await service.generate(
        conversation: conversation,
        database: _database,
        batchEndMessageId: messageIdAtGenerationStart,
        cancellation: cancellation);
    cancellation.throwIfCancelled();
    if (await _promoteCodexDetectedVideo(conversation, draft)) {
      _scheduleDraftGeneration(userId, newEvidence: true);
      return;
    }
    final saved = await _database.saveDraft(conversation.id, draft,
        expectedMessageId: messageIdAtGenerationStart);
    // Contacting or a manually observed seller reply may remove the queue
    // while Codex is generating. Never send a result from that stale turn.
    if (saved == 0 || await _database.isHumanContacting(userId)) return;
    final needsHuman = draftRequiresHumanReview(draft);
    if (needsHuman) {
      final document = await (await _database.history).read(userId);
      final messages = (document?['messages'] as List<Object?>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      final latestIncoming = messages.reversed
          .firstWhere((message) => message['direction'] == 'incoming');
      await _database.createHumanReviewTicket(
        userId: userId,
        customerRequest: latestIncoming['body']?.toString() ?? '',
        reason: draftHumanReviewReason(draft),
      );
      await _refreshTickets();
      if (draft.attachments.isNotEmpty && mounted) {
        setState(() => _diagnostics =
            'Human-review acknowledgement for $userId unexpectedly contained media and was not sent.');
      }
    }
    await _coordinator.refresh();
    _requestDelivery();
  }

  Future<bool> _promoteCodexDetectedVideo(
      ConversationSummary conversation, AiDraft draft) async {
    final videoImagePaths = draft.imageDescriptions.entries
        .where((entry) => codexIdentifiedVideoThumbnail(entry.value))
        .map((entry) => entry.key)
        .toSet();
    if (videoImagePaths.isEmpty) return false;

    final document = await (await _database.history).read(conversation.userId);
    String? expectedFingerprint;
    final messages = document?['messages'] as List<Object?>? ?? const [];
    for (final message
        in messages.whereType<Map<String, dynamic>>().toList().reversed) {
      final mediaItems = message['media'] as List<Object?>? ?? const [];
      for (final media in mediaItems.whereType<Map<String, dynamic>>()) {
        if (videoImagePaths.contains(media['path']?.toString())) {
          expectedFingerprint = media['visual_fingerprint']?.toString();
          break;
        }
      }
      if (expectedFingerprint?.isNotEmpty == true) break;
    }
    if (expectedFingerprint?.isNotEmpty != true) return false;

    try {
      return await _withJdUiOperation(() async {
        await _adapter
            .openConversation(conversation.userId, allowActivation: true)
            .timeout(_captureOperationTimeout);
        final windows =
            await _adapter.listOcrWindows().timeout(_captureOperationTimeout);
        if (windows.isEmpty) return false;
        final reception = windows.firstWhere(
            (window) => window.title.contains('咚咚融合工作台'),
            orElse: () => windows.first);
        final inspection = await _adapter
            .inspectExpectedCustomer(
              windowId: reception.windowId,
              expectedCustomer: conversation.userId,
            )
            .timeout(_captureOperationTimeout);
        final candidates = const OcrImageCandidateSelector().select(
          inspection,
          conversation.userId,
          allowUnlabeledLatestImage: true,
        );
        for (final region in candidates) {
          final visible = await _adapter.captureImageRegion(
            expectedCustomer: conversation.userId,
            windowId: inspection.windowId,
            x: region.x,
            y: region.y,
            width: region.width,
            height: region.height,
          );
          final fingerprint = visible.visualFingerprint ?? '';
          if (!_similarImageFingerprints(expectedFingerprint!, fingerprint)) {
            continue;
          }
          final video = await _saveVisibleVideo(
            conversation.userId,
            inspection.windowId,
            region,
            fingerprint,
          );
          if (video == null) return false;
          final inserted = await _database.saveCapture(CapturedConversation(
            stableKey: conversation.stableKey,
            customerName: conversation.customerName,
            customerExternalId: conversation.userId,
            messages: [video],
            capturedAt: inspection.capturedAt,
          ));
          if (inserted > 0 && mounted) {
            setState(() => _diagnostics =
                'Codex recognized a video thumbnail for ${conversation.userId}; downloaded it and queued the sampled frames for a second analysis.');
          }
          return inserted > 0;
        }
        return false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _diagnostics =
            'Codex recognized a video thumbnail, but JD video download failed: $error');
      }
      return false;
    }
  }

  bool _similarImageFingerprints(String left, String right,
      {int maximumDistance = 8}) {
    final a = BigInt.tryParse(left, radix: 16);
    final b = BigInt.tryParse(right, radix: 16);
    if (a == null || b == null) return false;
    var difference = a ^ b;
    var distance = 0;
    while (difference > BigInt.zero && distance <= maximumDistance) {
      difference &= difference - BigInt.one;
      distance++;
    }
    return distance <= maximumDistance;
  }

  void _requestDelivery() {
    _deliveryRequested = true;
    if (_deliveryWorkerRunning) return;
    _deliveryWorkerRunning = true;
    unawaited(_runDeliveryWorker());
  }

  Future<void> _runDeliveryWorker() async {
    try {
      do {
        _deliveryRequested = false;
        while (true) {
          final delivery = await _database.nextReadyDelivery();
          if (delivery == null) break;
          try {
            await _withJdUiOperation(() =>
                _sendAutomaticallyUnlocked(delivery.userId, delivery.draft));
          } catch (error) {
            final deliveryUnknown =
                error is PlatformException && error.code == 'send_unconfirmed';
            await _database.markGeneratedDraftDeliveryFailure(
              userId: delivery.userId,
              error: error.toString(),
              deliveryUnknown: deliveryUnknown,
              retryDelay: _deliveryFailureRetryDelay,
            );
            if (deliveryUnknown) {
              await _database.createHumanReviewTicket(
                userId: delivery.userId,
                customerRequest: delivery.draft.reply,
                reason:
                    'JD clicked Send but did not confirm delivery. Verify the conversation before any retry.',
              );
              await _refreshTickets();
            } else {
              _deliveryRetryTimer?.cancel();
              _deliveryRetryTimer =
                  Timer(_deliveryFailureRetryDelay, _requestDelivery);
            }
            if (mounted) setState(() => _error = error);
          }
          await _coordinator.refresh();
        }
      } while (_deliveryRequested);
    } finally {
      _deliveryWorkerRunning = false;
      if (_deliveryRequested) _requestDelivery();
    }
  }

  Future<T> _withJdUiOperation<T>(Future<T> Function() operation) async {
    final previous = _jdUiTail;
    final release = Completer<void>();
    _jdUiTail = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  Future<T> _withFallbackPriority<T>(Future<T> Function() operation) {
    // The capture queue may hold a slow OCR or video operation for far longer
    // than JD's response window. A fallback bypasses that Dart queue; the
    // native send independently re-verifies the exact active customer before
    // touching the composer, and aborts if another chat took focus.
    return operation();
  }

  Future<bool> _sendAutomaticallyUnlocked(String userId, AiDraft draft) async {
    if (await _database.isHumanContacting(userId)) return false;
    try {
      // Draft generation is independent from sidebar scanning. Another unread
      // customer may have become visible while Codex was working, so reopen
      // and verify the draft's exact customer immediately before sending.
      await _adapter
          .openConversation(userId, allowActivation: true)
          .timeout(_captureOperationTimeout);
      final mediaPaths = draft.attachments
          .where((attachment) => attachment.url.scheme == 'file')
          .map((attachment) => attachment.url.toFilePath())
          .toList(growable: false);
      if (mediaPaths.length != draft.attachments.length) {
        throw StateError(
            'Automatic media sending requires verified local files.');
      }
      await _adapter.sendDraftOnce(
        expectedCustomer: userId,
        reply: draft.reply,
        mediaPaths: mediaPaths,
      );
      await _database.markReplySent(userId: userId, reply: draft.reply);
      _finishUnreadRecovery(userId);
      _slaFallbackTimers.remove(userId)?.cancel();
      _scheduleDraftGeneration(userId, newEvidence: false);
      final evidence = _processingUnreadEvidence[userId];
      if (evidence != null) {
        _handledUnreadEvidence[userId] = evidence;
        _handledUnreadAt[userId] = DateTime.now();
      }
      if (mounted) {
        setState(() {
          _diagnostics =
              'Verified and automatically sent ${draft.model} reply to $userId.';
        });
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _diagnostics =
            'Automatic send to $userId failed. It was not retried to avoid duplicate delivery.');
      }
      rethrow;
    }
  }

  Future<CapturedConversation?> _captureWithVisibleMedia(
    OcrInspection inspection,
    OcrExtractionAttempt extraction, {
    bool allowUnlabeledLatestImage = false,
    bool allowRecoveryAfterHolding = false,
    bool allowVideoDetectionActivation = false,
    _RunVideoProcessingUnlocked? runVideoProcessingUnlocked,
  }) async {
    final customer = extraction.customerId ?? extraction.capture?.customerName;
    if (customer == null || inspection.windowId == 0) {
      return extraction.capture;
    }
    var textCapture = extraction.capture;
    final latestVisible = textCapture?.messages.lastOrNull;
    final onlyOurHoldingIsBelow = allowRecoveryAfterHolding &&
        latestVisible?.direction == 'outgoing' &&
        _isOwnHoldingReply(latestVisible?.body);

    // Keep verified OCR text, then inspect any customer-owned visual region in
    // the same viewport. A missed sender label can leave an older seller reply
    // as the last OCR message even when a new video is visible below it.
    const candidateSelector = OcrImageCandidateSelector();
    var imageCandidates = candidateSelector.select(
      inspection,
      customer,
      allowUnlabeledLatestImage: allowUnlabeledLatestImage,
      // Text on a customer's video thumbnail is video content, not a chat
      // message. Inspect dense rectangles for the play overlay as well.
      includeTextDense: true,
    );
    final viewportFallbackRegions = <OcrVisualRegion>[];
    if (imageCandidates.isEmpty && allowUnlabeledLatestImage) {
      final fallback =
          candidateSelector.fallbackLatestCustomerBlock(inspection, customer);
      if (fallback != null) {
        imageCandidates = [fallback];
        viewportFallbackRegions.add(fallback);
      }
    }
    if ((latestVisible?.direction == 'outgoing' && !onlyOurHoldingIsBelow) ||
        extraction.latestIncomingHasText) {
      imageCandidates = imageCandidates.where((region) {
        final bottom = region.y + region.height;
        final sellerActivityBelow = inspection.observations.any((item) {
          final text = item.text.trim();
          final sellerLabel = (text.contains('旗舰店') &&
                  (text.contains(':') || text.contains('：'))) ||
              RegExp(r'格志打印机[\u3400-\u9fffA-Za-z0-9_-]{1,12}').hasMatch(text);
          return sellerLabel && item.y > bottom + .005;
        });
        return !sellerActivityBelow;
      }).toList(growable: false);
    }
    if (!extraction.latestVisibleSenderIsIncoming &&
        !onlyOurHoldingIsBelow &&
        !(allowUnlabeledLatestImage && textCapture == null) &&
        imageCandidates.isEmpty) {
      _visibleMediaTrace =
          'strict routing: newest visible sender is not the customer';
      return textCapture;
    }
    final capturedMedia = <CapturedMessage>[];
    // Automatic image capture stays screenshot-first and never opens JD's
    // image viewer. A detected video uses JD's bounded local cache copy.
    // Only the newest candidate can create work.
    imageCandidates = imageCandidates.take(1).toList(growable: false);
    var failures = 0;
    final confirmedMediaRegions = <OcrVisualRegion>[];
    for (final region in imageCandidates) {
      try {
        final visible = await _adapter
            .captureImageRegion(
              expectedCustomer: customer,
              windowId: inspection.windowId,
              x: region.x,
              y: region.y,
              width: region.width,
              height: region.height,
              allowActivationForVideoDetection: allowVideoDetectionActivation,
            )
            .timeout(_unreadOperationTimeout);
        var turnAt = _unreadRecovery[customer]?.detectedAt ??
            (extraction.latestVisibleSenderIsIncoming
                ? extraction.latestIncomingSentAt
                : null);
        // The sender label can sit above OCR's text band while the media
        // thumbnail is still clearly visible. Start the 20-second recovery
        // clock before a video cache copy or frame extraction can stall.
        if (!extraction.latestVisibleSenderIsIncoming &&
            (visible.kind == 'video' ||
                (visible.kind == 'image' &&
                    visible.bytes != null &&
                    !candidateSelector.isTextDense(
                        region, inspection.observations))) &&
            visible.visualFingerprint?.isNotEmpty == true &&
            !_unreadRecovery.containsKey(customer) &&
            !await (await _database.history).hasSimilarImageFingerprint(
              customer,
              visible.visualFingerprint!,
              capturedAfter: turnAt,
            )) {
          await _beginUnreadRecovery(customer, 0,
              detectedAt: inspection.capturedAt);
          turnAt = _unreadRecovery[customer]?.detectedAt ?? turnAt;
        }
        if (visible.kind == 'video') {
          // Classification itself is enough to reject OCR text inside the
          // thumbnail, even if the cache copy must be retried later.
          confirmedMediaRegions.add(region);
          final saved = await _saveVisibleVideo(
            customer,
            inspection.windowId,
            region,
            visible.visualFingerprint ?? '',
            sentAt: turnAt,
            runVideoProcessingUnlocked: runVideoProcessingUnlocked,
          );
          if (saved != null) {
            capturedMedia.add(saved);
          }
        } else if (visible.kind == 'image' && visible.bytes != null) {
          // A rectangle around a long ordinary text bubble can look like an
          // image to Vision. Only a non-text-dense rectangle may be saved as a
          // photo; dense regions were inspected solely for a video overlay.
          if (!candidateSelector.isTextDense(region, inspection.observations)) {
            confirmedMediaRegions.add(region);
            final saved = await _saveVisibleImage(customer, visible,
                sentAt: turnAt,
                viewportFallback: viewportFallbackRegions
                    .any((item) => identical(item, region)));
            if (saved != null) {
              capturedMedia.add(saved);
            }
          }
        }
      } on PlatformException {
        failures++;
        // One invalid visual rectangle must not discard other candidates or
        // text already extracted from the visible conversation.
      } on TimeoutException {
        failures++;
        // A stalled native media operation cannot hold the JD UI queue past
        // the customer's fallback deadline.
      }
    }
    _visibleMediaTrace =
        'strict routing: image -> screenshot, video -> Save As + 1fps frames; candidates='
        '${imageCandidates.length}, captured=${capturedMedia.length}, '
        'failures=$failures; '
        'JD image viewer was not opened';
    if (confirmedMediaRegions.isNotEmpty) {
      // Re-read text with the verified media rectangles masked. Otherwise OCR
      // of a play icon or text displayed *inside* a video can close unread
      // recovery and generate a reply to a fabricated customer sentence.
      textCapture = const OcrCaptureExtractor()
          .analyze(inspection, excludedMediaRegions: confirmedMediaRegions)
          .capture;
    }
    if (capturedMedia.isEmpty) return textCapture;
    final uniqueMedia = <String, CapturedMessage>{
      for (final message in capturedMedia) message.stableId: message,
    }.values.toList(growable: false);
    return CapturedConversation(
      stableKey: textCapture?.stableKey ??
          'customer:${sha256.convert(utf8.encode(customer))}',
      customerName: customer,
      customerExternalId: customer,
      capturedAt: inspection.capturedAt,
      messages: [...?textCapture?.messages, ...uniqueMedia],
    );
  }

  Future<CapturedMessage?> _saveVisibleVideo(
    String customer,
    int windowId,
    OcrVisualRegion region,
    String thumbnailFingerprint, {
    DateTime? sentAt,
    _RunVideoProcessingUnlocked? runVideoProcessingUnlocked,
  }) async {
    final store = await _database.history;
    if (thumbnailFingerprint.isNotEmpty &&
        await store.hasSimilarImageFingerprint(
          customer,
          thumbnailFingerprint,
          captureSources: const {'jd_video_cache', 'jd_video_save_as'},
          capturedAfter: sentAt,
        )) {
      return null;
    }
    final destination = Directory(
      '${store.mediaDirectory.path}/${store.safeUserId(customer)}/videos',
    );
    await destination.create(recursive: true);
    final downloaded = await _adapter
        .downloadVideoAt(
          expectedCustomer: customer,
          windowId: windowId,
          x: region.x,
          y: region.y,
          width: region.width,
          height: region.height,
          destinationDirectory: destination.path,
        )
        .timeout(_unreadOperationTimeout);
    if (downloaded.path.isEmpty) return null;
    Future<CapturedMessage?> processDownloadedVideo() async {
      final extracted =
          await const VideoFrameExtractor().extract(downloaded.path);
      var audioEvidence = '[Video audio: analysis unavailable]';
      CapturedMedia? audioMedia;
      try {
        final audio =
            await const VideoAudioExtractor().extract(downloaded.path);
        if (!audio.hasAudioStream) {
          audioEvidence = '[Video audio: no audio stream]';
        } else if (!audio.hasAudibleContent) {
          audioEvidence =
              '[Video audio: an audio stream exists, but no meaningful audible content was detected]';
          audioMedia = CapturedMedia(
            type: 'audio',
            path: audio.audioPath!,
            mimeType: 'audio/wav',
            originalName: 'video_audio.wav',
            captureSource: 'jd_video_audio_ffmpeg',
            description:
                'Audio stream present; meaningful sound was not detected.',
          );
        } else {
          SpeechTranscription? speech;
          try {
            speech = await _adapter
                .transcribeAudio(audio.audioPath!)
                .timeout(const Duration(seconds: 60));
          } catch (_) {
            // Audio evidence remains useful even if permission, connectivity, or
            // the platform recognizer is temporarily unavailable.
          }
          final transcript =
              speech?.transcript.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
          if (speech?.speechDetected == true && transcript.isNotEmpty) {
            final bounded = transcript.length <= 8000
                ? transcript
                : '${transcript.substring(0, 8000)}…';
            audioEvidence =
                '[Video speech transcript (${speech!.language}): $bounded]';
            audioMedia = CapturedMedia(
              type: 'audio',
              path: audio.audioPath!,
              mimeType: 'audio/wav',
              originalName: 'video_audio.wav',
              captureSource: 'jd_video_audio_ffmpeg',
              description:
                  'Audible speech transcribed as ${speech.language} with confidence ${speech.confidence.toStringAsFixed(2)}: $bounded',
            );
          } else {
            audioEvidence =
                '[Video audio: audible content exists, but no speech was recognized]';
            audioMedia = CapturedMedia(
              type: 'audio',
              path: audio.audioPath!,
              mimeType: 'audio/wav',
              originalName: 'video_audio.wav',
              captureSource: 'jd_video_audio_ffmpeg',
              description:
                  'Audible content detected; no speech transcript was available.',
            );
          }
        }
      } catch (_) {
        // Visual video analysis must still proceed if the audio stream is
        // malformed or local FFmpeg audio extraction is unavailable.
      }
      final frameMedia = <CapturedMedia>[];
      for (var index = 0; index < extracted.framePaths.length; index++) {
        frameMedia.add(CapturedMedia(
          type: 'image',
          path: extracted.framePaths[index],
          mimeType: 'image/jpeg',
          originalName:
              'video_frame_${(index + 1).toString().padLeft(2, '0')}s.jpg',
          captureSource: 'jd_video_frame_1fps',
          description: 'Pending Codex visual analysis.',
        ));
      }
      return CapturedMessage(
        stableId: _visibleMediaStableId(
            'visible-video', extracted.sha256Digest, sentAt),
        direction: 'incoming',
        body:
            '[Customer sent a video; copied from JD cache and sampled at one frame per second, maximum 20 frames]\n$audioEvidence',
        sender: customer,
        sentAt: sentAt,
        axPath: 'ocr:jd-video-cache',
        media: [
          CapturedMedia(
            type: 'video',
            path: downloaded.path,
            mimeType: downloaded.mimeType,
            originalName: downloaded.originalName,
            captureSource: 'jd_video_cache',
            description:
                'Original customer video; visual evidence is stored in the sampled frame images.',
            visualFingerprint: thumbnailFingerprint,
          ),
          if (audioMedia != null) audioMedia,
          ...frameMedia,
        ],
      );
    }

    final recovery = _unreadRecovery[customer];
    if (recovery != null) recovery.videoProcessing = true;
    try {
      return runVideoProcessingUnlocked == null
          ? await processDownloadedVideo()
          : await runVideoProcessingUnlocked(processDownloadedVideo);
    } finally {
      if (recovery != null) recovery.videoProcessing = false;
    }
  }

  Future<CapturedMessage?> _saveVisibleImage(
    String customer,
    VisibleImagePayload image, {
    DateTime? sentAt,
    bool viewportFallback = false,
    bool originalDownload = false,
    bool clipboardCopy = false,
  }) async {
    final bytes = image.bytes!;
    final fingerprint = image.visualFingerprint ?? '';
    if (fingerprint.isNotEmpty &&
        await (await _database.history).hasSimilarImageFingerprint(
          customer,
          fingerprint,
          capturedAfter: sentAt,
        )) {
      return null;
    }
    final extension = image.extension ?? 'png';
    final originalName = image.originalName ??
        'qianniu_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final path = await (await _database.history).saveMedia(
      userId: customer,
      filename: originalName,
      bytes: bytes,
    );
    final digest = sha256.convert(bytes).toString();
    return CapturedMessage(
      stableId: _visibleMediaStableId('visible-image', digest, sentAt),
      direction: 'incoming',
      body: clipboardCopy
          ? '[Customer sent an image; copied from JD]'
          : originalDownload
              ? '[Customer sent an image; original downloaded]'
              : '[Customer sent an image; visible portion captured]',
      sender: customer,
      sentAt: sentAt,
      axPath: clipboardCopy
          ? 'ocr:jd-clipboard-image'
          : viewportFallback
              ? 'ocr:visible-chat-viewport-fallback'
              : 'ocr:visible-image-region',
      media: [
        CapturedMedia(
          type: 'image',
          path: path,
          mimeType: image.mimeType,
          originalName: originalName,
          captureSource: clipboardCopy
              ? 'jd_clipboard_copy'
              : originalDownload
                  ? 'jd_image_viewer_download'
                  : viewportFallback
                      ? 'verified_chat_viewport_fallback'
                      : 'verified_window_crop',
          isPartial: !originalDownload && !clipboardCopy,
          description: 'Pending Codex visual analysis.',
          visualFingerprint: fingerprint,
        ),
      ],
    );
  }

  String _visibleMediaStableId(String prefix, String digest, DateTime? turnAt) {
    if (turnAt == null) return '$prefix:$digest';
    return '$prefix:$digest:${turnAt.toUtc().microsecondsSinceEpoch}';
  }

  Future<void> _inspect() async {
    try {
      final result = await _adapter.inspectTree();
      setState(() => _diagnostics = result['tree'] as String? ?? '$result');
    } catch (error) {
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _unreadSignalTimer?.cancel();
    _activeChatSignalTimer?.cancel();
    _deliveryRetryTimer?.cancel();
    for (final timer in _draftRetryTimers.values) {
      timer.cancel();
    }
    for (final timer in _batchCollectionTimers.values) {
      timer.cancel();
    }
    for (final timer in _slaFallbackTimers.values) {
      timer.cancel();
    }
    for (final timer in _unreadHoldingTimers.values) {
      timer.cancel();
    }
    for (final timer in _unreadResendTimers.values) {
      timer.cancel();
    }
    _updateSubscription?.cancel();
    _diagnosticSubscription?.cancel();
    _adapter.close();
    _database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return const Scaffold(
          body: Center(
              child:
                  Text('The capture adapter currently supports macOS only.')));
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 20,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 18,
              child: Icon(Icons.support_agent_rounded, size: 21),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('JD Automation',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                Text('Customer communication console',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.black54)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh connection status',
            onPressed: _refreshStatus,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Accessibility diagnostics',
            onPressed: _inspect,
            icon: const Icon(Icons.troubleshoot_rounded),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _autoCaptureStarting ? null : _start,
            icon: Icon(_autoCaptureRunning
                ? Icons.stop_circle_outlined
                : _autoCaptureStarting
                    ? Icons.hourglass_top_rounded
                    : Icons.play_circle_outline_rounded),
            label: Text(_autoCaptureRunning
                ? 'Stop automation'
                : _autoCaptureStarting
                    ? 'Opening JD…'
                    : 'Start automation'),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: Row(children: [
        SizedBox(
          width: 310,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _status['trusted'] == true
                      ? Colors.green.withValues(alpha: 0.08)
                      : Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _status['trusted'] == true
                        ? Colors.green.withValues(alpha: 0.25)
                        : Theme.of(context).colorScheme.error.withValues(
                              alpha: 0.20,
                            ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _status['trusted'] == true
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      color: _status['trusted'] == true
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _status['trusted'] == true
                                ? 'JD connection ready'
                                : 'Access required',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _status['trusted'] == true
                                ? 'Automation can monitor conversations'
                                : 'Allow Accessibility to begin monitoring',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_status['trusted'] != true)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: OutlinedButton(
                  onPressed: () async {
                    await _adapter.requestAccessibility();
                    await _refreshStatus();
                  },
                  child: const Text('Request Accessibility access'),
                ),
              ),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Error: $_error',
                      style: const TextStyle(color: Colors.red))),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Human review',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (_tickets.isNotEmpty)
                    Badge(label: Text('${_tickets.length}')),
                ],
              ),
            ),
            if (_tickets.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 2, 12, 10),
                child: Text('No open tickets',
                    style: TextStyle(color: Colors.grey)),
              )
            else ...[
              for (final ticket in _tickets.values)
                ListTile(
                  dense: true,
                  title: Text(ticket.conversationId),
                  subtitle: Text('${ticket.status}: ${ticket.reason}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Contacting — pause AI for this customer',
                      onPressed: ticket.status == 'open'
                          ? () => _markContacting(ticket)
                          : null,
                      icon: const Icon(Icons.support_agent),
                    ),
                    IconButton(
                      tooltip: 'Contacted/solved — resume on next new message',
                      onPressed: ticket.status == 'contacting'
                          ? () => _markContacted(ticket)
                          : null,
                      icon: const Icon(Icons.task_alt),
                    ),
                  ]),
                ),
            ],
            const Divider(),
            Expanded(
                child: ListView.builder(
              itemCount: _conversations.length,
              itemBuilder: (context, index) {
                final item = _conversations[index];
                final ticket = _tickets[item.userId];
                return ListTile(
                  title: Row(children: [
                    Expanded(child: Text(item.customerName)),
                    Tooltip(
                      message: ticket == null
                          ? 'No human-review ticket'
                          : ticket.status == 'contacting'
                              ? 'Human is contacting customer'
                              : 'Start contacting; pauses AI for this customer',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: ticket != null && ticket.status == 'open'
                            ? () => _markContacting(ticket)
                            : null,
                        icon: const Icon(Icons.support_agent, size: 19),
                      ),
                    ),
                    Tooltip(
                      message:
                          'Contacted; AI waits for the next customer message',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: ticket?.status == 'contacting'
                            ? () => _markContacted(ticket!)
                            : null,
                        icon: const Icon(Icons.task_alt, size: 19),
                      ),
                    ),
                  ]),
                  subtitle: Text(
                      ticket == null
                          ? (item.messages.isEmpty
                              ? 'No messages'
                              : item.messages.last.body)
                          : '${ticket.status}: ${ticket.reason}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _MessageDialog(
                            conversation: item,
                            database: _database,
                            onReplyCompleted: _coordinator.refresh,
                          )).then((_) => _refreshTickets()),
                );
              },
            )),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(
            child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                _ocrInspection == null
                    ? 'Accessibility diagnostics'
                    : 'OCR diagnostics — ${_ocrInspection!.windowTitle}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_ocrInspection == null
                ? 'Use this output to map roles and paths from the installed JD 咚咚 build. Sending remains guarded by exact customer verification.'
                : '${_ocrInspection!.observations.length} Apple Vision text regions • ${_ocrInspection!.imageWidth}×${_ocrInspection!.imageHeight}. Red boxes show Apple Vision observations.'),
            const SizedBox(height: 8),
            if (_ocrInspection != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _diagnostics.startsWith('Saved') ||
                          _diagnostics.contains('already saved') ||
                          _diagnostics.startsWith('Sent')
                      ? Colors.green.withValues(alpha: 0.10)
                      : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_diagnostics),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
                child: _ocrInspection == null
                    ? SingleChildScrollView(
                        child: SelectableText(_diagnostics,
                            style: const TextStyle(
                                fontFamily: 'Menlo', fontSize: 11)))
                    : _OcrDiagnosticView(inspection: _ocrInspection!)),
          ]),
        )),
      ]),
    );
  }
}

class _OcrDiagnosticView extends StatelessWidget {
  const _OcrDiagnosticView({required this.inspection});

  final OcrInspection inspection;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          flex: 3,
          child: InteractiveViewer(
            minScale: 0.25,
            maxScale: 5,
            child: AspectRatio(
              aspectRatio: inspection.imageWidth / inspection.imageHeight,
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(inspection.image, fit: BoxFit.fill),
                CustomPaint(painter: _OcrBoxPainter(inspection.observations)),
              ]),
            ),
          ),
        ),
        const VerticalDivider(),
        Expanded(
          child: ListView.builder(
            itemCount: inspection.observations.length,
            itemBuilder: (context, index) {
              final observation = inspection.observations[index];
              return ListTile(
                dense: true,
                title: SelectableText(observation.text),
                subtitle: Text(
                    '${(observation.confidence * 100).toStringAsFixed(1)}% • x=${observation.x.toStringAsFixed(3)}, y=${observation.y.toStringAsFixed(3)}'),
              );
            },
          ),
        ),
      ]);
}

class _OcrBoxPainter extends CustomPainter {
  const _OcrBoxPainter(this.observations);

  final List<OcrObservation> observations;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final observation in observations) {
      canvas.drawRect(
        Rect.fromLTWH(
          observation.x * size.width,
          observation.y * size.height,
          observation.width * size.width,
          observation.height * size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OcrBoxPainter oldDelegate) =>
      oldDelegate.observations != observations;
}

class _MessageDialog extends StatefulWidget {
  const _MessageDialog({
    required this.conversation,
    required this.database,
    required this.onReplyCompleted,
  });

  final ConversationSummary conversation;
  final CaptureDatabase database;
  final Future<void> Function() onReplyCompleted;

  @override
  State<_MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends State<_MessageDialog> {
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.conversation.customerName),
        content: SizedBox(
          width: 620,
          height: 560,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Captured and sent messages',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: widget.conversation.messages
                    .map((message) => ListTile(
                          dense: true,
                          leading: Icon(message.direction == 'incoming'
                              ? Icons.call_received
                              : message.direction == 'outgoing'
                                  ? Icons.call_made
                                  : Icons.help_outline),
                          title: Text(message.body),
                          subtitle: Text(message.stableId),
                        ))
                    .toList(),
              ),
            ),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Text(
                    'Replies are generated and sent automatically. Unsent drafts are not shown or written to conversation JSON.'),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      );
}
