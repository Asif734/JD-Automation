import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/capture_models.dart';
import 'capture_adapter.dart';

class MacOSCaptureAdapter implements CaptureAdapter {
  MacOSCaptureAdapter({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  static const _channelName = 'com.grozziie.jdAutomation/accessibility';
  final MethodChannel _channel;
  final _captures = StreamController<CapturedConversation>.broadcast();
  final _diagnostics = StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<CapturedConversation> get captures => _captures.stream;

  @override
  Stream<Map<String, Object?>> get diagnostics => _diagnostics.stream;

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

  Future<Map<String, Object?>> sendDraftOnce({
    required String expectedCustomer,
    required String reply,
    List<String> mediaPaths = const [],
  }) async {
    final value = await _mapCall('sendDraftOnce', <String, Object?>{
      'expectedCustomer': expectedCustomer,
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
  }) async {
    final value = await _mapCall('captureImageRegion', <String, Object?>{
      'expectedCustomer': expectedCustomer,
      'windowId': windowId,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    });
    if (value['error'] case final String code) {
      throw PlatformException(
          code: code,
          message:
              value['message'] as String? ?? 'Image-region capture failed.');
    }
    return VisibleImagePayload.fromMap(value);
  }

  Future<MessageClassification> classifyMessageAt({
    required String expectedCustomer,
    required int windowId,
    required double x,
    required double y,
  }) async {
    final value = await _mapCall('classifyMessageAt', <String, Object?>{
      'expectedCustomer': expectedCustomer,
      'windowId': windowId,
      'x': x,
      'y': y,
    });
    return MessageClassification(
      kind: value['kind']?.toString() ?? 'unknown',
      visualFingerprint: value['visualFingerprint']?.toString(),
    );
  }

  Future<VisibleImagePayload> downloadImageAt({
    required String expectedCustomer,
    required int windowId,
    required double x,
    required double y,
  }) async {
    final value = await _mapCall('downloadImageAt', <String, Object?>{
      'expectedCustomer': expectedCustomer,
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
    final value = await _mapCall('openConversation', <String, Object?>{
      'expectedCustomer': expectedCustomer,
      'allowActivation': allowActivation,
    });
    if (value['error'] case final String code) {
      throw PlatformException(
          code: code,
          message:
              value['message'] as String? ?? 'Could not open conversation.');
    }
  }

  Future<void> scrollConversation(
      {required String expectedCustomer, required int deltaY}) async {
    final value = await _mapCall('scrollConversation', <String, Object?>{
      'expectedCustomer': expectedCustomer,
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
  const MessageClassification({required this.kind, this.visualFingerprint});

  final String kind;
  final String? visualFingerprint;
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
  });

  factory QianniuConversationRow.fromMap(Map<Object?, Object?> value) =>
      QianniuConversationRow(
        customer: value['customer']?.toString() ?? '',
        unread: value['unread'] == true,
        unreadEvidence: (value['unreadEvidence'] as num?)?.toInt() ?? 0,
        evidenceAvailable: value['evidenceAvailable'] == true,
      );

  final String customer;
  final bool unread;
  final int unreadEvidence;
  final bool evidenceAvailable;
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
  });

  factory OcrInspection.fromMap(Map<String, Object?> value) {
    final rawObservations = value['observations'] as List<Object?>? ?? const [];
    final rawVisualRegions =
        value['visualRegions'] as List<Object?>? ?? const [];
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
    this.bytes,
  });

  factory VisibleImagePayload.fromMap(Map<String, Object?> value) =>
      VisibleImagePayload(
        kind: value['kind']?.toString() ?? 'unsupported',
        mimeType: value['mimeType'] as String?,
        extension: value['extension'] as String?,
        originalName: value['originalName'] as String?,
        visualFingerprint: value['visualFingerprint'] as String?,
        bytes: value['dataBase64'] is String
            ? base64Decode(value['dataBase64']! as String)
            : null,
      );

  final String kind;
  final String? mimeType;
  final String? extension;
  final String? originalName;
  final String? visualFingerprint;
  final Uint8List? bytes;
}
