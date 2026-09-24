import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/capture_models.dart';
import 'capture_adapter.dart';

bool customerIdentitiesMatch(String? observed, String expected) {
  String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  return observed != null && normalize(observed) == normalize(expected);
}

class MacOSCaptureAdapter implements CaptureAdapter {
  MacOSCaptureAdapter({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static const _channelName = 'com.grozziie.jdAutomation/accessibility';
  final MethodChannel _channel;
  final _captures = StreamController<CapturedConversation>.broadcast();
  final _diagnostics = StreamController<Map<String, Object?>>.broadcast();
  final Map<String, String> _verifiedCustomerIdentities = {};

  String _identityKey(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _verifiedIdentityFor(String customer) =>
      _verifiedCustomerIdentities[_identityKey(customer)] ?? customer;

  void _rememberVerifiedIdentity(String requested, Object? verified) {
    final identity = verified?.toString().trim() ?? '';
    if (identity.isEmpty) return;
    _verifiedCustomerIdentities[_identityKey(requested)] = identity;
    _verifiedCustomerIdentities[_identityKey(identity)] = identity;
  }

  @override
  Stream<CapturedConversation> get captures => _captures.stream;

  @override
  Stream<Map<String, Object?>> get diagnostics => _diagnostics.stream;

  Future<void> close() async {
    await _captures.close();
    await _diagnostics.close();
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final arguments = (call.arguments as Map<Object?, Object?>?) ?? const {};
    if (call.method == 'capture') {
      _captures.add(CapturedConversation.fromMap(arguments));
    } else if (call.method == 'diagnostic') {
      _diagnostics.add(arguments.map((key, value) => MapEntry('$key', value)));
    }
  }

  @override
  Future<Map<String, Object?>> status() => _mapCall('status');

  @override
  Future<bool> requestAccessibility() async =>
      await _channel.invokeMethod<bool>('requestAccessibility') ?? false;

  Future<bool> requestScreenRecording() async =>
      await _channel.invokeMethod<bool>('requestScreenRecording') ?? false;

  Future<List<OcrWindowInfo>> listOcrWindows() async {
    final value = await _channel.invokeListMethod<Object?>('listOCRWindows');
    return (value ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(OcrWindowInfo.fromMap)
        .toList(growable: false);
  }

  Future<OcrInspection> inspectOcr({
    required int windowId,
    bool fast = false,
  }) async {
    final value = await _mapCall('inspectOCR', <String, Object?>{
      'windowId': windowId,
      'recognitionLevel': fast ? 'fast' : 'accurate',
    });
    if (value['error'] case final String code) {
      throw PlatformException(
        code: code,
        message: value['message'] as String? ?? 'OCR inspection failed.',
      );
    }
    return OcrInspection.fromMap(value);
  }

  /// Waits until JingMai's active header proves that a requested row switch
  /// completed. Callers must not persist OCR under the requested customer
  /// name until this independent identity check succeeds.
  Future<OcrInspection> inspectExpectedCustomer({
    required int windowId,
    required String expectedCustomer,
    int maximumAttempts = 6,
    Duration retryDelay = const Duration(milliseconds: 250),
  }) async {
    final verifiedExpected = _verifiedIdentityFor(expectedCustomer);
    OcrInspection? lastInspection;
    for (var attempt = 0; attempt < maximumAttempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelay);
      lastInspection = await inspectOcr(windowId: windowId);
      if (customerIdentitiesMatch(
          lastInspection.activeCustomerId, verifiedExpected)) {
        return lastInspection;
      }
    }
    throw PlatformException(
      code: 'customer_switch_not_verified',
      message: 'JingMai did not settle on $verifiedExpected. OCR data was '
          'discarded instead of being saved to the wrong customer file '
          '(active: ${lastInspection?.activeCustomerId ?? 'unknown'}).',
    );
  }

  Future<Map<String, Object?>> sendDraftOnce({
    required String expectedCustomer,
    required String reply,
    List<String> mediaPaths = const [],
  }) async {
    final value = await _mapCall('sendDraftOnce', <String, Object?>{
      'expectedCustomer': _verifiedIdentityFor(expectedCustomer),
      'reply': reply,
      'mediaPaths': mediaPaths,
    });
    if (value['error'] case final String code) {
      throw PlatformException(
          code: code, message: value['message'] as String? ?? 'Send failed.');
    }
    return value;
  }

  Future<VisibleImagePayload> captureImageRegion({
    required String expectedCustomer,
    required int windowId,
    required double x,
    required double y,
    required double width,
    required double height,
    DateTime? expectedMediaAt,
    bool allowActivationForVideoDetection = false,
  }) async {
    final value = await _mapCall('captureImageRegion', <String, Object?>{
      'expectedCustomer': _verifiedIdentityFor(expectedCustomer),
      'windowId': windowId,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      if (expectedMediaAt != null)
        'expectedMediaAtMs': expectedMediaAt.millisecondsSinceEpoch,
      'allowActivationForVideoDetection': allowActivationForVideoDetection,
    });
    if (value['error'] case final String code) {
      throw PlatformException(
          code: code,
          message:
              value['message'] as String? ?? 'Image-region capture failed.');
    }
    return VisibleImagePayload.fromMap(value);
  }

  /// Looks for one uniquely timed image or video in JD's local cache after an
  /// unread turn was detected. Native code re-verifies the active customer;
  /// the caller must additionally reject cross-customer clock ambiguity.
  Future<CachedMediaPayload?> captureRecentCachedMedia({
    required String expectedCustomer,
    required DateTime expectedMediaAt,
    required String destinationDirectory,
  }) async {
    final value = await _mapCall('captureRecentCachedMedia', <String, Object?>{
      'expectedCustomer': _verifiedIdentityFor(expectedCustomer),
      'expectedMediaAtMs': expectedMediaAt.millisecondsSinceEpoch,
      'destinationDirectory': destinationDirectory,
    });
    final kind = value['kind']?.toString();
    if (kind != 'image' && kind != 'video') return null;
    return CachedMediaPayload(
      kind: kind!,
      cacheKey: value['cacheKey']?.toString() ?? '',
      cacheModifiedAt: DateTime.fromMillisecondsSinceEpoch(
        (value['cacheModifiedAtMs'] as num?)?.toInt() ?? 0,
      ),
      image: kind == 'image' ? VisibleImagePayload.fromMap(value) : null,
      video: kind == 'video' ? DownloadedVideoPayload.fromMap(value) : null,
    );
  }

  Future<MessageClassification> classifyMessageAt({
    required String expectedCustomer,
    required int windowId,
    required double x,
    required double y,
  }) async {
    final value = await _mapCall('classifyMessageAt', <String, Object?>{
      'expectedCustomer': _verifiedIdentityFor(expectedCustomer),
      'windowId': windowId,
      'x': x,
      'y': y,
    });
    return MessageClassification(
      kind: value['kind']?.toString() ?? 'unknown',
      visualFingerprint: value['visualFingerprint']?.toString(),
      image: value['kind']?.toString() == 'image'
          ? VisibleImagePayload.fromMap(value)
          : null,
    );
  }

  Future<VisibleImagePayload> downloadImageAt({
    required String expectedCustomer,
    required int windowId,
    required double x,
    required double y,
  }) async {
    final value = await _mapCall('downloadImageAt', <String, Object?>{
      'expectedCustomer': _verifiedIdentityFor(expectedCustomer),
      'windowId': windowId,
      'x': x,
      'y': y,
    });
    if (value['error'] case final String code) {
      throw PlatformException(
          code: code,
          message: value['message'] as String? ??
              'The original JD image could not be downloaded.');
    }
    return VisibleImagePayload.fromMap(value);
  }

  Future<DownloadedVideoPayload> downloadVideoAt({
    required String expectedCustomer,
    required int windowId,
    required double x,
    required double y,
    required double width,
    required double height,
    required String destinationDirectory,
  }) async {
    final value = await _mapCall('downloadVideoAt', <String, Object?>{
      'expectedCustomer': _verifiedIdentityFor(expectedCustomer),
      'windowId': windowId,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'destinationDirectory': destinationDirectory,
    });
    if (value['error'] case final String code) {
      throw PlatformException(
        code: code,
        message: value['message'] as String? ??
            'The original JD video could not be downloaded.',
      );
    }
    return DownloadedVideoPayload.fromMap(value);
  }

  Future<SpeechTranscription> transcribeAudio(String path) async {
    final value = await _mapCall('transcribeAudio', <String, Object?>{
      'path': path,
    });
    if (value['error'] case final String code) {
      throw PlatformException(
        code: code,
        message: value['message'] as String? ??
            'The video audio could not be transcribed.',
      );
    }
    return SpeechTranscription.fromMap(value);
  }

  Future<List<String>> listConversations() async {
    final value = await _channel.invokeListMethod<Object?>('listConversations');
    return (value ?? const [])
        .map((item) => item.toString())
        .toList(growable: false);
  }

  Future<List<QianniuConversationRow>> listConversationRows() async {
    final value =
        await _channel.invokeListMethod<Object?>('listConversationRows');
    return (value ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(QianniuConversationRow.fromMap)
        .toList(growable: false);
  }

  Future<Map<String, Object?>> ensureReceptionWindow(
      {bool allowActivation = true}) async {
    final value = await _mapCall('ensureReceptionWindow', <String, Object?>{
      'allowActivation': allowActivation,
    });
    if (value['error'] case final String code) {
      throw PlatformException(
          code: code,
          message: value['message'] as String? ??
              'Could not open the JD 咚咚 customer-service window.');
    }
    return value;
  }

  Future<void> openConversation(String expectedCustomer,
      {bool allowActivation = true}) async {
    final nativeExpected = _verifiedIdentityFor(expectedCustomer);
    final value = await _mapCall('openConversation', <String, Object?>{
      'expectedCustomer': nativeExpected,
      'allowActivation': allowActivation,
    });
    if (value['error'] case final String code) {
      throw PlatformException(
          code: code,
          message:
              value['message'] as String? ?? 'Could not open conversation.');
    }
    _rememberVerifiedIdentity(expectedCustomer, value['customer']);
  }

  Future<void> scrollConversation(
      {required String expectedCustomer, required int deltaY}) async {
    final value = await _mapCall('scrollConversation', <String, Object?>{
      'expectedCustomer': _verifiedIdentityFor(expectedCustomer),
      'deltaY': deltaY,
    });
    if (value['error'] case final String code) {
      throw PlatformException(
          code: code,
          message: value['message'] as String? ?? 'Could not scroll chat.');
    }
  }

  @override
  Future<void> start() => _channel.invokeMethod<void>('startCapture');

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stopCapture');

  @override
  Future<Map<String, Object?>> inspectTree({int maxDepth = 12}) =>
      _mapCall('inspectTree', <String, Object?>{'maxDepth': maxDepth});

  Future<Map<String, Object?>> _mapCall(String method,
      [Object? arguments]) async {
    final value =
        await _channel.invokeMapMethod<Object?, Object?>(method, arguments);
    return (value ?? const {}).map((key, value) => MapEntry('$key', value));
  }
}

class MessageClassification {
  const MessageClassification({
    required this.kind,
    this.visualFingerprint,
    this.image,
  });

  final String kind;
  final String? visualFingerprint;
  final VisibleImagePayload? image;
}

class OcrWindowInfo {
  const OcrWindowInfo({
    this.windowId = 0,
    required this.title,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory OcrWindowInfo.fromMap(Map<Object?, Object?> value) => OcrWindowInfo(
        windowId: (value['windowId'] as num).toInt(),
        title: value['title'] as String? ?? 'Untitled JD window',
        x: (value['x'] as num?)?.toDouble() ?? 0,
        y: (value['y'] as num?)?.toDouble() ?? 0,
        width: (value['width'] as num?)?.toDouble() ?? 0,
        height: (value['height'] as num?)?.toDouble() ?? 0,
      );

  final int windowId;
  final String title;
  final double x;
  final double y;
  final double width;
  final double height;

  String get description =>
      '${width.round()}×${height.round()} at (${x.round()}, ${y.round()}) • ID $windowId';
}

class QianniuConversationRow {
  const QianniuConversationRow({
    required this.customer,
    required this.unread,
    required this.unreadEvidence,
    required this.evidenceAvailable,
    this.unreadAgeSeconds,
  });

  factory QianniuConversationRow.fromMap(Map<Object?, Object?> value) =>
      QianniuConversationRow(
        customer: value['customer']?.toString() ?? '',
        unread: value['unread'] == true,
        unreadEvidence: (value['unreadEvidence'] as num?)?.toInt() ?? 0,
        evidenceAvailable: value['evidenceAvailable'] == true,
        unreadAgeSeconds: (value['unreadAgeSeconds'] as num?)?.toInt(),
      );

  final String customer;
  final bool unread;
  final int unreadEvidence;
  final bool evidenceAvailable;

  /// Elapsed time shown by JD's red unread badge, when confidently readable.
  final int? unreadAgeSeconds;
}

class OcrObservation {
  const OcrObservation({
    required this.text,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory OcrObservation.fromMap(Map<Object?, Object?> value) => OcrObservation(
        text: value['text'] as String? ?? '',
        confidence: (value['confidence'] as num?)?.toDouble() ?? 0,
        x: (value['x'] as num?)?.toDouble() ?? 0,
        y: (value['y'] as num?)?.toDouble() ?? 0,
        width: (value['width'] as num?)?.toDouble() ?? 0,
        height: (value['height'] as num?)?.toDouble() ?? 0,
      );

  final String text;
  final double confidence;
  final double x;
  final double y;
  final double width;
  final double height;
}

class OcrInspection {
  const OcrInspection({
    required this.image,
    required this.imageWidth,
    required this.imageHeight,
    required this.windowTitle,
    required this.recognizedText,
    required this.observations,
    required this.capturedAt,
    this.visualRegions = const [],
    this.windowId = 0,
    this.activeCustomerId,
    this.ocrEngine = 'unknown',
    this.chatLeft,
    this.chatRight,
    this.chatBottom,
  });

  factory OcrInspection.fromMap(Map<String, Object?> value) {
    final rawObservations = value['observations'] as List<Object?>? ?? const [];
    final rawVisualRegions =
        value['visualRegions'] as List<Object?>? ?? const [];
    final chatRegion = value['chatRegion'] as Map<Object?, Object?>?;
    return OcrInspection(
      image: base64Decode(value['pngBase64'] as String? ?? ''),
      imageWidth: (value['imageWidth'] as num?)?.toInt() ?? 0,
      imageHeight: (value['imageHeight'] as num?)?.toInt() ?? 0,
      windowTitle: value['windowTitle'] as String? ?? 'JD 咚咚工作台',
      recognizedText: value['recognizedText'] as String? ?? '',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
          (value['capturedAtMs'] as num?)?.toInt() ?? 0),
      activeCustomerId: value['activeCustomerId'] as String?,
      windowId: (value['windowId'] as num?)?.toInt() ?? 0,
      ocrEngine: value['ocrEngine'] as String? ?? 'unknown',
      chatLeft: (chatRegion?['left'] as num?)?.toDouble(),
      chatRight: (chatRegion?['right'] as num?)?.toDouble(),
      chatBottom: (chatRegion?['bottom'] as num?)?.toDouble(),
      observations: rawObservations
          .whereType<Map<Object?, Object?>>()
          .map(OcrObservation.fromMap)
          .toList(growable: false),
      visualRegions: rawVisualRegions
          .whereType<Map<Object?, Object?>>()
          .map(OcrVisualRegion.fromMap)
          .toList(growable: false),
    );
  }

  final Uint8List image;
  final int imageWidth;
  final int imageHeight;
  final String windowTitle;
  final String recognizedText;
  final List<OcrObservation> observations;
  final List<OcrVisualRegion> visualRegions;
  final DateTime capturedAt;
  final int windowId;
  final String? activeCustomerId;
  final String ocrEngine;
  final double? chatLeft;
  final double? chatRight;
  final double? chatBottom;
}

class OcrVisualRegion {
  const OcrVisualRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  factory OcrVisualRegion.fromMap(Map<Object?, Object?> value) =>
      OcrVisualRegion(
        x: (value['x'] as num?)?.toDouble() ?? 0,
        y: (value['y'] as num?)?.toDouble() ?? 0,
        width: (value['width'] as num?)?.toDouble() ?? 0,
        height: (value['height'] as num?)?.toDouble() ?? 0,
        confidence: (value['confidence'] as num?)?.toDouble() ?? 0,
      );

  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;
}

class VisibleImagePayload {
  const VisibleImagePayload({
    required this.kind,
    this.mimeType,
    this.extension,
    this.originalName,
    this.visualFingerprint,
    this.captureSource,
    this.bytes,
  });

  factory VisibleImagePayload.fromMap(Map<String, Object?> value) =>
      VisibleImagePayload(
        kind: value['kind']?.toString() ?? 'unsupported',
        mimeType: value['mimeType'] as String?,
        extension: value['extension'] as String?,
        originalName: value['originalName'] as String?,
        visualFingerprint: value['visualFingerprint'] as String?,
        captureSource: value['captureSource'] as String?,
        bytes: value['dataBase64'] is String
            ? base64Decode(value['dataBase64']! as String)
            : null,
      );

  final String kind;
  final String? mimeType;
  final String? extension;
  final String? originalName;
  final String? visualFingerprint;
  final String? captureSource;
  final Uint8List? bytes;
}

class DownloadedVideoPayload {
  const DownloadedVideoPayload({
    required this.path,
    required this.originalName,
    required this.mimeType,
  });

  factory DownloadedVideoPayload.fromMap(Map<String, Object?> value) =>
      DownloadedVideoPayload(
        path: value['path']?.toString() ?? '',
        originalName: value['originalName']?.toString() ?? 'customer-video.mp4',
        mimeType: value['mimeType']?.toString() ?? 'video/mp4',
      );

  final String path;
  final String originalName;
  final String mimeType;
}

class CachedMediaPayload {
  const CachedMediaPayload({
    required this.kind,
    required this.cacheKey,
    required this.cacheModifiedAt,
    this.image,
    this.video,
  });

  final String kind;
  final String cacheKey;
  final DateTime cacheModifiedAt;
  final VisibleImagePayload? image;
  final DownloadedVideoPayload? video;
}

class SpeechTranscription {
  const SpeechTranscription({
    required this.transcript,
    required this.language,
    required this.confidence,
    required this.speechDetected,
  });

  factory SpeechTranscription.fromMap(Map<String, Object?> value) =>
      SpeechTranscription(
        transcript: value['transcript']?.toString().trim() ?? '',
        language: value['language']?.toString() ?? '',
        confidence: (value['confidence'] as num?)?.toDouble() ?? 0,
        speechDetected: value['speechDetected'] == true,
      );

  final String transcript;
  final String language;
  final double confidence;
  final bool speechDetected;
}
