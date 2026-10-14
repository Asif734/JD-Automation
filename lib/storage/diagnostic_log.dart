import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Local diagnostic events contain identities, operation metadata, and errors
/// exactly as displayed. Do not explicitly attach chat bodies or credentials.
class DiagnosticLog {
  DiagnosticLog(this.directory);

  final Future<Directory> Function() directory;
  Future<void> _tail = Future<void>.value();

  void record(String operation, {Map<String, Object?> fields = const {}}) {
    final now = DateTime.now().toUtc();
    final event = <String, Object?>{
      'timestamp': now.toIso8601String(),
      'pid': pid,
      'executable': Platform.resolvedExecutable,
      'operation': operation,
      ...fields,
    };
    _tail = _tail.then((_) async {
      final root = await directory();
      await root.create(recursive: true);
      final day =
          now.add(const Duration(hours: 6)).toIso8601String().substring(0, 10);
      await File('${root.path}/$day-$pid.jsonl').writeAsString(
          '${jsonEncode(event)}\n',
          mode: FileMode.append,
          flush: true);
    }).catchError((Object _) {
      // Logging failure must never stop capture or change a send decision.
    });
  }

  Future<void> flush() => _tail;
}
