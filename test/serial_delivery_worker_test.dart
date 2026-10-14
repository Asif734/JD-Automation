import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/runtime/serial_delivery_worker.dart';

void main() {
  test('a synchronous reentrant request shares the already-published worker',
      () async {
    var delivered = false;
    Future<void>? reentrant;
    late SerialDeliveryWorker<String> worker;
    worker = SerialDeliveryWorker<String>(
      enabled: () => true,
      next: () {
        if (delivered) return Future.value(null);
        reentrant = worker.request();
        return Future.value('customer');
      },
      deliver: (_) async {
        delivered = true;
        return true;
      },
      failed: (_, error, stack) async => fail('Unexpected failure'),
      onError: (error, stack) => fail('Unexpected worker error: $error'),
    );
    final request = worker.request();
    await request;
    expect(identical(request, reentrant), isTrue);
    expect(worker.isRunning, isFalse);
    expect(delivered, isTrue);
  });
  test('a deferred item releases the worker instead of spinning on the head',
      () async {
    var attempts = 0;
    var failCount = 0;
    final worker = SerialDeliveryWorker<String>(
      enabled: () => true,
      next: () async => 'saved-customer',
      deliver: (_) async {
        attempts++;
        return false;
      },
      failed: (_, error, stack) async {
        failCount++;
      },
      onError: (error, stack) => fail('Unexpected error: $error'),
    );
    await worker.request();
    expect(worker.isRunning, isFalse);
    expect(attempts, 1);
    expect(failCount, 0);
  });

  test('an independent periodic tick recovers from a queue read failure',
      () async {
    var readFails = true;
    var delivered = false;
    final errors = <Object>[];
    final completed = Completer<void>();
    final worker = SerialDeliveryWorker<String>(
      enabled: () => !delivered,
      next: () async {
        if (readFails) throw StateError('Temporary storage failure');
        return 'saved-customer';
      },
      deliver: (_) async {
        delivered = true;
        completed.complete();
        return true;
      },
      failed: (_, error, stack) async => fail('Unexpected send failure'),
      onError: (error, stack) => errors.add(error),
    );
    await worker.request();
    expect(worker.isRunning, isFalse);
    expect(errors, hasLength(1));
    readFails = false;
    // No capture/generation event requests delivery after storage recovers.
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      unawaited(worker.request());
    });
    addTearDown(timer.cancel);
    await completed.future.timeout(const Duration(seconds: 2));
    expect(delivered, isTrue);
  });

  test(
      'a failed retry-state write releases the worker and retains its queue item',
      () async {
    final saved = ['customer-a', 'customer-b'];
    var failureWriteFails = true;
    final errors = <Object>[];
    final delivered = <String>[];
    final worker = SerialDeliveryWorker<String>(
      enabled: () => true,
      next: () async => saved.firstOrNull,
      deliver: (item) async {
        if (failureWriteFails) throw StateError('Native callback failed');
        delivered.add(item);
        saved.remove(item);
        return true;
      },
      failed: (_, error, stack) async {
        throw StateError('Retry-state write failed');
      },
      onError: (error, stack) => errors.add(error),
    );
    await worker.request();
    expect(saved, ['customer-a', 'customer-b']);
    expect(worker.isRunning, isFalse);
    expect(errors, hasLength(1));
    failureWriteFails = false;
    await worker.request();
    expect(delivered, ['customer-a', 'customer-b']);
    expect(saved, isEmpty);
  });
}
