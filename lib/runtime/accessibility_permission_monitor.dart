import 'dart:async';

import 'package:flutter/widgets.dart';

/// Read-only permission refresh. Never prompts or starts automation.
class AccessibilityPermissionMonitor with WidgetsBindingObserver {
  AccessibilityPermissionMonitor({
    required this.readStatus,
    required this.onStatus,
    required this.onError,
    this.pollInterval = const Duration(seconds: 2),
    this.responseTimeout = const Duration(seconds: 5),
  });

  final Future<Map<String, Object?>> Function() readStatus;
  final void Function(Map<String, Object?>) onStatus;
  final void Function(Object, StackTrace) onError;
  final Duration pollInterval;
  final Duration responseTimeout;
  Timer? _timer;
  Future<void>? _refreshing;
  bool _started = false;
  bool _disposed = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    return _refreshing ??= Future<void>.microtask(() async {
      try {
        final status = await readStatus().timeout(responseTimeout);
        if (_disposed) return;
        onStatus(status);
        if (status['trusted'] == true) {
          _timer?.cancel();
          _timer = null;
        } else {
          _armPoll();
        }
      } catch (error, stack) {
        if (_disposed) return;
        onError(error, stack);
        _armPoll();
      } finally {
        _refreshing = null;
      }
    });
  }

  void _armPoll() {
    if (_disposed || !_started) return;
    _timer ??= Timer.periodic(pollInterval, (_) => unawaited(refresh()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }
}
