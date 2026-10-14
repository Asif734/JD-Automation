import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/runtime/accessibility_permission_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(bool Function() condition) async {
    final until = DateTime.now().add(const Duration(seconds: 2));
    while (!condition() && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  test('grant is detected automatically and repeated polling stops', () async {
    var trusted = false;
    var reads = 0;
    final updates = <Map<String, Object?>>[];
    final monitor = AccessibilityPermissionMonitor(
      readStatus: () async {
        reads++;
        return {'trusted': trusted};
      },
      onStatus: updates.add,
      onError: (error, stack) => fail('Unexpected status error: $error'),
      pollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(monitor.dispose);
    monitor.start();
    await waitFor(() => updates.isNotEmpty);
    expect(updates.last['trusted'], isFalse);
    trusted = true;
    await waitFor(() => updates.last['trusted'] == true);
    final afterGrant = reads;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(reads, afterGrant);
  });

  test('returning from Settings refreshes and detects permission revocation',
      () async {
    var trusted = true;
    final updates = <Map<String, Object?>>[];
    final monitor = AccessibilityPermissionMonitor(
      readStatus: () async => {
        'trusted': trusted,
        'appBundleIdentifier': 'com.grozziie.jdAutomation.review'
      },
      onStatus: updates.add,
      onError: (error, stack) => fail('Unexpected status error: $error'),
      pollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(monitor.dispose);
    monitor.start();
    await waitFor(() => updates.isNotEmpty);
    trusted = false;
    monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await waitFor(() => updates.last['trusted'] == false);
    trusted = true;
    await waitFor(() => updates.last['trusted'] == true);
    expect(updates.last['appBundleIdentifier'],
        'com.grozziie.jdAutomation.review');
  });

  test('overlapping refresh requests share a single native status read',
      () async {
    final response = Completer<Map<String, Object?>>();
    var reads = 0;
    final monitor = AccessibilityPermissionMonitor(
      readStatus: () {
        reads++;
        return response.future;
      },
      onStatus: (_) {},
      onError: (error, stack) => fail('Unexpected status error: $error'),
    );
    addTearDown(monitor.dispose);
    final requests = List.generate(30, (_) => monitor.refresh());
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    response.complete({'trusted': true});
    await Future.wait(requests);
  });

  test('dispose ignores late status callbacks and performs no more reads',
      () async {
    final response = Completer<Map<String, Object?>>();
    final updates = <Map<String, Object?>>[];
    var reads = 0;
    final monitor = AccessibilityPermissionMonitor(
      readStatus: () {
        reads++;
        return response.future;
      },
      onStatus: updates.add,
      onError: (error, stack) => fail('Unexpected status error: $error'),
    );
    monitor.start();
    await Future<void>.delayed(Duration.zero);
    monitor.dispose();
    response.complete({'trusted': false});
    await monitor.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(updates, isEmpty);
    expect(reads, 1);
  });

  test('a lost status callback is bounded and a later refresh recovers',
      () async {
    final lost = Completer<Map<String, Object?>>();
    var available = false;
    final errors = <Object>[];
    final updates = <Map<String, Object?>>[];
    final monitor = AccessibilityPermissionMonitor(
      readStatus: () =>
          available ? Future.value({'trusted': true}) : lost.future,
      onStatus: updates.add,
      onError: (error, stack) => errors.add(error),
      responseTimeout: const Duration(milliseconds: 20),
      pollInterval: const Duration(milliseconds: 10),
    );
    addTearDown(monitor.dispose);
    monitor.start();
    await waitFor(() => errors.isNotEmpty);
    expect(errors.first, isA<TimeoutException>());
    available = true;
    await waitFor(() => updates.isNotEmpty && updates.last['trusted'] == true);
  });
}
