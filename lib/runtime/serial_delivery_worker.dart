/// Drains durable delivery work serially. A failed customer is rescheduled by
/// [failed] before another customer is selected; it cannot monopolize the queue.
class SerialDeliveryWorker<T> {
  SerialDeliveryWorker({
    required this.enabled,
    required this.next,
    required this.deliver,
    required this.failed,
    required this.onError,
    this.afterAttempt,
  });

  final bool Function() enabled;
  final Future<T?> Function() next;
  final Future<bool> Function(T) deliver;
  final Future<void> Function(T, Object, StackTrace) failed;
  final void Function(Object, StackTrace) onError;
  final Future<void> Function()? afterAttempt;
  bool _running = false;
  bool _requested = false;
  Future<void>? _current;

  bool get isRunning => _running;

  Future<void> request() {
    if (!enabled()) return Future<void>.value();
    _requested = true;
    if (_running) return _current!;
    _running = true;
    // Publish the shared future before invoking callbacks, including callbacks
    // that synchronously request another drain.
    return _current = Future<void>.microtask(_drain);
  }

  Future<void> _drain() async {
    try {
      do {
        _requested = false;
        while (enabled()) {
          final item = await next();
          if (item == null || !enabled()) break;
          try {
            // A false result means paused, superseded, or deferred work. Do
            // not spin forever on an unchanged queue head in this drain.
            if (!await deliver(item)) break;
          } catch (error, stack) {
            await failed(item, error, stack);
          }
          await afterAttempt?.call();
        }
      } while (_requested && enabled());
    } catch (error, stack) {
      // A database/refresh failure releases the worker too. A later independent
      // recovery tick can restart it without an unhandled async exception.
      onError(error, stack);
    } finally {
      _running = false;
    }
  }
}
