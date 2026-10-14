import 'package:flutter/services.dart';

import '../storage/diagnostic_log.dart';

/// Keeps the error banner and its durable diagnostic entry in sync.
class AppErrorState {
  AppErrorState({this.log});

  final DiagnosticLog? log;
  Object? _value;

  Object? get value => _value;
  String? get displayedText => _value == null ? null : 'Error: $_value';

  set value(Object? error) {
    _value = error;
    if (error != null) record(error, displayedText: displayedText!);
  }

  void record(Object error,
      {required String displayedText, String surface = 'error_banner'}) {
    log?.record('ui.error', fields: {
      'surface': surface,
      'displayedText': displayedText,
      'errorType': error.runtimeType.toString(),
      'error': error.toString(),
      if (error is PlatformException) 'code': error.code,
      if (error is PlatformException) 'message': error.message,
    });
  }
}
