import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A saved Codex thread is usable only while its input history is still an
/// unchanged prefix of the delivered conversation. The last generated reply
/// must also have appeared in that conversation before another turn resumes.
class CustomerCodexSession {
  const CustomerCodexSession({
    required this.threadId,
    required this.model,
    required this.historyCount,
    required this.historyFingerprint,
    required this.lastReply,
    required this.updatedAt,
  });

  final String threadId;
  final String model;
  final int historyCount;
  final String historyFingerprint;
  final String lastReply;
  final DateTime updatedAt;

  bool canResume(List<Map<String, dynamic>> messages, String currentModel) {
    if (threadId.isEmpty ||
        model != currentModel ||
        historyCount > messages.length ||
        DateTime.now().difference(updatedAt) > const Duration(days: 1)) {
      return false;
    }
    if (fingerprint(messages.take(historyCount)) != historyFingerprint) {
      return false;
    }
    return messages.skip(historyCount).any((message) =>
        message['direction'] == 'outgoing' &&
        message['body']?.toString().trim() == lastReply.trim());
  }

  static String fingerprint(Iterable<Map<String, dynamic>> messages) {
    final stable = messages
        .map((message) => {
              'id': message['id'],
              'direction': message['direction'],
              'body': message['body'],
              'media_paths': [
                for (final media
                    in (message['media'] as List<Object?>? ?? const []))
                  if (media is Map<String, dynamic>) media['path'],
              ],
            })
        .toList(growable: false);
    return sha256.convert(utf8.encode(jsonEncode(stable))).toString();
  }

  Map<String, Object?> toJson() => {
        'thread_id': threadId,
        'model': model,
        'history_count': historyCount,
        'history_fingerprint': historyFingerprint,
        'last_reply': lastReply,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  static CustomerCodexSession? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final updatedAt = DateTime.tryParse(value['updated_at']?.toString() ?? '');
    final count = value['history_count'];
    if (updatedAt == null || count is! int || count < 0) return null;
    return CustomerCodexSession(
      threadId: value['thread_id']?.toString() ?? '',
      model: value['model']?.toString() ?? '',
      historyCount: count,
      historyFingerprint: value['history_fingerprint']?.toString() ?? '',
      lastReply: value['last_reply']?.toString() ?? '',
      updatedAt: updatedAt,
    );
  }
}

class CustomerCodexSessionStore {
  CustomerCodexSessionStore(this.directory);

  final Directory directory;

  File _file(String userId) => File(
      p.join(directory.path, '${sha256.convert(utf8.encode(userId))}.json'));

  Future<CustomerCodexSession?> read(String userId) async {
    final file = _file(userId);
    if (!await file.exists()) return null;
    try {
      return CustomerCodexSession.fromJson(
          jsonDecode(await file.readAsString()));
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(String userId, CustomerCodexSession session) async {
    await directory.create(recursive: true);
    final file = _file(userId);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(session.toJson()));
    await temporary.rename(file.path);
  }

  Future<void> invalidate(String userId) async {
    final file = _file(userId);
    if (await file.exists()) await file.delete();
  }
}
