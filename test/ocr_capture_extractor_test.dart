import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/ocr_capture_extractor.dart';
import 'package:jd_automation/platform/macos_capture_adapter.dart';

void main() {
  test('extracts latest incoming message for full customer identity', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2620,
      imageHeight: 1600,
      windowTitle: '接待中心',
      recognizedText: '',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(1234),
      activeCustomerId: 'stoneshishininger',
      observations: const [
        OcrObservation(
            text: 'stoneshishininger',
            confidence: 1,
            x: .61,
            y: .20,
            width: .1,
            height: .02),
        OcrObservation(
            text: 'stoneshishininger',
            confidence: .98,
            x: .22,
            y: .55,
            width: .1,
            height: .02),
        OcrObservation(
            text: '2026-08-25 09:28:06',
            confidence: .95,
            x: .33,
            y: .55,
            width: .12,
            height: .02),
        OcrObservation(
            text: '3',
            confidence: .99,
            x: .22,
            y: .58,
            width: .01,
            height: .02),
        OcrObservation(
            text: 'stoneshishininger',
            confidence: .98,
            x: .22,
            y: .68,
            width: .1,
            height: .02),
        OcrObservation(
            text: '2026-08-25 09:40:20',
            confidence: .95,
            x: .33,
            y: .68,
            width: .12,
            height: .02),
        OcrObservation(
            text: 'hi',
            confidence: .99,
            x: .22,
            y: .71,
            width: .02,
            height: .02),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection);
    expect(capture, isNotNull);
    expect(capture!.customerExternalId, 'stoneshishininger');
    expect(capture.messages.map((message) => message.body), ['3', 'hi']);
    expect(capture.messages.last.stableId, startsWith('ocr:'));
  });

  test('refuses a scan without a full customer identity', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 1,
      imageHeight: 1,
      windowTitle: '接待中心',
      recognizedText: '',
      capturedAt: DateTime.now(),
      observations: const [
        OcrObservation(
            text: 'stoneshishinin...',
            confidence: 1,
            x: .1,
            y: .4,
            width: .1,
            height: .02),
        OcrObservation(
            text: 'hi', confidence: 1, x: .2, y: .5, width: .02, height: .02),
      ],
    );
    expect(const OcrCaptureExtractor().extract(inspection), isNull);
  });

  test('accepts a truncated OCR sender after AX supplies exact identity', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2620,
      imageHeight: 1600,
      windowTitle: '接待中心',
      recognizedText: '',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(5678),
      activeCustomerId: 'yangxingkaishininger',
      observations: const [
        OcrObservation(
            text: 'yangxingkaishin...',
            confidence: .96,
            x: .22,
            y: .62,
            width: .1,
            height: .02),
        OcrObservation(
            text: 'Do you have this printer?',
            confidence: .98,
            x: .22,
            y: .66,
            width: .18,
            height: .02),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection);
    expect(capture, isNotNull);
    expect(capture!.customerExternalId, 'yangxingkaishininger');
    expect(capture.messages.single.body, 'Do you have this printer?');
  });

  test('rejects a Qianniu sidebar recency label as message content', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2620,
      imageHeight: 1600,
      windowTitle: '接待中心',
      recognizedText: '',
      capturedAt: DateTime.now(),
      activeCustomerId: 'stoneshishininger',
      observations: const [
        OcrObservation(
            text: 'stoneshishininger',
            confidence: 1,
            x: .22,
            y: .60,
            width: .1,
            height: .02),
        OcrObservation(
            text: '11秒',
            confidence: 1,
            x: .22,
            y: .64,
            width: .03,
            height: .02),
      ],
    );
    expect(const OcrCaptureExtractor().extract(inspection), isNull);
  });

  test('uses latest sender when Vision merges customer and timestamp', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2620,
      imageHeight: 1600,
      windowTitle: '接待中心',
      recognizedText: '',
      capturedAt: DateTime.now(),
      activeCustomerId: 'stoneshishininger',
      observations: const [
        OcrObservation(
            text: 'stoneshishininger',
            confidence: 1,
            x: .22,
            y: .45,
            width: .10,
            height: .02),
        OcrObservation(
            text: 'what about this portable machine?',
            confidence: 1,
            x: .22,
            y: .49,
            width: .22,
            height: .02),
        OcrObservation(
            text: 'stoneshishininger 2026-08-26 11:03:13',
            confidence: .95,
            x: .22,
            y: .62,
            width: .25,
            height: .02),
        OcrObservation(
            text: 'ok. we will talk later',
            confidence: 1,
            x: .22,
            y: .66,
            width: .16,
            height: .02),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection);
    expect(capture, isNotNull);
    expect(capture!.messages.map((message) => message.body),
        ['what about this portable machine?', 'ok. we will talk later']);
  });

  test('captures a manually sent seller reply as outgoing', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2620,
      imageHeight: 1600,
      windowTitle: '接待中心',
      recognizedText: '',
      capturedAt: DateTime.fromMillisecondsSinceEpoch(9000),
      activeCustomerId: 'stoneshishininger',
      observations: const [
        OcrObservation(
            text: 'stoneshishininger',
            confidence: 1,
            x: .22,
            y: .45,
            width: .10,
            height: .02),
        OcrObservation(
            text: 'Can you help me?',
            confidence: 1,
            x: .22,
            y: .49,
            width: .12,
            height: .02),
        OcrObservation(
            text: '加普威旗舰店:小雷',
            confidence: 1,
            x: .22,
            y: .56,
            width: .12,
            height: .02),
        OcrObservation(
            text: '2026-08-26 15:10:00',
            confidence: 1,
            x: .34,
            y: .56,
            width: .12,
            height: .02),
        OcrObservation(
            text: 'Yes, I can help you.',
            confidence: 1,
            x: .22,
            y: .60,
            width: .14,
            height: .02),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection);
    expect(capture, isNotNull);
    expect(capture!.messages, hasLength(2));
    expect(capture.messages.first.direction, 'incoming');
    expect(capture.messages.last.direction, 'outgoing');
    expect(capture.messages.last.body, 'Yes, I can help you.');
    expect(capture.messages.last.sender, '加普威旗舰店:小雷');
  });

  test('fingerprint tolerates OCR whitespace variation', () {
    OcrInspection inspection(String body) => OcrInspection(
          image: Uint8List(0),
          imageWidth: 2620,
          imageHeight: 1600,
          windowTitle: '接待中心',
          recognizedText: '',
          capturedAt: DateTime.now(),
          activeCustomerId: 'stoneshishininger',
          observations: [
            const OcrObservation(
                text: 'stoneshishininger',
                confidence: 1,
                x: .22,
                y: .45,
                width: .10,
                height: .02),
            const OcrObservation(
                text: '2026-08-26 15:12:10',
                confidence: 1,
                x: .34,
                y: .45,
                width: .12,
                height: .02),
            OcrObservation(
                text: body,
                confidence: 1,
                x: .22,
                y: .49,
                width: .20,
                height: .02),
          ],
        );

    final joined = const OcrCaptureExtractor()
        .extract(inspection('how can ipurchase it'))!;
    final spaced = const OcrCaptureExtractor()
        .extract(inspection('how can i purchase it'))!;
    expect(joined.messages.single.stableId, spaced.messages.single.stableId);
  });

  test('targets a newest image-only sender instead of an older text body', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2550,
      imageHeight: 1640,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      capturedAt: DateTime.now(),
      activeCustomerId: 'jd_41aeec7741d05',
      observations: const [
        OcrObservation(
            text: 'jd_41aeec7741d05',
            confidence: 1,
            x: .22,
            y: .28,
            width: .10,
            height: .02),
        OcrObservation(
            text: 'I am sending a photo',
            confidence: 1,
            x: .22,
            y: .32,
            width: .16,
            height: .02),
        OcrObservation(
            text: '加普威旗舰店:小雷',
            confidence: 1,
            x: .22,
            y: .43,
            width: .12,
            height: .02),
        OcrObservation(
            text: 'Please send it.',
            confidence: 1,
            x: .22,
            y: .47,
            width: .10,
            height: .02),
        OcrObservation(
            text: 'jd_41aeec7741d05',
            confidence: 1,
            x: .22,
            y: .64,
            width: .10,
            height: .02),
      ],
    );

    final result = const OcrCaptureExtractor().analyze(inspection);

    expect(result.capture, isNotNull);
    expect(result.copyTarget, isNotNull);
    expect(result.copyTarget!.y, closeTo(.68, .001));
  });
}
