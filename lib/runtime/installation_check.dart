import 'dart:convert';
import 'dart:io';

import '../codex/codex_reply_service.dart';
import '../storage/capture_database.dart';
import 'app_runtime.dart';

/// Installer smoke check: no customer database is opened and no JD capture,
/// generation, or delivery is started.
Future<void> checkInstallation() async {
  try {
    final database = CaptureDatabase();
    final data = await database.storageRoot;
    final service = await CodexReplyService.discover(database);
    final tools = <String, String>{};
    for (final name in ['ffmpeg', 'ffprobe']) {
      final binary = await AppRuntime.bundledTool(name);
      if (binary == null) throw StateError('Bundled $name is missing.');
      final result = await Process.run(binary, ['-version'])
          .timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) throw StateError('$name failed to launch.');
      tools[name] = binary;
    }
    stdout.writeln(jsonEncode({
      'app_name': AppRuntime.appName,
      'standalone': AppRuntime.standalone,
      'data_directory': data.path,
      'workspace': service.workspace.path,
      'knowledge': service.knowledgeDirectory.path,
      'codex': service.executable,
      'bundled_tools': tools,
    }));
    exit(0);
  } catch (error) {
    stderr.writeln('Installation check failed: $error');
    exit(78);
  }
}
