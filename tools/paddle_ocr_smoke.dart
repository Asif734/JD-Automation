import 'dart:convert';
import 'dart:io';

import 'package:jd_automation/ocr/paddle_ocr_service.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tools/paddle_ocr_smoke.dart <image.png>');
    exitCode = 64;
    return;
  }
  final bytes = await File(arguments.single).readAsBytes();
  final service = PaddleOcrService();
  final result = await service.recognize(
    base64Encode(bytes),
    imageWidth: 0,
    imageHeight: 0,
  );
  for (final observation in result.observations) {
    stdout.writeln(observation['text']);
  }
  stdout.writeln('visual_regions=${result.visualRegions.length}');
  await service.close();
}
