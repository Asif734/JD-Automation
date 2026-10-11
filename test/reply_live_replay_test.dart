import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/codex/codex_reply_service.dart';
import 'package:jd_automation/codex/customer_codex_session.dart';
import 'package:jd_automation/domain/capture_models.dart';
import 'package:jd_automation/storage/capture_database.dart';

/// Opt-in generation-only replay. Never opens JD or sends a customer message.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (name, question, expectedRecord) in [
    ('live TD630 four-copy replay', '打4联可以的吧', 'dot_matrix_copy_capacity'),
    (
      'live confirmed AK890 packaging replay',
      '有送纸吗',
      'ak80_confirmed_ak890_package_correction_20261010'
    ),
  ]) {
    test(name, () async {
      final root = await Directory.systemTemp.createTemp('jd_live_replay_');
      final database =
          CaptureDatabase(storageRoot: Directory('${root.path}/data'));
      addTearDown(() async {
        await database.close();
        await root.delete(recursive: true);
      });
      final project = Directory.current.path;
      final document =
          jsonDecode(await File('$project/data/格志打印机贝贝.json').readAsString())
              as Map<String, dynamic>;
      final messages =
          (document['messages'] as List).cast<Map<String, dynamic>>();
      final end = messages.lastIndexWhere((message) =>
          message['direction'] == 'incoming' &&
          (message['body'] as String).startsWith(question));
      expect(end, greaterThanOrEqualTo(0));
      final target = messages[end];
      await database.saveCapture(CapturedConversation(
        stableKey: 'customer:replay',
        customerName: '格志打印机贝贝',
        customerExternalId: '格志打印机贝贝',
        capturedAt: DateTime.now(),
        messages: [
          CapturedMessage(
              stableId: target['id'] as String,
              direction: 'incoming',
              body: target['body'] as String,
              axPath: 'replay')
        ],
      ));
      await File('${root.path}/data/格志打印机贝贝.json').writeAsString(jsonEncode({
        ...document,
        'messages': messages.take(end + 1).toList(),
      }));
      final executable =
          (await Process.run('which', ['codex'])).stdout.toString().trim();
      expect(executable, isNotEmpty);
      final sessions =
          CustomerCodexSessionStore(Directory('${root.path}/sessions'));
      final service = CodexReplyService(
        executable: executable,
        workspace: Directory('$project/codex_workspace'),
        knowledgeDirectory: Directory('$project/格志京东客服知识库-2026-10-04'),
        outputSchema: File('$project/codex_workspace/reply.schema.json'),
        sessionStore: sessions,
        timeout: const Duration(seconds: 120),
      );
      final watch = Stopwatch()..start();
      final draft = await service.generate(
        conversation: (await database.conversations()).single,
        database: database,
        batchEndMessageId: target['id'] as String,
      );
      watch.stop();
      final session = await sessions.read('格志打印机贝贝');
      // ignore: avoid_print
      print(jsonEncode({
        'generation_ms': watch.elapsedMilliseconds,
        'model': draft.model,
        'reply': draft.reply,
        'used_record_ids': draft.usedRecordIds,
        'thread_id': session?.threadId
      }));
      expect(draft.usedRecordIds, contains(expectedRecord));
      if (question == '有送纸吗') {
        expect(draft.reply, contains('AK890'));
        expect(draft.reply, contains('TG890'));
        expect(draft.reply, matches(RegExp(r'2\s*张|两张')));
        expect(draft.reply, isNot(matches(RegExp(r'AK80.*(?:未确认|没有.*资料)'))));
      } else {
        expect(draft.reply, matches(RegExp(r'可以|支持')));
      }
      expect(draft.reply, isNot(matches(RegExp(r'没有注明|无法确认|不能保证'))));
      // Generating a replay never adds a sent reply to the temporary history.
      final after = await (await database.history).read('格志打印机贝贝');
      expect((after!['messages'] as List).length, end + 1);
    },
        skip: Platform.environment['JD_REPLY_LIVE_REPLAY'] != '1',
        timeout: const Timeout(Duration(minutes: 3)));
  }
}
