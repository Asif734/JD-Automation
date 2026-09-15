import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/capture_models.dart';

class ConversationFileStore {
  ConversationFileStore(this.rootDirectory);

  final Directory rootDirectory;
  final Map<String, Future<void>> _writeTails = {};

  Directory get conversationsDirectory => rootDirectory;
  Directory get mediaDirectory =>
      Directory(p.join(rootDirectory.path, 'media'));

  Future<CaptureAppendResult> appendCapture(CapturedConversation capture) {
    final userId = capture.customerExternalId ?? capture.customerName;
    return _serialized(userId, () async {
      final document = await _readOrCreate(
        userId: userId,
        displayName: capture.customerName,
        stableKey: capture.stableKey,
      );
      final messages =
          (document['messages'] as List<Object?>).cast<Map<String, Object?>>();
      final knownIds =
          messages.map((item) => item['id']).whereType<String>().toSet();
      final knownIncomingVariants = <String, Set<String>>{};
      for (final item in messages.where((item) =>
          item['direction'] == 'incoming' &&
          (item['source'] == 'jd_automation' ||
              item['source'] == 'qianniu_capture'))) {
        final raw = item['body']?.toString() ?? '';
        final canonical = _ocrCanonical(raw);
        if (canonical.isNotEmpty) {
          knownIncomingVariants.putIfAbsent(canonical, () => {}).add(raw);
        }
      }
      var inserted = 0;
      final insertedIncomingIds = <String>[];
      final insertedOutgoingIds = <String>[];
      String? lastInsertedDirection;
      for (var index = 0; index < capture.messages.length; index++) {
        final message = capture.messages[index];
        if (!knownIds.add(message.stableId)) continue;
        if (message.direction == 'incoming') {
          final canonical = _ocrCanonical(message.body);
          final sameBubbleIndex = messages.lastIndexWhere((item) =>
              item['direction'] == 'incoming' &&
              (item['source'] == 'jd_automation' ||
                  item['source'] == 'qianniu_capture') &&
              _sameIncomingBubbleTime(item['sent_at'], message.sentAt) &&
              _sameBubbleContent(item['body']?.toString() ?? '', message.body));
          if (sameBubbleIndex >= 0) {
            final existing = messages[sameBubbleIndex];
            final existingBody = existing['body']?.toString() ?? '';
            if (_ocrCanonical(message.body).length >
                _ocrCanonical(existingBody).length) {
              final oldId = existing['id']?.toString();
              if (oldId != null) knownIds.remove(oldId);
              existing
                ..['id'] = message.stableId
                ..['body'] = message.body
                ..['sender'] = message.sender
                ..['sent_at'] = message.sentAt?.toUtc().toIso8601String()
                ..['captured_at'] =
                    capture.capturedAt.toUtc().toIso8601String();
              knownIds.add(message.stableId);
              inserted++;
              lastInsertedDirection = 'incoming';
            }
            continue;
          }
          final upgradeIndex = messages.lastIndexWhere((item) {
            if (item['direction'] != 'incoming' ||
                (item['source'] != 'jd_automation' &&
                    item['source'] != 'qianniu_capture')) {
              return false;
            }
            final capturedAt =
                DateTime.tryParse(item['captured_at']?.toString() ?? '');
            if (capturedAt == null ||
                capture.capturedAt.difference(capturedAt).abs() >
                    const Duration(minutes: 2)) {
              return false;
            }
            if (!_sameIncomingBubbleTimestampOrUnknown(
                item['sent_at'], message.sentAt)) {
              return false;
            }
            return _isMoreCompleteVariant(
                item['body']?.toString() ?? '', message.body);
          });
          if (upgradeIndex >= 0) {
            final existing = messages[upgradeIndex];
            final existingCanonical =
                _ocrCanonical(existing['body']?.toString() ?? '');
            if (canonical.length > existingCanonical.length) {
              final oldId = existing['id']?.toString();
              if (oldId != null) knownIds.remove(oldId);
              existing
                ..['id'] = message.stableId
                ..['body'] = message.body
                ..['sender'] = message.sender
                ..['captured_at'] =
                    capture.capturedAt.toUtc().toIso8601String();
              knownIds.add(message.stableId);
              inserted++;
              lastInsertedDirection = 'incoming';
              final alreadyAnswered = messages
                  .skip(upgradeIndex + 1)
                  .any((item) => item['direction'] == 'outgoing');
              if (!alreadyAnswered) {
                insertedIncomingIds.add(message.stableId);
              }
            }
            continue;
          }
          final variants = knownIncomingVariants[canonical];
          // A different OCR spelling of the same canonical text is an old
          // visible bubble being re-read. An exact repeated customer message
          // is still allowed when its timestamp-derived stable ID is new.
          if (variants != null && !variants.contains(message.body)) continue;
          final recentDuplicate = messages.reversed.take(12).any((item) {
            if (item['direction'] != 'incoming' ||
                (item['source'] != 'jd_automation' &&
                    item['source'] != 'qianniu_capture')) {
              return false;
            }
            final capturedAt =
                DateTime.tryParse(item['captured_at']?.toString() ?? '');
            if (capturedAt == null ||
                capture.capturedAt.difference(capturedAt).abs() >
                    const Duration(minutes: 2)) {
              return false;
            }
            if (!_sameIncomingBubbleTimestampOrUnknown(
                item['sent_at'], message.sentAt)) {
              return false;
            }
            return _sameOcrWordBag(
                item['body']?.toString() ?? '', message.body);
          });
          if (recentDuplicate) continue;
          knownIncomingVariants
              .putIfAbsent(canonical, () => {})
              .add(message.body);
        }
        if (message.direction == 'outgoing') {
          final matchingDraft = messages.reversed
              .where((item) =>
                  item['direction'] == 'outgoing' &&
                  item['source'] == 'generated_reply' &&
                  (_sameReply(item['body']?.toString() ?? '', message.body) ||
                      _sameBubbleTime(item['sent_at'], message.sentAt)))
              .firstOrNull;
          if (matchingDraft != null) {
            if (matchingDraft['delivery_status'] != 'sent') {
              matchingDraft['delivery_status'] = 'sent';
              matchingDraft['sent_at'] =
                  capture.capturedAt.toUtc().toIso8601String();
              inserted++;
            }
            continue;
          }
        }
        messages.add({
          'id': message.stableId,
          'direction': message.direction,
          'body': message.body,
          'sender': message.sender,
          'sent_at': message.sentAt?.toUtc().toIso8601String(),
          'captured_at': capture.capturedAt.toUtc().toIso8601String(),
          'source': 'jd_automation',
          'media': [for (final media in message.media) media.toJson()],
        });
        inserted++;
        lastInsertedDirection = message.direction;
        if (message.direction == 'incoming') {
          insertedIncomingIds.add(message.stableId);
        } else if (message.direction == 'outgoing') {
          insertedOutgoingIds.add(message.stableId);
        }
      }
      if (inserted > 0) await _write(document, userId);
      return CaptureAppendResult(
        changed: inserted,
        insertedIncomingIds: insertedIncomingIds,
        insertedOutgoingIds: insertedOutgoingIds,
        lastInsertedDirection: lastInsertedDirection,
      );
    });
  }

  /// Adds factual visual descriptions to already captured media without
  /// writing an unsent customer reply into conversation history.
  Future<int> updateMediaDescriptions(
          String userId, Map<String, String> descriptions) =>
      _serialized(userId, () async {
        if (descriptions.isEmpty) return 0;
        final document = await read(userId);
        if (document == null) return 0;
        var changed = 0;
        final messages = document['messages'] as List<Object?>? ?? const [];
        for (final message in messages.whereType<Map<String, dynamic>>()) {
          final mediaItems = message['media'] as List<Object?>? ?? const [];
          for (final media in mediaItems.whereType<Map<String, dynamic>>()) {
            final path = media['path']?.toString();
            final description = path == null ? null : descriptions[path];
            if (description == null || media['description'] == description) {
              continue;
            }
            media['description'] = description;
            changed++;
          }
        }
        if (changed > 0) await _write(document, userId);
        return changed;
      });

  Future<bool> hasSimilarImageFingerprint(String userId, String fingerprint,
      {int maximumDistance = 8, Set<String>? captureSources}) async {
    if (fingerprint.isEmpty) return false;
    final target = BigInt.tryParse(fingerprint, radix: 16);
    if (target == null) return false;
    final document = await read(userId);
    final messages = document?['messages'] as List<Object?>? ?? const [];
    for (final message in messages.whereType<Map<String, dynamic>>()) {
      final mediaItems = message['media'] as List<Object?>? ?? const [];
      for (final media in mediaItems.whereType<Map<String, dynamic>>()) {
        if (captureSources != null &&
            !captureSources.contains(media['capture_source']?.toString())) {
          continue;
        }
        final known = BigInt.tryParse(
            media['visual_fingerprint']?.toString() ?? '',
            radix: 16);
        if (known == null) continue;
        var difference = target ^ known;
        var distance = 0;
        while (difference > BigInt.zero && distance <= maximumDistance) {
          difference &= difference - BigInt.one;
          distance++;
        }
        if (distance <= maximumDistance) return true;
      }
    }
    return false;
  }

  /// Appends a generated reply only after Qianniu confirms the send action.
  /// Unsent drafts intentionally never become conversation history.
  Future<void> appendSentReply({
    required String userId,
    required String displayName,
    required String stableKey,
    required AiDraft draft,
  }) =>
      _serialized(userId, () async {
        final document = await _readOrCreate(
          userId: userId,
          displayName: displayName,
          stableKey: stableKey,
        );
        final now = DateTime.now().toUtc();
        final replyId =
            'assistant:${sha256.convert(utf8.encode('$userId\u001f${now.toIso8601String()}\u001f${draft.reply}'))}';
        (document['messages'] as List<Object?>).add({
          'id': replyId,
          'direction': 'outgoing',
          'body': draft.reply,
          'sender': draft.model,
          'sent_at': now.toIso8601String(),
          'captured_at': now.toIso8601String(),
          'source': 'generated_reply',
          'delivery_status': 'sent',
          'media': [
            for (final attachment in draft.attachments)
              {
                'type': attachment.kind,
                'path': attachment.url.toString(),
                'media_id': attachment.mediaId,
                'caption': attachment.caption,
              }
          ],
          'reply_metadata': {
            'decision': draft.decision,
            'confidence': draft.confidence,
            'risk_level': draft.riskLevel,
            'model': draft.model,
            'used_record_ids': draft.usedRecordIds,
            'actions': draft.actions,
            'raw_response': jsonDecode(draft.rawJson),
          },
        });
        await _write(document, userId);
      });

  /// Removes legacy unsent generated replies written by older builds.
  /// Incoming messages, OCR-observed seller messages, and confirmed generated
  /// sends are preserved.
  Future<int> purgeLegacyUnsentDrafts() =>
      _serialized('*maintenance*', () async {
        if (!await conversationsDirectory.exists()) return 0;
        var removed = 0;
        await for (final entity in conversationsDirectory.list()) {
          if (entity is! File || p.extension(entity.path) != '.json') continue;
          Map<String, Object?> document;
          try {
            document = (jsonDecode(await entity.readAsString())
                    as Map<String, dynamic>)
                .cast<String, Object?>();
          } catch (_) {
            continue;
          }
          final userId = document['user_id']?.toString();
          if (userId != null && userId.isNotEmpty) {
            final customerNamedFile = _conversationFile(userId);
            if (p.absolute(entity.path) != p.absolute(customerNamedFile.path) &&
                !await customerNamedFile.exists()) {
              try {
                await entity.rename(customerNamedFile.path);
              } on FileSystemException {
                // Keep the original file intact if a rename is unavailable.
              }
            }
          }
          final rawMessages = document['messages'];
          if (rawMessages is! List<Object?>) continue;
          final retained = rawMessages.where((item) {
            if (item is! Map<String, dynamic>) return true;
            final unsentDraft = item['source'] == 'generated_reply' &&
                item['delivery_status'] != 'sent';
            if (unsentDraft) removed++;
            return !unsentDraft;
          }).toList(growable: true);
          if (retained.length == rawMessages.length) continue;
          document['messages'] = retained;
          if (userId != null && userId.isNotEmpty) {
            await _write(document, userId);
          }
        }
        return removed;
      });

  Future<bool> markReplySent({
    required String userId,
    required String reply,
  }) =>
      _serialized(userId, () async {
        final document = await read(userId);
        if (document == null) return false;
        final messages = (document['messages'] as List<Object?>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
        for (final message in messages.reversed) {
          if (message['source'] == 'generated_reply' &&
              message['body'] == reply &&
              message['delivery_status'] != 'sent') {
            final now = DateTime.now().toUtc().toIso8601String();
            message['delivery_status'] = 'sent';
            message['sent_at'] = now;
            await _write(document, userId);
            return true;
          }
        }
        return false;
      });

  Future<List<StoredMessage>> lastMessages(String userId,
      {int limit = 20}) async {
    final document = await read(userId);
    if (document == null) return const [];
    final messages = (document['messages'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    final selected = messages.length <= limit
        ? messages
        : messages.sublist(messages.length - limit);
    return selected.map((message) {
      final capturedAt =
          DateTime.tryParse(message['captured_at'] as String? ?? '');
      return StoredMessage(
        stableId: message['id'] as String? ?? '',
        direction: message['direction'] as String? ?? 'unknown',
        body: message['body'] as String? ?? '',
        capturedAt:
            capturedAt?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    }).toList(growable: false);
  }

  Future<Map<String, Object?>?> read(String userId) async {
    var file = _conversationFile(userId);
    if (!await file.exists()) {
      final legacy = _legacyConversationFile(userId);
      if (!await legacy.exists()) return null;
      await conversationsDirectory.create(recursive: true);
      try {
        file = await legacy.rename(file.path);
      } on FileSystemException {
        // A concurrent reader may already have migrated it. Otherwise retain
        // read access to the old hashed file without risking data loss.
        if (!await file.exists()) file = legacy;
      }
    }
    return (jsonDecode(await file.readAsString()) as Map<String, dynamic>)
        .cast<String, Object?>();
  }

  Future<String> saveMedia({
    required String userId,
    required String filename,
    required List<int> bytes,
  }) =>
      _serialized(userId, () async {
        final directory =
            Directory(p.join(mediaDirectory.path, safeUserId(userId)));
        await directory.create(recursive: true);
        final extension = p.extension(filename).toLowerCase();
        final safeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
            ? extension
            : '.bin';
        final digest = sha256.convert(bytes).toString().substring(0, 16);
        final path = p.join(directory.path, '$digest$safeExtension');
        final file = File(path);
        if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
        return path;
      });

  String safeUserId(String userId) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      return 'user_${sha256.convert(utf8.encode(userId))}';
    }
    var safe = trimmed.replaceAll(RegExp(r'[/\\:\x00-\x1f\x7f]'), '_');
    final changed = safe != trimmed;
    if (utf8.encode(safe).length > 180) {
      safe = String.fromCharCodes(safe.runes.take(48));
    }
    if (changed || safe != trimmed) {
      final suffix =
          sha256.convert(utf8.encode(trimmed)).toString().substring(0, 10);
      safe = '${safe}_$suffix';
    }
    return safe;
  }

  String _legacySafeUserId(String userId) {
    final trimmed = userId.trim();
    if (RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(trimmed)) return trimmed;
    return 'user_${sha256.convert(utf8.encode(trimmed))}';
  }

  String _ocrCanonical(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'''[.,!?;:'"`~，。！？；：“”‘’（）()\[\]{}、]'''), '');

  bool _sameOcrWordBag(String left, String right) {
    List<String> tokens(String value) => RegExp(r'[a-z0-9]+|[\u3400-\u9fff]')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!)
        .toList()
      ..sort();

    final leftTokens = tokens(left);
    final rightTokens = tokens(right);
    if (leftTokens.length < 3 || leftTokens.length != rightTokens.length) {
      return false;
    }
    for (var index = 0; index < leftTokens.length; index++) {
      if (leftTokens[index] != rightTokens[index]) return false;
    }
    return true;
  }

  bool _isMoreCompleteVariant(String existing, String observed) {
    final left = _ocrCanonical(existing);
    final right = _ocrCanonical(observed);
    if (left.isEmpty || right.isEmpty || left == right) return false;
    final shorter = left.length < right.length ? left : right;
    final longer = left.length < right.length ? right : left;
    if (shorter.length >= 8 && longer.contains(shorter)) return true;

    Set<String> words(String value) => RegExp(r'[a-z0-9]+|[\u3400-\u9fff]')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!)
        .toSet();
    final leftWords = words(existing);
    final rightWords = words(observed);
    final smaller =
        leftWords.length < rightWords.length ? leftWords : rightWords;
    final larger =
        leftWords.length < rightWords.length ? rightWords : leftWords;
    return smaller.length >= 3 &&
        larger.length > smaller.length &&
        larger.containsAll(smaller);
  }

  bool _sameReply(String generated, String observed) {
    final left = _ocrCanonical(generated);
    final right = _ocrCanonical(observed);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    final shorter = left.length < right.length ? left : right;
    final longer = left.length < right.length ? right : left;
    if (shorter.length >= 15 && longer.contains(shorter)) return true;

    Set<String> words(String value) => RegExp(r'[a-z0-9]+|[\u3400-\u9fff]')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!)
        .toSet();
    final generatedWords = words(generated);
    final observedWords = words(observed);
    final smallerWords = generatedWords.length < observedWords.length
        ? generatedWords
        : observedWords;
    if (smallerWords.length < 6) return false;
    final overlap = generatedWords.intersection(observedWords).length;
    return overlap >= 6 && overlap / smallerWords.length >= 0.75;
  }

  bool _sameBubbleTime(Object? storedValue, DateTime? observed) {
    if (observed == null) return false;
    final stored = DateTime.tryParse(storedValue?.toString() ?? '');
    if (stored == null) return false;
    return stored.toUtc().difference(observed.toUtc()).abs() <=
        const Duration(seconds: 3);
  }

  /// A close timestamp alone does not identify a chat bubble: customers often
  /// send several separate messages within three seconds. Only coalesce close
  /// observations when OCR is re-reading the same text or a partial/expanded
  /// version of that text.
  bool _sameBubbleContent(String stored, String observed) {
    final left = _ocrCanonical(stored);
    final right = _ocrCanonical(observed);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    final shorter = left.length < right.length ? left : right;
    final longer = left.length < right.length ? right : left;
    if (shorter.length >= 3 && longer.contains(shorter)) return true;

    Set<String> tokens(String value) => RegExp(r'[a-z0-9]+|[\u3400-\u9fff]')
        .allMatches(value.toLowerCase())
        .map((match) => match.group(0)!)
        .toSet();
    final leftTokens = tokens(stored);
    final rightTokens = tokens(observed);
    final smallerTokens =
        leftTokens.length < rightTokens.length ? leftTokens : rightTokens;
    if (smallerTokens.length < 2) return false;
    final overlap = leftTokens.intersection(rightTokens).length;
    return overlap >= 2 && overlap / smallerTokens.length >= 0.66;
  }

  bool _sameIncomingBubbleTime(Object? storedValue, DateTime? observed) {
    if (observed == null) return false;
    final stored = DateTime.tryParse(storedValue?.toString() ?? '');
    if (stored == null) return false;
    // JD timestamps identify the bubble to the second. Nearby timestamps are
    // commonly separate rapid messages and must remain separate.
    return stored.toUtc().millisecondsSinceEpoch ==
        observed.toUtc().millisecondsSinceEpoch;
  }

  bool _sameIncomingBubbleTimestampOrUnknown(
      Object? storedValue, DateTime? observed) {
    if (observed == null) {
      return DateTime.tryParse(storedValue?.toString() ?? '') == null;
    }
    return _sameIncomingBubbleTime(storedValue, observed);
  }

  Future<Map<String, Object?>> _readOrCreate({
    required String userId,
    required String displayName,
    required String stableKey,
  }) async {
    final existing = await read(userId);
    if (existing != null) {
      existing['display_name'] = displayName;
      existing['stable_key'] = stableKey;
      return existing;
    }
    return {
      'schema_version': 1,
      'user_id': userId,
      'display_name': displayName,
      'stable_key': stableKey,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'messages': <Object?>[],
    };
  }

  Future<void> _write(Map<String, Object?> document, String userId) async {
    await conversationsDirectory.create(recursive: true);
    document['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final destination = _conversationFile(userId);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document),
      flush: true,
    );
    await temporary.rename(destination.path);
  }

  File _conversationFile(String userId) =>
      File(p.join(conversationsDirectory.path, '${safeUserId(userId)}.json'));

  File _legacyConversationFile(String userId) => File(
      p.join(conversationsDirectory.path, '${_legacySafeUserId(userId)}.json'));

  Future<T> _serialized<T>(String userId, Future<T> Function() action) {
    final completer = Completer<T>();
    final previous = _writeTails[userId] ?? Future<void>.value();
    _writeTails[userId] = previous.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }
}

class CaptureAppendResult {
  const CaptureAppendResult({
    required this.changed,
    required this.insertedIncomingIds,
    required this.insertedOutgoingIds,
    required this.lastInsertedDirection,
  });

  final int changed;
  final List<String> insertedIncomingIds;
  final List<String> insertedOutgoingIds;
  final String? lastInsertedDirection;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
