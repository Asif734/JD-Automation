import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/ocr_image_candidate_selector.dart';
import 'package:jd_automation/capture/ocr_capture_extractor.dart';
import 'package:jd_automation/platform/macos_capture_adapter.dart';

void main() {
  test('creates a bounded screenshot fallback for an image-only block', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 1600,
      imageHeight: 1300,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      capturedAt: DateTime.now(),
      activeCustomerId: 'jd_test',
      chatLeft: .12,
      chatRight: .72,
      chatBottom: .90,
      observations: const [
        OcrObservation(
            text: 'jd_test 11:13:35',
            confidence: 1,
            x: .13,
            y: .30,
            width: .15,
            height: .025),
        OcrObservation(
            text: '格志打印机小甘',
            confidence: .5,
            x: .18,
            y: .45,
            width: .09,
            height: .015),
        OcrObservation(
            text: 'jd_test 11:13:42',
            confidence: 1,
            x: .13,
            y: .62,
            width: .15,
            height: .025),
        OcrObservation(
            text: 'check this',
            confidence: 1,
            x: .14,
            y: .67,
            width: .10,
            height: .025),
      ],
      visualRegions: const [],
    );

    final fallback = const OcrImageCandidateSelector()
        .fallbackLatestCustomerBlock(inspection, 'jd_test');

    expect(fallback, isNotNull);
    expect(fallback!.y, greaterThan(.32));
    expect(fallback.y + fallback.height, lessThan(.62));
    expect(fallback.x + fallback.width, lessThanOrEqualTo(.72));
  });

  test('does not screenshot an ordinary text-only block', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 1600,
      imageHeight: 1300,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      capturedAt: DateTime.now(),
      activeCustomerId: 'jd_test',
      chatLeft: .12,
      chatRight: .72,
      chatBottom: .90,
      observations: const [
        OcrObservation(
            text: 'jd_test 11:13:42',
            confidence: 1,
            x: .13,
            y: .62,
            width: .15,
            height: .025),
        OcrObservation(
            text: 'check this',
            confidence: 1,
            x: .14,
            y: .67,
            width: .10,
            height: .025),
      ],
      visualRegions: const [],
    );

    expect(
        const OcrImageCandidateSelector()
            .fallbackLatestCustomerBlock(inspection, 'jd_test'),
        isNull);
  });

  test('rejects a text-dense chat bubble rectangle as an image', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 2550,
      imageHeight: 1640,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      capturedAt: DateTime.now(),
      activeCustomerId: 'jd_test',
      observations: const [
        OcrObservation(
            text: 'jd_test 17:52:59',
            confidence: 1,
            x: .22,
            y: .30,
            width: .12,
            height: .02),
        OcrObservation(
            text: 'i am not able to connect attendance',
            confidence: 1,
            x: .23,
            y: .34,
            width: .25,
            height: .02),
        OcrObservation(
            text: 'machine with the grozzie app',
            confidence: 1,
            x: .23,
            y: .37,
            width: .22,
            height: .02),
        OcrObservation(
            text: 'can you tell me how to do that',
            confidence: 1,
            x: .23,
            y: .40,
            width: .21,
            height: .02),
      ],
      visualRegions: const [
        OcrVisualRegion(x: .21, y: .33, width: .30, height: .11, confidence: 1),
      ],
    );

    final candidates =
        const OcrImageCandidateSelector().select(inspection, 'jd_test');

    expect(candidates, isEmpty);
    // The same rectangle still needs native video classification: a customer
    // may have filmed a text-filled screen rather than typed that text.
    final videoCandidates = const OcrImageCandidateSelector()
        .select(inspection, 'jd_test', includeTextDense: true);
    expect(videoCandidates, hasLength(1));
  });

  OcrInspection inspection({required List<OcrObservation> observations}) =>
      OcrInspection(
        image: Uint8List(0),
        imageWidth: 2550,
        imageHeight: 1640,
        windowTitle: '咚咚融合工作台',
        recognizedText: '',
        capturedAt: DateTime.now(),
        activeCustomerId: 'jd_41aeec7741d05',
        observations: observations,
        visualRegions: const [
          OcrVisualRegion(
              x: .29, y: .48, width: .25, height: .12, confidence: .9),
        ],
      );

  test('rejects outgoing text rectangle after the seller label', () {
    final result = const OcrImageCandidateSelector().select(
      inspection(observations: const [
        OcrObservation(
            text: 'jd_41aeec7741d05 11:06:58',
            confidence: 1,
            x: .22,
            y: .40,
            width: .16,
            height: .02),
        OcrObservation(
            text: '11:07:19 格志打印机小甘',
            confidence: 1,
            x: .45,
            y: .44,
            width: .16,
            height: .02),
      ]),
      'jd_41aeec7741d05',
    );

    expect(result, isEmpty);
  });

  test('accepts a photo fully inside the customer message block', () {
    final result = const OcrImageCandidateSelector().select(
      inspection(observations: const [
        OcrObservation(
            text: 'jd_41aeec7741d05 11:06:58',
            confidence: 1,
            x: .22,
            y: .40,
            width: .16,
            height: .02),
        OcrObservation(
            text: '11:08:00 格志打印机小甘',
            confidence: 1,
            x: .45,
            y: .65,
            width: .16,
            height: .02),
      ]),
      'jd_41aeec7741d05',
    );

    expect(result, hasLength(1));
  });

  test('accepts a wide customer video preview', () {
    final inspection = OcrInspection(
      image: Uint8List(0),
      imageWidth: 960,
      imageHeight: 532,
      windowTitle: '咚咚融合工作台',
      recognizedText: '',
      capturedAt: DateTime.now(),
      activeCustomerId: 'jd_41aeec7741d05',
      chatLeft: .10,
      chatRight: .80,
      observations: const [
        OcrObservation(
            text: 'jd_41aeec7741d05 18:02:59',
            confidence: 1,
            x: .11,
            y: .08,
            width: .29,
            height: .04),
      ],
      visualRegions: const [
        OcrVisualRegion(
            x: .115, y: .147, width: .50, height: .51, confidence: .9),
      ],
    );
    // The label is visible but above the text extractor's sender band.
    expect(const OcrCaptureExtractor().analyze(inspection).capture, isNull);
    final result = const OcrImageCandidateSelector().select(
      inspection,
      'jd_41aeec7741d05',
      includeTextDense: true,
    );

    expect(result, hasLength(1));
  });

  test('accepts wide unlabeled media in a verified active chat', () {
    final result = const OcrImageCandidateSelector().select(
      OcrInspection(
        image: Uint8List(0),
        imageWidth: 960,
        imageHeight: 532,
        windowTitle: '咚咚融合工作台',
        recognizedText: '',
        capturedAt: DateTime.now(),
        activeCustomerId: 'jd_41aeec7741d05',
        chatLeft: .10,
        chatRight: .80,
        visualRegions: const [
          OcrVisualRegion(
              x: .115, y: .147, width: .50, height: .51, confidence: .9),
        ],
        observations: const [],
      ),
      'jd_41aeec7741d05',
      allowUnlabeledLatestImage: true,
      includeTextDense: true,
    );

    expect(result, hasLength(1));
  });

  test('does not attribute an unlabeled seller-side rectangle to customer', () {
    final result = const OcrImageCandidateSelector().select(
      OcrInspection(
        image: Uint8List(0),
        imageWidth: 960,
        imageHeight: 532,
        windowTitle: '咚咚融合工作台',
        recognizedText: '',
        capturedAt: DateTime.now(),
        activeCustomerId: 'jd_41aeec7741d05',
        chatLeft: .10,
        chatRight: .80,
        visualRegions: const [
          OcrVisualRegion(
              x: .42, y: .147, width: .36, height: .30, confidence: .9),
        ],
        observations: const [],
      ),
      'jd_41aeec7741d05',
      allowUnlabeledLatestImage: true,
      includeTextDense: true,
    );

    expect(result, isEmpty);
  });
}
