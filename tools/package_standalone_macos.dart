import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// Packages only runtime evidence and media tools. No customer data, auth,
// environment files, source repository, or Codex executable is distributed.
Future<void> main(List<String> args) async {
  if (args.length != 1 || !args.single.endsWith('.app')) {
    throw ArgumentError(
        'Usage: dart run tools/package_standalone_macos.dart <app>');
  }
  final project = Directory.current.absolute;
  final app = Directory(args.single).absolute;
  if (!await File(p.join(app.path, 'Contents', 'Info.plist')).exists()) {
    throw StateError('Built app is missing: ${app.path}');
  }
  final runtime =
      Directory(p.join(app.path, 'Contents', 'Resources', 'jd_runtime'));
  // Clear only the validated, generated runtime directory inside this app.
  if (await runtime.exists()) await runtime.delete(recursive: true);
  await runtime.create(recursive: true);
  const knowledgeName = '格志京东客服知识库-2026-10-04';
  final sourceKnowledge = Directory(p.join(project.path, knowledgeName));
  final packagedKnowledge = Directory(p.join(runtime.path, knowledgeName));
  await packagedKnowledge.create();
  await for (final entry in sourceKnowledge.list(followLinks: false)) {
    if (entry is File &&
        (entry.path.endsWith('_kb.md') ||
            p.basename(entry.path) ==
                'customer_service_high_priority_issues.md')) {
      await entry.copy(p.join(packagedKnowledge.path, p.basename(entry.path)));
    }
  }
  final cards = Directory(p.join(packagedKnowledge.path, 'rag_cards'));
  await cards.create();
  await for (final entry in Directory(p.join(sourceKnowledge.path, 'rag_cards'))
      .list(followLinks: false)) {
    if (entry is File &&
        (entry.path.endsWith('.json') || entry.path.endsWith('.jsonl'))) {
      await entry.copy(p.join(cards.path, p.basename(entry.path)));
    }
  }
  final workspace = Directory(p.join(runtime.path, 'codex_workspace'));
  await workspace.create();
  for (final name in [
    'AGENTS.md',
    'reply.schema.json',
    'search_plan.schema.json'
  ]) {
    await File(p.join(project.path, 'codex_workspace', name))
        .copy(p.join(workspace.path, name));
  }
  for (final required in [
    p.join(cards.path, 'customer_service_rag_cards.jsonl'),
    p.join(cards.path, 'source_chunks.jsonl'),
    p.join(packagedKnowledge.path, 'product_model_feature_catalog_kb.md'),
  ]) {
    if (!await File(required).exists()) {
      throw StateError('Missing runtime evidence: $required');
    }
  }

  final bin = Directory(p.join(runtime.path, 'bin'));
  final libs = Directory(p.join(runtime.path, 'lib'));
  await bin.create();
  await libs.create();
  final originals = <String, String>{}; // install name -> packaged file
  final realTargets = <String, String>{};
  final dependencyEdges = <String, Map<String, String>>{};
  final cellarRoots = <String>{};
  final queue = <String>[];

  Future<String> copyBinary(String source, {bool executable = false}) async {
    final known = originals[source];
    if (known != null) return known;
    final real = await File(source).resolveSymbolicLinks();
    if (realTargets[real] case final String target) {
      originals[source] = target;
      return target;
    }
    final target =
        p.join(executable ? bin.path : libs.path, p.basename(source));
    if (realTargets.values.contains(target)) {
      throw StateError('Conflicting bundled library name: $target');
    }
    await File(real).copy(target);
    await run('chmod', ['u+w', target]);
    originals[source] = target;
    realTargets[real] = target;
    queue.add(real);
    final parts = p.split(real);
    final cellar = parts.indexOf('Cellar');
    if (cellar >= 0 && parts.length > cellar + 2) {
      cellarRoots.add(p.joinAll(parts.take(cellar + 3)));
    }
    return target;
  }

  for (final name in ['ffmpeg', 'ffprobe']) {
    final configured = Platform.environment['JD_${name.toUpperCase()}'];
    final candidates = [
      if (configured != null) configured,
      '/opt/homebrew/bin/$name',
      '/usr/local/bin/$name',
    ];
    String? source;
    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        source = candidate;
        break;
      }
    }
    if (source == null) {
      throw StateError(
          '$name is needed on the build Mac for standalone video support.');
    }
    await copyBinary(source, executable: true);
  }
  for (var i = 0; i < queue.length; i++) {
    final source = queue[i];
    final target = realTargets[source]!;
    final edges = <String, String>{};
    final listing = await run('otool', ['-L', source]);
    final dependencyLines = const LineSplitter()
        .convert(listing)
        .skip(target.endsWith('.dylib') ? 2 : 1);
    for (final line in dependencyLines) {
      final dependency = line.trim().split(' (').first;
      if (dependency.startsWith('/System/Library/') ||
          dependency.startsWith('/usr/lib/')) {
        continue;
      }
      if (!p.isAbsolute(dependency)) {
        throw StateError(
            'Unresolved non-system dependency: $dependency in $source');
      }
      final dependencyReal = await File(dependency).resolveSymbolicLinks();
      if (dependencyReal == source) {
        continue; // dylib install ID, not a dependency
      }
      edges[dependency] = await copyBinary(dependency);
    }
    dependencyEdges[target] = edges;
  }
  var minimumMacOS = '15.0';
  for (final entry in realTargets.entries) {
    final target = entry.value;
    final architectures = await run('lipo', ['-archs', target]);
    if (!architectures.split(RegExp(r'\s+')).contains('arm64')) {
      throw StateError(
          'Bundled video tool is not Apple Silicon compatible: $target');
    }
    final commands = await run('otool', ['-l', target]);
    final minimumVersions = [
      ...RegExp(r'\bminos (\d+\.\d+(?:\.\d+)?)').allMatches(commands),
      ...RegExp(
              r'cmd LC_VERSION_MIN_MACOS\s+cmdsize \d+\s+version (\d+\.\d+(?:\.\d+)?)')
          .allMatches(commands),
    ];
    for (final match in minimumVersions) {
      final version = match.group(1)!;
      if (newerVersion(version, minimumMacOS)) minimumMacOS = version;
    }
    for (final edge in dependencyEdges[target]!.entries) {
      await run('install_name_tool', [
        '-change',
        edge.key,
        '@loader_path/${p.relative(edge.value, from: p.dirname(target))}',
        target
      ]);
    }
    if (target.endsWith('.dylib')) {
      await run(
          'install_name_tool', ['-id', '@rpath/${p.basename(target)}', target]);
    }
    await run('codesign', ['--force', '--sign', '-', target]);
  }
  final notices = Directory(p.join(runtime.path, 'third_party_notices'));
  await notices.create();
  for (final root in cellarRoots) {
    final destination = Directory(p.join(
        notices.path, '${p.basename(p.dirname(root))}-${p.basename(root)}'));
    await destination.create();
    await for (final entry in Directory(root).list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (entry is File &&
          (name.toUpperCase().startsWith('LICENSE') ||
              name.toUpperCase().startsWith('COPYING') ||
              name == 'INSTALL_RECEIPT.json' ||
              name == 'sbom.spdx.json')) {
        await entry.copy(p.join(destination.path, name));
      }
    }
    final formulas = Directory(p.join(root, '.brew'));
    if (await formulas.exists()) {
      await for (final entry in formulas.list(followLinks: false)) {
        if (entry is File && entry.path.endsWith('.rb')) {
          await entry.copy(p.join(destination.path, p.basename(entry.path)));
        }
      }
    }
  }
  await run('/usr/libexec/PlistBuddy', [
    '-c',
    'Set :LSMinimumSystemVersion $minimumMacOS',
    p.join(app.path, 'Contents', 'Info.plist')
  ]);
  await File(p.join(runtime.path, 'package_manifest.json'))
      .writeAsString(const JsonEncoder.withIndent('  ').convert({
    'app_name': 'JD Automation Standalone',
    'bundle_id': 'com.grozziie.jdAutomation.standalone',
    'architecture': 'arm64',
    'minimum_macos': minimumMacOS,
    'knowledge': knowledgeName,
    'external_dependency': 'Installed, authenticated Codex CLI and JD Jingmai',
    'bundled_media_binaries': realTargets.values
        .map((s) => p.relative(s, from: runtime.path))
        .toList(),
    'excludes': ['customer data', 'credentials', 'Codex sessions'],
  }));
  for (final name in ['ffmpeg', 'ffprobe']) {
    await run(p.join(bin.path, name), ['-version']);
  }
  stdout.writeln(
      'Packaged runtime evidence and ${realTargets.length} media binaries; macOS $minimumMacOS+.');
}

bool newerVersion(String a, String b) {
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l > r;
  }
  return false;
}

Future<String> run(String command, List<String> args) async {
  final result = await Process.run(command, args);
  if (result.exitCode != 0) {
    throw StateError('$command failed (${result.exitCode}): ${result.stderr}');
  }
  return result.stdout.toString();
}
