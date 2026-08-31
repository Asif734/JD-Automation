import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/capture/ocr_image_candidate_selector.dart';
import 'package:jd_automation/platform/macos_capture_adapter.dart';

void main() {
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
}
