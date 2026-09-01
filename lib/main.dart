import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

import 'backend/rag_backend_client.dart';
import 'capture/capture_coordinator.dart';
import 'capture/ocr_capture_extractor.dart';
import 'capture/ocr_image_candidate_selector.dart';
import 'codex/codex_reply_service.dart';
import 'domain/capture_models.dart';
import 'platform/macos_capture_adapter.dart';
import 'storage/capture_database.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JdAutomationApp());
}

class JdAutomationApp extends StatelessWidget {
  const JdAutomationApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'JD Automation',
        theme: ThemeData(
            colorSchemeSeed: const Color(0xfff26b21), useMaterial3: true),
        home: const CaptureHome(),
      );
}

class CaptureHome extends StatefulWidget {
  const CaptureHome({super.key});

  @override
  State<CaptureHome> createState() => _CaptureHomeState();
}

class _CaptureHomeState extends State<CaptureHome> {
  // The persistent PaddleOCR sidecar is fast after warm-up, but its first
  // model initialization can take substantially longer than a native scan.
  static const _captureOperationTimeout = Duration(seconds: 90);
  late final MacOSCaptureAdapter _adapter;
  late final CaptureCoordinator _coordinator;
  late final CaptureDatabase _database;
  late final RagBackendClient _backend;
  StreamSubscription? _updateSubscription;
  StreamSubscription? _diagnosticSubscription;
  List<ConversationSummary> _conversations = const [];
  Map<String, Object?> _status = const {};
  String _diagnostics = 'No AX inspection yet.';
  Object? _error;
  BackendHealth? _backendHealth;
  Map<String, HumanReviewTicket> _tickets = const {};
  OcrInspection? _ocrInspection;
  bool _ocrLoading = false;
  bool _sending = false;
  bool _autoCaptureRunning = false;
  bool _autoCaptureBusy = false;
  Timer? _autoCaptureTimer;
  final Set<String> _draftQueue = {};
  bool _draftWorkerRunning = false;
  String? _activeDraftUser;
  final Map<String, int> _processingUnreadEvidence = {};
  final Map<String, int> _handledUnreadEvidence = {};
  final Set<String> _visibleTransferWelcomes = {};
  String _visibleMediaTrace = 'visible image candidates=0, saved=0';

  @override
  void initState() {
    super.initState();
    _backend = RagBackendClient();
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
      _refreshBackendHealth();
      _refreshTickets();
    }
  }

  Future<void> _refreshBackendHealth() async {
    try {
      final health = await _backend.health();
      if (mounted) setState(() => _backendHealth = health);
    } catch (_) {
      if (mounted) setState(() => _backendHealth = null);
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
    if (_autoCaptureRunning) {
      _autoCaptureTimer?.cancel();
      setState(() => _autoCaptureRunning = false);
      return;
    }
    setState(() {
      _autoCaptureRunning = true;
      _error = null;
      _diagnostics =
          'Automatic OCR capture started. Unread rows will be checked every 15 seconds.';
    });
    _autoCaptureTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => unawaited(_runAutoCaptureCycle()));
    unawaited(_runAutoCaptureCycle());
  }

  Future<void> _runAutoCaptureCycle() async {
    if (!_autoCaptureRunning || _autoCaptureBusy || _sending) return;
    _autoCaptureBusy = true;
    final scanStartedAt = DateTime.now();
    if (mounted) {
      setState(() {
        _error = null;
        _diagnostics =
            'Checking JD unread messages at ${_formatClock(scanStartedAt)}…';
      });
    }
    try {
      // A periodic monitor must never activate/unhide Qianniu. Doing so steals
      // keyboard focus from whichever application the operator is using.
      await _adapter
          .ensureReceptionWindow(allowActivation: false)
          .timeout(_captureOperationTimeout);
      final rows = await _adapter
          .listConversationRows()
          .timeout(_captureOperationTimeout);
      if (rows.isEmpty) {
        throw StateError('No JD conversation rows are available.');
      }
      final evidenceAvailable = rows.any((row) => row.evidenceAvailable);
      for (final row in rows.where((row) => !row.unread)) {
        _handledUnreadEvidence.remove(row.customer);
        _processingUnreadEvidence.remove(row.customer);
      }
      final orderedRows = evidenceAvailable
          ? rows
              .where((row) =>
                  row.unread &&
                  _activeDraftUser != row.customer &&
                  !_draftQueue.contains(row.customer) &&
                  _handledUnreadEvidence[row.customer] != row.unreadEvidence)
              .toList(growable: false)
          : const <QianniuConversationRow>[];
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
              rows.any((row) => row.customer == activeCustomer) &&
              !await _database.isHumanContacting(activeCustomer)) {
            final extraction = const OcrCaptureExtractor().analyze(inspection);
            if (extraction.transferNoticeVisible) {
              if (_visibleTransferWelcomes.add(activeCustomer)) {
                await _sendTransferWelcomeOnce(
                    activeCustomer,
                    extraction.transferNoticeKey ??
                        'visible-transfer-${inspection.capturedAt.day}');
              }
            } else {
              _visibleTransferWelcomes.remove(activeCustomer);
            }
            final capture = await _captureWithVisibleMedia(
                inspection, extraction,
                // Passive polling may save newly recognized text, but it must
                // never open an old image without verified unread evidence.
                allowUnlabeledLatestImage: false);
            if (capture != null) {
              insertedFromActiveChat = await _database.saveCapture(capture);
            }
            if (await _database.hasPendingUnanswered(activeCustomer)) {
              _draftQueue.add(activeCustomer);
              unawaited(_runDraftWorker());
            }
            if (insertedFromActiveChat > 0) await _coordinator.refresh();
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
        // Human takeover is scoped to one customer. Keep monitoring every
        // other row while leaving this customer's Qianniu chat untouched.
        if (await _database.isHumanContacting(customer)) continue;
        _processingUnreadEvidence[customer] = row.unreadEvidence;
        try {
          await _adapter
              .openConversation(customer, allowActivation: false)
              .timeout(_captureOperationTimeout);
          final inspection =
              await _inspectStableConversation(reception.windowId);
          if (mounted) setState(() => _ocrInspection = inspection);
          final extraction = const OcrCaptureExtractor().analyze(inspection);
          if (extraction.transferNoticeVisible) {
            if (_visibleTransferWelcomes.add(customer)) {
              await _sendTransferWelcomeOnce(
                  customer,
                  extraction.transferNoticeKey ??
                      row.unreadEvidence.toString());
            }
          } else {
            _visibleTransferWelcomes.remove(customer);
          }
          final capture = await _captureWithVisibleMedia(inspection, extraction,
                  allowUnlabeledLatestImage: row.unread)
              .timeout(_captureOperationTimeout);
          if (capture != null) {
            insertedTotal += await _database.saveCapture(capture);
          }
          // Queue the durable current message immediately. Optional history
          // scrolling must never prevent an already-saved customer turn from
          // reaching Codex.
          if (await _database.hasPendingUnanswered(customer)) {
            _draftQueue.add(customer);
            unawaited(_runDraftWorker());
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
            'Scan ${_formatClock(scanStartedAt)} timed out during a JD operation. It was released; the next fixed 15-second check will retry.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _autoCaptureBusy = false;
    }
  }

  /// Let a newly selected JD conversation settle, then perform one enlarged
  /// PaddleOCR pass. The sidecar already recognizes the complete conversation
  /// crop; doing the same expensive inference twice doubled response latency.
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

  Future<bool> _sendTransferWelcomeOnce(String userId, String eventKey) async {
    if (!await _database.reserveTransferWelcome(
        userId: userId, eventKey: eventKey)) {
      return false;
    }
    const welcome =
        'Hello! Welcome to Grozziie customer service. I’m here to help you. What can I assist you with today?';
    if (mounted) setState(() => _sending = true);
    try {
      await _adapter.sendDraftOnce(
        expectedCustomer: userId,
        reply: welcome,
        mediaPaths: const [],
      );
      await _database.appendAutomatedNoticeSent(userId: userId, reply: welcome);
      _handledUnreadEvidence[userId] = int.tryParse(eventKey) ?? 0;
      if (mounted) {
        setState(() => _diagnostics =
            'Detected a JD transfer and sent one welcome message to $userId.');
      }
      return true;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _runDraftWorker() async {
    if (_draftWorkerRunning) return;
    _draftWorkerRunning = true;
    try {
      while (_draftQueue.isNotEmpty) {
        final userId = _draftQueue.first;
        _draftQueue.remove(userId);
        _activeDraftUser = userId;
        try {
          await _processDraftUser(userId);
        } finally {
          if (_activeDraftUser == userId) _activeDraftUser = null;
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _draftWorkerRunning = false;
      if (_draftQueue.isNotEmpty) unawaited(_runDraftWorker());
    }
  }

  Future<void> _processDraftUser(String userId) async {
    final pending = await _database.conversations();
    final matches = pending
        .where((conversation) => conversation.userId == userId)
        .toList(growable: false);
    if (matches.isEmpty) return;
    if (!await _database.hasPendingUnanswered(userId)) return;
    final conversation = matches.first;
    final service = await CodexReplyService.discover(_database);
    final draft =
        await service.generate(conversation: conversation, database: _database);
    final saved = await _database.saveDraft(conversation.id, draft);
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
      if (draft.attachments.isEmpty) {
        final sent = await _sendAutomatically(userId, draft);
        if (mounted && sent) {
          setState(() => _diagnostics =
              'Created an open human-review ticket and automatically sent the Codex acknowledgement to $userId. AI remains active until Contacting is clicked.');
        }
      } else if (mounted) {
        setState(() => _diagnostics =
            'Human-review acknowledgement for $userId unexpectedly contained media and was not sent.');
      }
    } else {
      await _sendAutomatically(userId, draft);
    }
    await _coordinator.refresh();
  }

  Future<bool> _sendAutomatically(String userId, AiDraft draft) async {
    if (await _database.isHumanContacting(userId)) return false;
    if (mounted) setState(() => _sending = true);
    try {
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
      final evidence = _processingUnreadEvidence[userId];
      if (evidence != null) _handledUnreadEvidence[userId] = evidence;
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
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<CapturedConversation?> _captureWithVisibleMedia(
    OcrInspection inspection,
    OcrExtractionAttempt extraction, {
    bool allowUnlabeledLatestImage = false,
  }) async {
    final customer = extraction.customerId ?? extraction.capture?.customerName;
    if (customer == null || inspection.windowId == 0) {
      return extraction.capture;
    }
    final textCapture = extraction.capture;

    // A sender-bounded OCR body is already definitive text evidence. Saving
    // it must not depend on clicking the bubble and copying from JD: passive
    // monitoring intentionally leaves JD in the background, where clipboard
    // classification returns `unavailable` and previously discarded valid
    // Apple Vision text. This also prevents the cursor jumping on every scan.
    if (extraction.latestIncomingHasText) {
      _visibleMediaTrace =
          'strict routing: verified incoming OCR text -> saved directly';
      return textCapture;
    }
    if (!extraction.latestVisibleSenderIsIncoming) {
      _visibleMediaTrace =
          'strict routing: newest visible sender is not the customer';
      return textCapture;
    }
    final capturedMedia = <CapturedMessage>[];
    var imageCandidates = const OcrImageCandidateSelector().select(
      inspection,
      customer,
      allowUnlabeledLatestImage: allowUnlabeledLatestImage,
    );
    final visibleMessages = textCapture?.messages ?? const [];
    final latestVisible = visibleMessages.isEmpty ? null : visibleMessages.last;
    if (latestVisible?.direction == 'outgoing') {
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
    // Automatic media capture is deliberately screenshot-first and never
    // opens JD's modal image viewer. Only the newest candidate can create work.
    imageCandidates = imageCandidates.take(1).toList(growable: false);
    var failures = 0;
    for (final region in imageCandidates) {
      try {
        final visible = await _adapter.captureImageRegion(
          expectedCustomer: customer,
          windowId: inspection.windowId,
          x: region.x,
          y: region.y,
          width: region.width,
          height: region.height,
        );
        if (visible.kind == 'image' && visible.bytes != null) {
          final saved = await _saveVisibleImage(
            customer,
            visible,
          );
          if (saved != null) capturedMedia.add(saved);
        }
      } on PlatformException {
        failures++;
        // One invalid visual rectangle must not discard other candidates or
        // text already extracted from the visible conversation.
      }
    }
    _visibleMediaTrace = 'strict routing: image -> screenshot; candidates='
        '${imageCandidates.length}, captured=${capturedMedia.length}, '
        'failures=$failures; '
        'JD image viewer was not opened';
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

  Future<CapturedMessage?> _saveVisibleImage(
    String customer,
    VisibleImagePayload image, {
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
      stableId: 'visible-image:$digest',
      direction: 'incoming',
      body: clipboardCopy
          ? '[Customer sent an image; copied from JD]'
          : originalDownload
              ? '[Customer sent an image; original downloaded]'
              : '[Customer sent an image; visible portion captured]',
      sender: customer,
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

  Future<void> _loadDemoData() async {
    try {
      await _database.seedDemoData();
      await _coordinator.refresh();
      final root = await _database.storageRoot;
      if (mounted) {
        setState(() {
          _ocrInspection = null;
          _diagnostics =
              'Demo data created.\n\nJSON: ${root.path}/<user_id>.json\nMedia: ${root.path}/media/<user_id>/\nSQLite pending queue: ${root.path}/jd_automation.sqlite3';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _inspect() async {
    try {
      final result = await _adapter.inspectTree();
      setState(() => _diagnostics = result['tree'] as String? ?? '$result');
    } catch (error) {
      setState(() => _error = error);
    }
  }

  Future<void> _inspectOcr({bool chooseWindow = false}) async {
    setState(() {
      _ocrLoading = true;
      _error = null;
    });
    try {
      final windows = await _adapter.listOcrWindows();
      if (windows.isEmpty) {
        throw StateError(
            'No visible JD 咚咚 windows found. Open the customer-service window and retry.');
      }
      // CGWindowList is ordered front-to-back. The Qianniu reception/message
      // window floats in front of the main workbench, so it is the safe default.
      final selected = chooseWindow && windows.length > 1
          ? await _selectOcrWindow(windows)
          : windows.first;
      if (selected == null) return;
      final inspection = await _adapter.inspectOcr(windowId: selected.windowId);
      final extraction = const OcrCaptureExtractor().analyze(inspection);
      final capture = await _captureWithVisibleMedia(
        inspection,
        extraction,
        allowUnlabeledLatestImage: true,
      );
      var outcome = 'OCR did not save a message: ${extraction.reason}; '
          '$_visibleMediaTrace.';
      if (capture != null) {
        final inserted = await _database.saveCapture(capture);
        await _coordinator.refresh();
        final userId = capture.customerExternalId ?? capture.customerName;
        final unanswered = await _database.hasPendingUnanswered(userId);
        if (!unanswered) {
          outcome = 'OCR completed. The latest message for '
              '${capture.customerName} is not awaiting a reply. '
              '${inserted == 0 ? 'No duplicate was added.' : 'Newly observed seller activity was saved without generating a draft.'}';
        } else {
          final pending = await _database.conversations();
          final conversation =
              pending.firstWhere((item) => item.userId == userId);
          final service = await CodexReplyService.discover(_database);
          final draft = await service.generate(
              conversation: conversation, database: _database);
          final saved = await _database.saveDraft(conversation.id, draft);
          if (saved == 0 || await _database.isHumanContacting(userId)) {
            outcome =
                'The reply became ineligible while it was generating. Nothing was sent.';
            if (mounted) {
              setState(() {
                _ocrInspection = inspection;
                _diagnostics = outcome;
              });
            }
            return;
          }
          final needsHuman = draftRequiresHumanReview(draft);
          if (needsHuman) {
            await _database.createHumanReviewTicket(
              userId: capture.customerName,
              customerRequest: capture.messages.last.body,
              reason: draftHumanReviewReason(draft),
            );
            await _refreshTickets();
            if (draft.attachments.isEmpty) {
              final sent = await _sendAutomatically(userId, draft);
              outcome = sent
                  ? 'Created an open human-review ticket and automatically sent the Codex acknowledgement. AI remains active until Contacting is clicked.'
                  : 'The ticket remains open, but Contacting was clicked before the acknowledgement could be sent.';
            } else {
              outcome =
                  'Created the human-review ticket, but its reply includes media and could not be auto-sent safely.';
            }
          } else {
            final sent = await _sendAutomatically(userId, draft);
            outcome = sent
                ? 'Saved the customer message and automatically sent a verified ${draft.model} reply to ${capture.customerName}.'
                : 'Human takeover started before sending. Nothing was sent.';
          }
          await _coordinator.refresh();
        }
      }
      if (mounted) {
        setState(() {
          _ocrInspection = inspection;
          _diagnostics = outcome;
        });
      }
    } on PlatformException catch (error) {
      if (error.code == 'screen_recording_not_allowed') {
        await _adapter.requestScreenRecording();
      }
      if (mounted) setState(() => _error = error);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _ocrLoading = false);
    }
  }

  Future<OcrWindowInfo?> _selectOcrWindow(List<OcrWindowInfo> windows) async {
    return showDialog<OcrWindowInfo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select JD 咚咚 window to scan'),
        children: [
          for (final window in windows)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, window),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.chat_outlined),
                title: Text(
                    window.title.isEmpty ? 'Untitled JD window' : window.title),
                subtitle: Text(window.description),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _updateSubscription?.cancel();
    _diagnosticSubscription?.cancel();
    _adapter.close();
    _backend.close();
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
        title: const Text('JD Automation'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Tooltip(
                message: _backendHealth == null
                    ? 'Backend unavailable'
                    : '${_backendHealth!.records} knowledge records • ${_backendHealth!.model}',
                child: Chip(
                  avatar: Icon(Icons.circle,
                      size: 11,
                      color: _backendHealth?.available == true
                          ? Colors.green
                          : Colors.red),
                  label: Text(_backendHealth?.available == true
                      ? 'AI backend ready'
                      : 'AI backend offline'),
                ),
              ),
            ),
          ),
          TextButton(
              onPressed: _refreshStatus, child: const Text('Refresh status')),
          TextButton(onPressed: _inspect, child: const Text('Inspect AX tree')),
          TextButton.icon(
            onPressed: _ocrLoading ? null : () => _inspectOcr(),
            icon: _ocrLoading
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.document_scanner_outlined),
            label: Text(_ocrLoading ? 'Scanning…' : 'Inspect OCR'),
          ),
          IconButton(
            tooltip: 'Choose a different JD window',
            onPressed:
                _ocrLoading ? null : () => _inspectOcr(chooseWindow: true),
            icon: const Icon(Icons.filter_none),
          ),
          TextButton(
            onPressed: _loadDemoData,
            child: const Text('Load demo'),
          ),
          FilledButton(
              onPressed: _start,
              child:
                  Text(_autoCaptureRunning ? 'Stop capture' : 'Start capture')),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(children: [
        SizedBox(
          width: 310,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                  'PID: ${_status['pid'] ?? 'not running'}  •  Accessibility: ${_status['trusted'] == true ? 'allowed' : 'not allowed'}'),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Text('Human review',
                  style: TextStyle(fontWeight: FontWeight.w700)),
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
                : '${_ocrInspection!.observations.length} ${_ocrInspection!.ocrEngine == 'apple_vision' ? 'Apple Vision' : 'PaddleOCR'} text regions • ${_ocrInspection!.imageWidth}×${_ocrInspection!.imageHeight}. Red boxes show ${_ocrInspection!.ocrEngine == 'apple_vision' ? 'Apple Vision' : 'PaddleOCR'} observations.'),
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
