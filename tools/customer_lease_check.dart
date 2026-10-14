import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:jd_automation/runtime/automation_lease.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    final lease = AutomationLease(Directory(args[1]));
    final acquired = await lease.acquire();
    stdout.writeln(acquired ? 'acquired' : 'busy');
    if (!acquired) exit(3);
    if (args.first == 'hold') await stdin.first;
    await lease.release();
    return;
  }
  final root = await Directory.systemTemp.createTemp('jd-lease-check-');
  Process? first;
  try {
    final script = Platform.script.toFilePath();
    first = await Process.start(
        Platform.resolvedExecutable, [script, 'hold', root.path]);
    final ready = await first.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    if (ready != 'acquired') {
      throw StateError(
          'First test process could not acquire its isolated lock.');
    }
    final second = await Process.run(
        Platform.resolvedExecutable, [script, 'probe', root.path]);
    if (second.exitCode != 3 || second.stdout.toString().trim() != 'busy') {
      throw StateError('A second process acquired the same lock.');
    }
    first.kill(ProcessSignal.sigkill);
    await first.exitCode;
    final recovered = await Process.run(
        Platform.resolvedExecutable, [script, 'probe', root.path]);
    if (recovered.exitCode != 0) {
      throw StateError('The lock was not released after the simulated crash.');
    }
    stdout.writeln(
        'Automation lease: competing process rejected; crash recovery passed. Temporary lock only.');
  } finally {
    first?.kill();
    await root.delete(recursive: true);
  }
}
