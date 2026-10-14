import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/runtime/app_runtime.dart';

void main() {
  late Directory root;
  late String executable;
  late Directory bundle;
  late Directory data;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('jd_standalone_test_');
    executable =
        '${root.path}/Other Mac/JD Automation Standalone.app/Contents/MacOS/JD Automation Standalone';
    bundle = AppRuntime.bundleResources(executablePath: executable)!;
    data = Directory('${root.path}/Application Support/standalone/data');
  });
  tearDown(() => root.delete(recursive: true));

  test('bundle resources are relative to the moved app, not the build Mac',
      () async {
    await bundle.create(recursive: true);
    final resources = await AppRuntime.resources(data,
        environment: {}, executablePath: executable, requireBundle: true);
    expect(resources.workspace.path, '${bundle.path}/codex_workspace');
    expect(
        resources.knowledge.path, '${bundle.path}/${AppRuntime.knowledgeName}');
    expect(resources.workspace.path, isNot(startsWith(data.path)));
  });

  test('standalone cannot silently use an old external knowledge folder',
      () async {
    final resources = await AppRuntime.resources(data,
        environment: {}, executablePath: executable, requireBundle: true);
    expect(resources.workspace.path, '${bundle.path}/codex_workspace');
    expect(await resources.workspace.exists(), isFalse);
  });

  test('development resources retain the existing data sibling layout',
      () async {
    final resources = await AppRuntime.resources(data,
        environment: {}, executablePath: '/usr/bin/dart', requireBundle: false);
    expect(resources.workspace.path, '${data.parent.path}/codex_workspace');
    expect(resources.knowledge.path,
        '${data.parent.path}/${AppRuntime.knowledgeName}');
  });

  test('explicit operator resource overrides still work', () async {
    final resources = await AppRuntime.resources(data,
        environment: {
          'JD_CODEX_WORKSPACE': '${root.path}/custom-workspace',
          'JD_KNOWLEDGE_DIR': '${root.path}/custom-knowledge',
        },
        executablePath: executable,
        requireBundle: true);
    expect(resources.workspace.path, '${root.path}/custom-workspace');
    expect(resources.knowledge.path, '${root.path}/custom-knowledge');
  });

  test('official installer is found with a Finder-style PATH', () async {
    final codex = File('${root.path}/.local/bin/codex');
    await codex.create(recursive: true);
    expect(
        await AppRuntime.findCodex(environment: {
          'HOME': root.path,
          'PATH': '/usr/bin:/bin',
        }),
        codex.path);
  });

  test('an invalid explicit Codex override is not silently replaced', () async {
    await File('${root.path}/.local/bin/codex').create(recursive: true);
    expect(
        await AppRuntime.findCodex(environment: {
          'HOME': root.path,
          'CODEX_EXECUTABLE': '${root.path}/missing',
        }),
        isNull);
  });

  test('custom installer directory works without changing PATH', () async {
    final codex = File('${root.path}/custom/bin/codex');
    await codex.create(recursive: true);
    expect(
        await AppRuntime.findCodex(environment: {
          'HOME': root.path,
          'CODEX_INSTALL_DIR': codex.parent.path,
        }),
        codex.path);
  });

  test('npm Node interpreter directory is available to Codex from Finder', () {
    final environment = AppRuntime.processEnvironment(
        '${root.path}/.nvm/versions/node/v22/bin/codex',
        environment: {'HOME': root.path, 'PATH': '/usr/bin:/bin:.:relative'});
    expect(environment['PATH']!.split(':'),
        contains('${root.path}/.nvm/versions/node/v22/bin'));
    expect(environment['PATH']!.split(':'), isNot(contains('.')));
    expect(environment['PATH']!.split(':'), contains('/opt/homebrew/bin'));
  });

  test('video tools are found inside the moved app', () async {
    final ffmpeg = File('${bundle.path}/bin/ffmpeg');
    await ffmpeg.create(recursive: true);
    expect(await AppRuntime.bundledTool('ffmpeg', executablePath: executable),
        ffmpeg.path);
    expect(await AppRuntime.bundledTool('ffprobe', executablePath: executable),
        isNull);
  });

  test('bundled initial data is imported once without overwriting state',
      () async {
    final initial = Directory('${bundle.path}/initial_data');
    await initial.create(recursive: true);
    await File('${initial.path}/customer.json').writeAsString('snapshot');
    await File('${initial.path}/media/photo.png')
        .create(recursive: true)
        .then((file) => file.writeAsBytes([1, 2, 3]));

    expect(
        await AppRuntime.installBundledInitialData(data,
            executablePath: executable),
        isTrue);
    expect(await File('${data.path}/customer.json').readAsString(), 'snapshot');
    await File('${data.path}/customer.json').writeAsString('live state');

    expect(
        await AppRuntime.installBundledInitialData(data,
            executablePath: executable),
        isFalse);
    expect(
        await File('${data.path}/customer.json').readAsString(), 'live state');
  });
}
