import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Read-only resources travel with the app; customer state never does.
class AppRuntime {
  static const standalone = bool.fromEnvironment('JD_STANDALONE');
  static const appName =
      String.fromEnvironment('JD_APP_NAME', defaultValue: 'JD Automation');
  static const knowledgeName = '格志京东客服知识库-2026-10-04';

  static Directory? bundleResources({String? executablePath}) {
    final executable = executablePath ?? Platform.resolvedExecutable;
    final macos = Directory(p.dirname(executable));
    final contents = macos.parent;
    if (p.basename(macos.path) != 'MacOS' ||
        p.basename(contents.path) != 'Contents' ||
        !contents.parent.path.endsWith('.app')) {
      return null;
    }
    return Directory(p.join(contents.path, 'Resources', 'jd_runtime'));
  }

  static Future<RuntimeResources> resources(Directory dataRoot,
      {Map<String, String>? environment,
      String? executablePath,
      bool requireBundle = standalone}) async {
    final env = environment ?? Platform.environment;
    final bundle = bundleResources(executablePath: executablePath);
    final bundled = bundle != null && (requireBundle || await bundle.exists());
    final defaultRoot = bundled ? bundle : dataRoot.parent;
    if (requireBundle && bundle == null) {
      throw const FileSystemException('Standalone app bundle is missing.');
    }
    String? override(String name, String legacy) =>
        _nonempty(env[name]) ?? _nonempty(env[legacy]);
    return RuntimeResources(
      workspace: Directory(
          override('JD_CODEX_WORKSPACE', 'QIANNIU_CODEX_WORKSPACE') ??
              p.join(defaultRoot.path, 'codex_workspace')),
      knowledge: Directory(
          override('JD_KNOWLEDGE_DIR', 'QIANNIU_KNOWLEDGE_DIR') ??
              p.join(defaultRoot.path, knowledgeName)),
    );
  }

  static Future<String?> bundledTool(String name,
      {String? executablePath}) async {
    final bundle = bundleResources(executablePath: executablePath);
    if (bundle == null) return null;
    final candidate = p.join(bundle.path, 'bin', name);
    return await File(candidate).exists() ? candidate : null;
  }

  static Future<String?> findCodex(
      {Map<String, String>? environment, String? extensionArchitecture}) async {
    final env = environment ?? Platform.environment;
    final home = _nonempty(env['HOME']);
    final configured = _nonempty(env['CODEX_EXECUTABLE']);
    // An explicit override is authoritative, including when it is invalid.
    if (configured != null) {
      return await File(configured).exists() ? configured : null;
    }
    final candidates = <String>[
      if (_nonempty(env['CODEX_INSTALL_DIR']) case final String directory)
        p.join(directory, 'codex'),
      if (home != null) p.join(home, '.local', 'bin', 'codex'),
      '/opt/homebrew/bin/codex',
      '/usr/local/bin/codex',
      if (home != null) p.join(home, '.npm-global', 'bin', 'codex'),
      if (home != null) p.join(home, 'bin', 'codex'),
      for (final directory in (env['PATH'] ?? '').split(':'))
        if (p.isAbsolute(directory)) p.join(directory, 'codex'),
    ];
    for (final candidate in candidates.toSet()) {
      if (await File(candidate).exists()) return candidate;
    }
    if (home == null) return null;
    final nodeVersions = Directory(p.join(home, '.nvm', 'versions', 'node'));
    if (await nodeVersions.exists()) {
      final versions = await nodeVersions
          .list()
          .where((e) => e is Directory)
          .cast<Directory>()
          .toList();
      versions.sort((a, b) => b.path.compareTo(a.path));
      for (final version in versions) {
        final candidate = p.join(version.path, 'bin', 'codex');
        if (await File(candidate).exists()) return candidate;
      }
    }
    final extensions = Directory(p.join(home, '.vscode', 'extensions'));
    if (!await extensions.exists()) return null;
    final directories = await extensions
        .list()
        .where((entry) =>
            entry is Directory &&
            p.basename(entry.path).startsWith('openai.chatgpt-'))
        .cast<Directory>()
        .toList();
    directories.sort((a, b) => b.path.compareTo(a.path));
    final architecture = extensionArchitecture ??
        (Abi.current() == Abi.macosArm64 ? 'macos-aarch64' : 'macos-x64');
    for (final directory in directories) {
      final candidate = p.join(directory.path, 'bin', architecture, 'codex');
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  /// Finder's PATH omits Homebrew and often npm's Node interpreter.
  static Map<String, String> processEnvironment(String codex,
      {Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final home = _nonempty(env['HOME']);
    return {
      'PATH': <String>{
        p.dirname(codex),
        ...?env['PATH']?.split(':'),
        if (home != null) p.join(home, '.local', 'bin'),
        '/opt/homebrew/bin',
        '/usr/local/bin',
        '/usr/bin',
        '/bin',
        '/usr/sbin',
        '/sbin',
      }.where((value) => p.isAbsolute(value)).join(':'),
    };
  }

  static String? _nonempty(String? value) =>
      value == null || value.trim().isEmpty ? null : value;
}

class RuntimeResources {
  const RuntimeResources({required this.workspace, required this.knowledge});
  final Directory workspace;
  final Directory knowledge;
}
