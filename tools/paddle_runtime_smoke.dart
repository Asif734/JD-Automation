import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
        'Usage: dart run tools/paddle_runtime_smoke.dart <runtime> <image>');
    exitCode = 64;
    return;
  }
  final process = await Process.start(arguments[0], const []);
  final lines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  final errors = process.stderr.transform(utf8.decoder).join();
  await lines.firstWhere((line) {
    try {
      return (jsonDecode(line) as Map<String, dynamic>)['event'] == 'ready';
    } catch (_) {
      return false;
    }
  }).timeout(const Duration(seconds: 90));
  final bytes = await File(arguments[1]).readAsBytes();
  process.stdin.writeln(jsonEncode({
    'id': 'standalone-smoke',
    'pngBase64': base64Encode(bytes),
  }));
  await process.stdin.flush();
  final responseLine = await lines.firstWhere((line) {
    try {
      return (jsonDecode(line) as Map<String, dynamic>)['id'] ==
          'standalone-smoke';
    } catch (_) {
      return false;
    }
  }).timeout(const Duration(seconds: 90));
  final response = jsonDecode(responseLine) as Map<String, dynamic>;
  if (response['error'] != null) throw StateError('${response['error']}');
  final observations = response['observations'] as List<Object?>? ?? const [];
  final visualRegions = response['visualRegions'] as List<Object?>? ?? const [];
  stdout.writeln(
      'observations=${observations.length} visual_regions=${visualRegions.length}');
  stdout.writeln(observations
      .whereType<Map<String, dynamic>>()
      .map((item) => item['text'])
      .where((text) =>
          text.toString().contains('TP879') ||
          text.toString().contains('jd_41aeec'))
      .join('\n'));
  await process.stdin.close();
  process.kill();
  final stderrText = await errors;
  if (stderrText.contains('Library not loaded')) {
    throw StateError(stderrText);
  }
}
