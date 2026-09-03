import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/ocr_capture_extractor.dart';
import 'package:jd_automation/platform/macos_capture_adapter.dart';

void main() {
  test('detects a JD colleague transfer notice as a system event', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2550,
      imageHeight: 1640,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      windowId: 1,
      capturedAt: DateTime.now(),
      activeCustomerId: 'jd_41aeec7741d05',
      observations: const [
        OcrObservation(
            text: '您的同事格志打印机艳艳将客户jd_41aeec7741d05转接给您!',
            confidence: 0.99,
            x: 0.30,
            y: 0.40,
            width: 0.30,
            height: 0.03),
        OcrObservation(
            text: 'jd_41aeec7741d05 14:13:01',
            confidence: 0.99,
            x: 0.25,
            y: 0.25,
            width: 0.15,
            height: 0.03),
        OcrObservation(
            text: 'hello',
            confidence: 0.99,
            x: 0.25,
            y: 0.29,
            width: 0.08,
            height: 0.03),
      ],
    );

    final result = const OcrCaptureExtractor().analyze(inspection);

    expect(result.transferNoticeVisible, isTrue);
    expect(result.capture!.messages.single.body, 'hello');
  });

  test('detects the JD session-summary transfer format', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2550,
      imageHeight: 1640,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      windowId: 1,
      capturedAt: DateTime.now(),
      activeCustomerId: 'jd_41aeec7741d05',
      observations: const [
        OcrObservation(
            text: '用户诉求：催促转接',
            confidence: 0.99,
            x: 0.30,
            y: 0.40,
            width: 0.20,
            height: 0.03),
      ],
    );

    final result = const OcrCaptureExtractor().analyze(inspection);

    expect(result.transferNoticeVisible, isTrue);
    expect(result.capture, isNull);
  });

  test('does not save a transfer summary merged into a customer bubble', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2550,
      imageHeight: 1640,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      windowId: 1,
      capturedAt: DateTime.now(),
      activeCustomerId: 'jd_41aeec7741d05',
      observations: const [
        OcrObservation(
            text: 'jd_41aeec7741d05 16:57:00',
            confidence: 1,
            x: .22,
            y: .30,
            width: .18,
            height: .02),
        OcrObservation(
            text: '请你转给子账号小甘 Grozziie 您好老板',
            confidence: 1,
            x: .24,
            y: .34,
            width: .28,
            height: .02),
        OcrObservation(
            text: '上次会话小结',
            confidence: 1,
            x: .25,
            y: .38,
            width: .12,
            height: .02),
        OcrObservation(
            text: '用户诉求：催促转接',
            confidence: 1,
            x: .25,
            y: .42,
            width: .16,
            height: .02),
      ],
    );

    final result = const OcrCaptureExtractor().analyze(inspection);

    expect(result.transferNoticeVisible, isTrue);
    expect(result.capture, isNull);
  });

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
    expect(capture.messages.last.sentAt, DateTime(2026, 8, 25, 9, 40, 20));
  });

  test('preserves a time-only JD bubble timestamp on the capture date', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2550,
      imageHeight: 1640,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      windowId: 1,
      capturedAt: DateTime(2026, 8, 31, 18, 18, 46),
      activeCustomerId: 'jd_41aeec7741d05',
      observations: const [
        OcrObservation(
            text: 'jd_41aeec7741d05 18:18:16',
            confidence: 1,
            x: .22,
            y: .30,
            width: .18,
            height: .02),
        OcrObservation(
            text: 'not finding the machine',
            confidence: 1,
            x: .23,
            y: .34,
            width: .18,
            height: .02),
      ],
    );

    final message =
        const OcrCaptureExtractor().extract(inspection)!.messages.single;
    expect(message.sentAt, DateTime(2026, 8, 31, 18, 18, 16));
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

  test('captures current JD seller-name format during human handoff', () {
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
            text: '17:38:38 格志打印机小甘',
            confidence: 1,
            x: .47,
            y: .48,
            width: .15,
            height: .02),
        OcrObservation(
            text: 'ok', confidence: 1, x: .49, y: .52, width: .02, height: .02),
        OcrObservation(
            text: '17:39:12 格志打印机小甘',
            confidence: 1,
            x: .47,
            y: .60,
            width: .15,
            height: .02),
        OcrObservation(
            text: 'i will sent in a moment',
            confidence: 1,
            x: .43,
            y: .64,
            width: .16,
            height: .02),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection);

    expect(capture, isNotNull);
    expect(capture!.messages, hasLength(2));
    expect(capture.messages.every((message) => message.direction == 'outgoing'),
        isTrue);
    expect(capture.messages.map((message) => message.body),
        ['ok', 'i will sent in a moment']);
  });

  test('captures newest customer body with a large bottom-layout gap', () {
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
            text: '15:59:06 格志打印机小甘',
            confidence: 1,
            x: .45,
            y: .58,
            width: .15,
            height: .02),
        OcrObservation(
            text: 'well, please let me know, how can i help you',
            confidence: 1,
            x: .39,
            y: .62,
            width: .22,
            height: .02),
        OcrObservation(
            text: 'jd_41aeec7741d05 16:00:20',
            confidence: 1,
            x: .42,
            y: .69,
            width: .18,
            height: .02),
        OcrObservation(
            text: 'we are done for now',
            confidence: 1,
            x: .46,
            y: .79,
            width: .12,
            height: .02),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection);

    expect(capture, isNotNull);
    expect(capture!.messages.last.direction, 'incoming');
    expect(capture.messages.last.body, 'we are done for now');
  });

  test('reconstructs every line of a multiline customer bubble', () {
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
            text: 'jd_41aeec7741d05 16:35:47',
            confidence: 1,
            x: .22,
            y: .40,
            width: .18,
            height: .02),
        OcrObservation(
            text: 'what is the model no of your face',
            confidence: 1,
            x: .22,
            y: .44,
            width: .25,
            height: .02),
        OcrObservation(
            text: 'attendance machine?',
            confidence: 1,
            x: .22,
            y: .47,
            width: .14,
            height: .02),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection);

    expect(capture!.messages.single.body,
        'what is the model no of your face attendance machine?');
  });

  test('keeps a left-shifted final line under the same customer sender', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2550,
      imageHeight: 1640,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      capturedAt: DateTime(2026, 9, 1, 13, 31, 49),
      activeCustomerId: 'jd_41aeec7741d05',
      observations: const [
        OcrObservation(
            text: 'jd_41aeec7741d05 13:31:43',
            confidence: 1,
            x: .22,
            y: .48,
            width: .18,
            height: .02),
        OcrObservation(
            text: 'thanks, hope you are doing well. am i',
            confidence: 1,
            x: .22,
            y: .52,
            width: .30,
            height: .025),
        OcrObservation(
            text: 'right?',
            confidence: 1,
            x: .16,
            y: .555,
            width: .045,
            height: .025),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection)!;

    expect(capture.messages.single.body,
        'thanks, hope you are doing well. am i right?');
  });

  test('removes Apple Vision standalone trailing D artifact', () {
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
            text: 'jd_41aeec7741d05 16:17:46',
            confidence: 1,
            x: .22,
            y: .40,
            width: .18,
            height: .02),
        OcrObservation(
            text: 'great it is Working well',
            confidence: 1,
            x: .22,
            y: .44,
            width: .20,
            height: .02),
        OcrObservation(
            text: 'D', confidence: .8, x: .22, y: .47, width: .01, height: .02),
      ],
    );

    final result = const OcrCaptureExtractor().analyze(inspection);

    expect(result.capture!.messages.single.body, 'great it is Working well');
    expect(result.latestIncomingHasText, isTrue);
  });

  test('removes trailing D plus JD control glyph without changing model D', () {
    OcrExtractionAttempt extract(String body) =>
        const OcrCaptureExtractor().analyze(OcrInspection(
          image: Uint8List(0),
          imageWidth: 2550,
          imageHeight: 1640,
          windowTitle: '咚咚融合工作台',
          recognizedText: '',
          capturedAt: DateTime(2026, 9, 1, 17),
          activeCustomerId: 'jd_41aeec7741d05',
          observations: [
            const OcrObservation(
                text: 'jd_41aeec7741d05 17:00:00',
                confidence: 1,
                x: .22,
                y: .40,
                width: .18,
                height: .02),
            OcrObservation(
                text: body,
                confidence: .9,
                x: .22,
                y: .44,
                width: .30,
                height: .02),
          ],
        ));

    expect(
        extract('it is not connecting with my android device D 回')
            .capture!
            .messages
            .single
            .body,
        'it is not connecting with my android device');
    expect(extract('这是一台打印机，无法通过 Wi-Fi 连接。D 回').capture!.messages.single.body,
        '这是一台打印机，无法通过 Wi-Fi 连接。');
    expect(extract('My model is M880D').capture!.messages.single.body,
        'My model is M880D');
  });

  test('drops an image-area D artifact so the turn remains image-only', () {
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
            text: 'jd_41aeec7741d05 16:11:23',
            confidence: 1,
            x: .22,
            y: .40,
            width: .18,
            height: .02),
        OcrObservation(
            text: 'D', confidence: .8, x: .23, y: .45, width: .01, height: .02),
      ],
    );

    final result = const OcrCaptureExtractor().analyze(inspection);

    expect(result.capture, isNull);
    expect(result.latestIncomingHasText, isFalse);
    expect(result.copyTarget, isNotNull);
  });

  test('treats Apple Vision image control glyphs as image-only', () {
    OcrExtractionAttempt extract(String artifact) =>
        const OcrCaptureExtractor().analyze(OcrInspection(
          image: Uint8List(0),
          imageWidth: 2550,
          imageHeight: 1640,
          windowTitle: '咚咚融合工作台',
          recognizedText: '',
          capturedAt: DateTime(2026, 9, 1, 16, 50),
          activeCustomerId: 'jd_41aeec7741d05',
          observations: [
            const OcrObservation(
                text: 'jd_41aeec7741d05 16:50:00',
                confidence: 1,
                x: .22,
                y: .40,
                width: .18,
                height: .02),
            OcrObservation(
                text: artifact,
                confidence: .8,
                x: .23,
                y: .45,
                width: .03,
                height: .02),
          ],
        ));

    for (final artifact in ['◎ 回', 'g 回', '•']) {
      final result = extract(artifact);
      expect(result.capture, isNull, reason: artifact);
      expect(result.latestIncomingHasText, isFalse, reason: artifact);
      expect(result.latestVisibleSenderIsIncoming, isTrue, reason: artifact);
    }
  });

  test('removes every C30 artifact and its trailing control glyph', () {
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
            text: 'jd_41aeec7741d05 16:35:23',
            confidence: 1,
            x: .22,
            y: .40,
            width: .18,
            height: .02),
        OcrObservation(
            text: '接下来我们 C30 要做的就是将 Grozzie 应用程序与打印机连接起来。',
            confidence: 1,
            x: .22,
            y: .44,
            width: .32,
            height: .02),
        OcrObservation(
            text: 'C30 回',
            confidence: .8,
            x: .54,
            y: .44,
            width: .025,
            height: .02),
      ],
    );

    final body = const OcrCaptureExtractor()
        .analyze(inspection)
        .capture!
        .messages
        .single
        .body;

    expect(body, '接下来我们要做的就是将 Grozzie 应用程序与打印机连接起来。');
  });

  test('keeps a three-line purchase request with separated OCR line gaps', () {
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
            text: 'jd_41aeec7741d05 11:10:13',
            confidence: 1,
            x: .22,
            y: .30,
            width: .18,
            height: .018),
        OcrObservation(
            text: 'i am doing well too.',
            confidence: 1,
            x: .23,
            y: .35,
            width: .15,
            height: .018),
        OcrObservation(
            text: 'i need to buy an attendance machine.',
            confidence: 1,
            x: .23,
            y: .405,
            width: .29,
            height: .018),
        OcrObservation(
            text: 'what do you suggest?',
            confidence: 1,
            x: .23,
            y: .46,
            width: .17,
            height: .018),
      ],
    );

    final message =
        const OcrCaptureExtractor().extract(inspection)!.messages.single;
    expect(message.body,
        'i am doing well too. i need to buy an attendance machine. what do you suggest?');
  });

  test('joins every OCR box in a sender-bounded TP732 message', () {
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
            text: 'jd_41aeec7741d05 12:26:20',
            confidence: 1,
            x: .22,
            y: .30,
            width: .18,
            height: .018),
        OcrObservation(
            text: 'how to connect',
            confidence: 1,
            x: .24,
            y: .35,
            width: .10,
            height: .016),
        OcrObservation(
            text: 'tp732',
            confidence: 1,
            x: .35,
            y: .46,
            width: .05,
            height: .016),
        OcrObservation(
            text: 'to the',
            confidence: 1,
            x: .41,
            y: .57,
            width: .05,
            height: .016),
        OcrObservation(
            text: 'macbook.',
            confidence: 1,
            x: .24,
            y: .68,
            width: .07,
            height: .016),
        OcrObservation(
            text: '12:26:39 格志打印机小甘',
            confidence: 1,
            x: .40,
            y: .75,
            width: .18,
            height: .018),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection)!;
    expect(capture.messages.first.body, 'how to connect tp732 to the macbook.');
  });

  test('concatenates the exact wrapped TP32 customer message', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2550,
      imageHeight: 1640,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      capturedAt: DateTime(2026, 8, 31, 18, 46, 1),
      activeCustomerId: 'jd_41aeec7741d05',
      observations: const [
        OcrObservation(
            text: 'jd_41aeec7741d05 18:45:59',
            confidence: 1,
            x: .22,
            y: .40,
            width: .18,
            height: .02),
        OcrObservation(
            text: 'i am not able to setup tp32 printer to',
            confidence: 1,
            x: .23,
            y: .44,
            width: .28,
            height: .02),
        OcrObservation(
            text: 'my phone. check this',
            confidence: 1,
            x: .23,
            y: .47,
            width: .14,
            height: .02),
      ],
    );

    final message =
        const OcrCaptureExtractor().extract(inspection)!.messages.single;
    expect(message.body,
        'i am not able to setup tp32 printer to my phone. check this');
    expect(message.sentAt, DateTime(2026, 8, 31, 18, 45, 59));
  });

  test('reconstructs multiline text even when sender and bubble x differ', () {
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
            text: 'jd_41aeec7741d05 17:52:59',
            confidence: 1,
            x: .21,
            y: .38,
            width: .18,
            height: .02),
        OcrObservation(
            text: 'i am not able to connect attendance',
            confidence: 1,
            x: .34,
            y: .42,
            width: .25,
            height: .02),
        OcrObservation(
            text: 'machine with the grozzie app. can',
            confidence: 1,
            x: .34,
            y: .45,
            width: .24,
            height: .02),
        OcrObservation(
            text: 'you tell me, how i can i do that?',
            confidence: 1,
            x: .34,
            y: .48,
            width: .22,
            height: .02),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection);

    expect(capture!.messages.single.body,
        'i am not able to connect attendance machine with the grozzie app. can you tell me, how i can i do that?');
  });

  test('detects a clipped colleague transfer banner and excludes it as chat',
      () {
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
            text: 'jd_41aeec7741d05 17:52:00',
            confidence: 1,
            x: .21,
            y: .30,
            width: .18,
            height: .02),
        OcrObservation(
            text: '您的同事格志打印机艳艳将客户jd_41aeec7741',
            confidence: 1,
            x: .30,
            y: .34,
            width: .30,
            height: .02),
      ],
    );

    final result = const OcrCaptureExtractor().analyze(inspection);

    expect(result.transferNoticeVisible, isTrue);
    expect(result.capture, isNull);
  });

  test('orders same-line OCR words left to right despite y jitter', () {
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
            text: 'jd_41aeec7741d05 16:36:09',
            confidence: 1,
            x: .22,
            y: .40,
            width: .18,
            height: .02),
        OcrObservation(
            text: 'real',
            confidence: 1,
            x: .28,
            y: .443,
            width: .03,
            height: .02),
        OcrObservation(
            text: 'do you',
            confidence: 1,
            x: .22,
            y: .446,
            width: .05,
            height: .02),
        OcrObservation(
            text: 'have face attendance',
            confidence: 1,
            x: .32,
            y: .441,
            width: .15,
            height: .02),
        OcrObservation(
            text: 'machine?',
            confidence: 1,
            x: .22,
            y: .475,
            width: .07,
            height: .02),
      ],
    );

    final capture = const OcrCaptureExtractor().extract(inspection);

    expect(capture!.messages.single.body,
        'do you real have face attendance machine?');
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

    expect(result.latestIncomingHasText, isFalse);

    expect(result.capture, isNotNull);
    expect(result.copyTarget, isNotNull);
    expect(result.copyTarget!.y, closeTo(.68, .001));
  });
}
