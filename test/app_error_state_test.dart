import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/runtime/app_error_state.dart';
import 'package:jd_automation/storage/diagnostic_log.dart';

void main() {
  late Directory root;
  late DiagnosticLog log;
  late AppErrorState state;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('jd-ui-error-test-');
    log = DiagnosticLog(() async => root);
    state = AppErrorState(log: log);
  });

  tearDown(() async {
    await log.flush();
    await root.delete(recursive: true);
  });

  Future<List<Map<String, dynamic>>> events() async {
    await log.flush();
    final files = await root.list().where((entry) => entry is File).toList();
    final lines = <String>[];
    for (final file in files.cast<File>()) {
      lines.addAll(await file.readAsLines());
    }
    return lines
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
  }

  test('platform error persists exactly as displayed after banner is cleared',
      () async {
    final error = PlatformException(
      code: 'customer_identity_mismatch',
      message: 'Expected 格志打印机贝贝, observed jd_6c67c99371fa4',
      details: {'expectedCustomerId': '格志打印机贝贝'},
    );
    state.value = error;
    final displayed = state.displayedText;
    expect(displayed, 'Error: $error');
    state.value = null;
    expect(state.value, isNull);
    expect(state.displayedText, isNull);

    final saved = (await events()).single;
    expect(saved['operation'], 'ui.error');
    expect(saved['surface'], 'error_banner');
    expect(saved['displayedText'], displayed);
    expect(saved['code'], error.code);
    expect(saved['message'], error.message);
    expect(saved['errorType'], 'PlatformException');
    expect(saved['pid'], pid);
    expect(saved['executable'], Platform.resolvedExecutable);
    expect(DateTime.parse(saved['timestamp'] as String).isUtc, isTrue);
  });

  test('timeouts, plain errors, and repeated occurrences are all retained',
      () async {
    final errors = <Object>[
      TimeoutException('Opening customer chat', const Duration(seconds: 8)),
      StateError('Invalid history owner'),
      'Video capture failed',
      'Video capture failed',
    ];
    for (final error in errors) {
      state.value = error;
      state.value = null;
    }
    expect((await events()).map((event) => event['displayedText']),
        errors.map((error) => 'Error: $error'));
  });

  test('diagnostics-panel errors are saved without replacing the banner',
      () async {
    final error = StateError('No verified video match');
    final text = 'JD video download failed: $error';
    state.record(error, displayedText: text, surface: 'diagnostics');
    expect(state.value, isNull);
    final saved = (await events()).single;
    expect(saved['surface'], 'diagnostics');
    expect(saved['displayedText'], text);
    expect(saved['error'], error.toString());
  });

  test('unavailable log directory cannot break error display or future logging',
      () async {
    var unavailable = true;
    log = DiagnosticLog(() async {
      if (unavailable) throw const FileSystemException('Log directory blocked');
      return root;
    });
    state = AppErrorState(log: log);
    state.value = 'First error';
    await log.flush();
    expect(state.displayedText, 'Error: First error');
    unavailable = false;
    state.value = 'Second error';
    expect((await events()).single['displayedText'], 'Error: Second error');
  });
}
