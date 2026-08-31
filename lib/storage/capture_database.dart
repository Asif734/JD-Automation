import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/capture_models.dart';
import 'conversation_file_store.dart';

/// SQLite contains only customers waiting for processing. Durable messages and
/// sent replies live in per-user JSON documents managed by [history]. Unsent
/// generated drafts are transient SQLite state, never conversation history.
class CaptureDatabase {
  CaptureDatabase({Directory? storageRoot}) : _storageRoot = storageRoot;

  final Directory? _storageRoot;
  Database? _database;
  ConversationFileStore? _history;
  bool _legacyDraftsPurged = false;
  bool _reviewControlsSynced = false;

  Future<Directory> get storageRoot async =>
      _storageRoot ?? await _resolveDefaultStorageRoot();

  Future<ConversationFileStore> get history async {
    if (_history case final value?) return value;
    final value = ConversationFileStore(await storageRoot);
    _history = value;
    return value;
  }

  Future<Database> get database async {
    if (_database case final database?) return database;
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      p.join((await storageRoot).path, 'jd_automation.sqlite3'),
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
    _database = database;
    if (!_legacyDraftsPurged) {
      await (await history).purgeLegacyUnsentDrafts();
      _legacyDraftsPurged = true;
    }
    if (!_reviewControlsSynced) {
      final open = await database.query('human_review_tickets',
          columns: ['user_id'], where: "status = 'open'");
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in open) {
        final userId = row['user_id']! as String;
        final current = await database.query('conversation_control',
            columns: ['state'],
            where: 'user_id = ?',
            whereArgs: [userId],
            limit: 1);
        if (current.isNotEmpty &&
            current.first['state'] == 'human_contacting') {
          continue;
        }
        await database.rawInsert('''INSERT INTO conversation_control(
          user_id,state,resume_after_message_id,updated_at_ms)
          VALUES(?,'human_review_open',NULL,?) ON CONFLICT(user_id) DO UPDATE SET
          state='human_review_open',resume_after_message_id=NULL,
          updated_at_ms=excluded.updated_at_ms''', [userId, now]);
        await database.delete('pending_customers',
            where: 'user_id = ?', whereArgs: [userId]);
      }
      _reviewControlsSynced = true;
    }
    return database;
  }

  Future<void> _create(Database db, int version) async {
    await _createPendingQueue(db);
    await _createHumanReview(db);
    await _createGeneratedDrafts(db);
    await _createTransferWelcomes(db);
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      // Preserve legacy tables but stop writing to them.
      await _createPendingQueue(db);
    }
    if (oldVersion < 4) await _createHumanReview(db);
    if (oldVersion < 5) await _createGeneratedDrafts(db);
    if (oldVersion < 6) await _createTransferWelcomes(db);
  }

  Future<void> _createTransferWelcomes(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS transfer_welcomes (
      user_id TEXT NOT NULL,
      event_key TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      PRIMARY KEY(user_id, event_key)
    )''');
  }

  Future<bool> hasTransferWelcome(
      {required String userId, required String eventKey}) async {
    final db = await database;
    final rows = await db.query('transfer_welcomes',
        columns: ['user_id'],
        where: 'user_id = ? AND event_key = ?',
        whereArgs: [userId, eventKey],
        limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> recordTransferWelcome(
      {required String userId, required String eventKey}) async {
    final db = await database;
    await db.insert(
        'transfer_welcomes',
        {
          'user_id': userId,
          'event_key': eventKey,
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> appendAutomatedNoticeSent(
      {required String userId, required String reply}) async {
    final raw = <String, Object?>{
      'reply': reply,
      'decision': 'draft',
      'confidence': 1.0,
      'used_record_ids': <String>[],
      'required_slots': <String>[],
      'actions': <Object?>[],
      'risk_level': 'low',
      'risk_triggers': <String>[],
      'auto_send_allowed': false,
      'model': 'jd-transfer-welcome-v1',
      'attachments': <Object?>[],
      'image_descriptions': <Object?>[],
      'human_review_required': false,
      'reason': null,
    };
    await (await history).appendSentReply(
      userId: userId,
      displayName: userId,
      stableKey: userId,
      draft: AiDraft.fromJson(raw, mediaBaseUrl: Uri()),
    );
  }

  Future<void> _createGeneratedDrafts(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS generated_drafts (
      user_id TEXT PRIMARY KEY,
      pending_id INTEGER NOT NULL,
      reply TEXT NOT NULL,
      model TEXT NOT NULL,
      raw_json TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL
    )''');
  }

  Future<void> _createHumanReview(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS human_review_tickets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      customer_request TEXT NOT NULL,
      reason TEXT NOT NULL,
      status TEXT NOT NULL,
      assigned_to TEXT,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS human_review_queue
      ON human_review_tickets(status, updated_at_ms DESC)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS conversation_control (
      user_id TEXT PRIMARY KEY,
      state TEXT NOT NULL,
      resume_after_message_id TEXT,
      updated_at_ms INTEGER NOT NULL
    )''');
  }

  Future<void> _createPendingQueue(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS pending_customers (
      id INTEGER PRIMARY KEY,
      user_id TEXT NOT NULL UNIQUE,
      display_name TEXT NOT NULL,
      stable_key TEXT NOT NULL,
      newest_message_id TEXT NOT NULL,
      enqueued_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL
    )''');
    await db.execute('''CREATE INDEX IF NOT EXISTS pending_customers_oldest
      ON pending_customers(enqueued_at_ms ASC, id ASC)''');
  }

  Future<int> saveCapture(CapturedConversation capture,
      {bool isCurrentViewport = true}) async {
    final store = await history;
    final result = await store.appendCapture(capture);
    final userId = capture.customerExternalId ?? capture.customerName;
    if (result.changed == 0) return 0;
    final db = await database;
    if (isCurrentViewport &&
        capture.messages.isNotEmpty &&
        capture.messages.last.direction == 'outgoing') {
      await db.delete('pending_customers',
          where: 'user_id = ?', whereArgs: [userId]);
      await db.delete('generated_drafts',
          where: 'user_id = ?', whereArgs: [userId]);
      return result.changed;
    }
    if (result.insertedIncomingIds.isEmpty) return result.changed;
    // A new customer turn invalidates any older unsent suggestion.
    await db
        .delete('generated_drafts', where: 'user_id = ?', whereArgs: [userId]);
    final controls = await db.query('conversation_control',
        where: 'user_id = ?', whereArgs: [userId], limit: 1);
    if (controls.isNotEmpty) {
      final control = controls.first;
      if (control['state'] == 'human_review_open' ||
          control['state'] == 'human_contacting') {
        return result.changed;
      }
      if (control['state'] == 'waiting_for_customer') {
        final newestId = result.insertedIncomingIds.last;
        if (newestId == control['resume_after_message_id']) {
          return result.changed;
        }
        await db.update(
            'conversation_control',
            {
              'state': 'ai_active',
              'resume_after_message_id': null,
              'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'user_id = ?',
            whereArgs: [userId]);
      }
    }
    await _upsertPending(capture);
    return result.changed;
  }

  Future<void> _upsertPending(CapturedConversation capture) async {
    final userId = capture.customerExternalId ?? capture.customerName;
    final newest = capture.messages.lastWhere(
      (message) => message.direction == 'incoming',
    );
    final now = capture.capturedAt.millisecondsSinceEpoch;
    final db = await database;
    await db.rawInsert('''INSERT INTO pending_customers(
      user_id, display_name, stable_key, newest_message_id, enqueued_at_ms, updated_at_ms)
      VALUES(?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET
        display_name=excluded.display_name,
        stable_key=excluded.stable_key,
        newest_message_id=excluded.newest_message_id,
        updated_at_ms=excluded.updated_at_ms''', [
      userId,
      capture.customerName,
      capture.stableKey,
      newest.stableId,
      now,
      now,
    ]);
  }

  /// Requeues a durable incoming message only when no generated reply appears
  /// after it. This repairs capture-success/generation-failure without ever
  /// drafting twice for an already answered message.
  Future<bool> ensurePendingForUnanswered(String userId) async {
    final db = await database;
    final drafts = await db.query('generated_drafts',
        columns: ['user_id'],
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1);
    if (drafts.isNotEmpty) return false;
    final controls = await db.query('conversation_control',
        columns: ['state'],
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1);
    if (controls.isNotEmpty && controls.first['state'] != 'ai_active') {
      return false;
    }
    final document = await (await history).read(userId);
    if (document == null) return false;
    final messages = (document['messages'] as List<Object?>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final incomingIndex = messages
        .lastIndexWhere((message) => message['direction'] == 'incoming');
    if (incomingIndex < 0) return false;
    final answered = messages
        .skip(incomingIndex + 1)
        .any((message) => message['direction'] == 'outgoing');
    if (answered) return false;
    final incoming = messages[incomingIndex];
    final capturedAt =
        DateTime.tryParse(incoming['captured_at']?.toString() ?? '') ??
            DateTime.now().toUtc();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert('''INSERT INTO pending_customers(
      user_id, display_name, stable_key, newest_message_id, enqueued_at_ms, updated_at_ms)
      VALUES(?, ?, ?, ?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET
        display_name=excluded.display_name,
        stable_key=excluded.stable_key,
        newest_message_id=excluded.newest_message_id,
        updated_at_ms=excluded.updated_at_ms''', [
      userId,
      document['display_name']?.toString() ?? userId,
      document['stable_key']?.toString() ?? userId,
      incoming['id']?.toString() ?? '',
      capturedAt.millisecondsSinceEpoch,
      now,
    ]);
    return true;
  }

  Future<List<ConversationSummary>> conversations() async {
    final db = await database;
    final store = await history;
    final rows = await db.query('pending_customers',
        orderBy: 'enqueued_at_ms ASC, id ASC');
    return Future.wait(rows.map((row) async => ConversationSummary(
          id: row['id']! as int,
          userId: row['user_id']! as String,
          stableKey: row['stable_key']! as String,
          customerName: row['display_name']! as String,
          lastActivityAt:
              DateTime.fromMillisecondsSinceEpoch(row['updated_at_ms']! as int),
          messages: await store.lastMessages(row['user_id']! as String),
        )));
  }

  /// Returns true only when SQLite and durable JSON agree that the customer
  /// has a latest incoming message with no later outgoing reply or draft.
  /// Stale queue rows from earlier builds are removed automatically.
  Future<bool> hasPendingUnanswered(String userId) async {
    final db = await database;
    final rows = await db.query('pending_customers',
        columns: ['newest_message_id'],
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1);
    if (rows.isEmpty) return false;
    final document = await (await history).read(userId);
    final messages = (document?['messages'] as List<Object?>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final incomingIndex = messages
        .lastIndexWhere((message) => message['direction'] == 'incoming');
    final answered = incomingIndex < 0 ||
        messages
            .skip(incomingIndex + 1)
            .any((message) => message['direction'] == 'outgoing');
    final latestIncomingId =
        incomingIndex < 0 ? null : messages[incomingIndex]['id']?.toString();
    final queueMatchesLatest =
        rows.first['newest_message_id']?.toString() == latestIncomingId;
    if (answered || !queueMatchesLatest) {
      await db.delete('pending_customers',
          where: 'user_id = ?', whereArgs: [userId]);
      return false;
    }
    return true;
  }

  /// Saves an unsent Codex suggestion in transient SQLite, then removes the
  /// user from the generation queue. JSON is unchanged until an actual send.
  Future<int> saveDraft(int pendingId, AiDraft draft) async {
    final db = await database;
    final rows = await db.query('pending_customers',
        where: 'id = ?', whereArgs: [pendingId], limit: 1);
    if (rows.isEmpty) return 0;
    final row = rows.first;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      await txn.rawInsert('''INSERT INTO generated_drafts(
        user_id,pending_id,reply,model,raw_json,created_at_ms)
        VALUES(?,?,?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET
        pending_id=excluded.pending_id,reply=excluded.reply,
        model=excluded.model,raw_json=excluded.raw_json,
        created_at_ms=excluded.created_at_ms''', [
        row['user_id'],
        pendingId,
        draft.reply,
        draft.model,
        draft.rawJson,
        now,
      ]);
      return txn
          .delete('pending_customers', where: 'id = ?', whereArgs: [pendingId]);
    });
  }

  Future<StoredDraft?> latestDraft(int pendingId) async => null;

  Future<List<HumanReviewTicket>> humanReviewTickets() async {
    final db = await database;
    final rows = await db.query('human_review_tickets',
        where: "status IN ('open','contacting')",
        orderBy: 'updated_at_ms DESC, id DESC');
    return rows
        .map((row) => HumanReviewTicket(
              id: row['id']! as int,
              conversationId: row['user_id']! as String,
              customerRequest: row['customer_request']! as String,
              reason: row['reason']! as String,
              status: row['status']! as String,
              assignedTo: row['assigned_to'] as String?,
            ))
        .toList(growable: false);
  }

  Future<int> improveGenericTicketReasons() async {
    final db = await database;
    final rows = await db.query('human_review_tickets',
        columns: ['id', 'user_id', 'reason'],
        where: "status IN ('open','contacting')");
    var updated = 0;
    for (final row in rows) {
      final reason = row['reason']?.toString().trim() ?? '';
      if (reason.isNotEmpty && reason != 'Codex requested human review.') {
        continue;
      }
      final document = await (await history).read(row['user_id']! as String);
      final messages = (document?['messages'] as List<Object?>? ?? const [])
          .whereType<Map<String, dynamic>>();
      final generated = messages.toList().reversed.firstWhere(
          (item) => item['source'] == 'generated_reply',
          orElse: () => const {});
      final metadata = generated['reply_metadata'];
      if (metadata is! Map<String, dynamic>) continue;
      final raw = metadata['raw_response'];
      if (raw is! Map<String, dynamic>) continue;
      final improved = _reasonFromResponse(raw, metadata);
      updated += await db.update(
          'human_review_tickets',
          {
            'reason': improved,
            'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [row['id']]);
    }
    return updated;
  }

  String _reasonFromResponse(
      Map<String, dynamic> raw, Map<String, dynamic> metadata) {
    final explicit = raw['reason']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty && explicit != 'null') {
      return explicit;
    }
    final triggers = (raw['risk_triggers'] as List<Object?>? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final escalation = (raw['actions'] as List<Object?>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((item) {
          final type = item['type']?.toString().toLowerCase() ?? '';
          return type.contains('human') ||
              type.contains('escalat') ||
              type.contains('route');
        })
        .map((item) => item['description']?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty);
    final details = <String>{...triggers, ...escalation}.toList();
    final risk = metadata['risk_level']?.toString() ?? 'unknown';
    return details.isEmpty
        ? 'Human review required because this reply was classified as $risk risk.'
        : 'Human review required ($risk risk): ${details.join('. ')}';
  }

  Future<HumanReviewTicket> createHumanReviewTicket({
    required String userId,
    required String customerRequest,
    required String reason,
  }) async {
    final db = await database;
    final existing = await db.query('human_review_tickets',
        where: "user_id = ? AND status IN ('open','contacting')",
        whereArgs: [userId],
        orderBy: 'id DESC',
        limit: 1);
    if (existing.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.transaction((txn) async {
        await txn.insert('human_review_tickets', {
          'user_id': userId,
          'customer_request': customerRequest,
          'reason': reason,
          'status': 'open',
          'created_at_ms': now,
          'updated_at_ms': now,
        });
        await txn.rawInsert('''INSERT INTO conversation_control(
          user_id,state,resume_after_message_id,updated_at_ms)
          VALUES(?,'human_review_open',NULL,?) ON CONFLICT(user_id) DO UPDATE SET
          state='human_review_open',resume_after_message_id=NULL,
          updated_at_ms=excluded.updated_at_ms''', [userId, now]);
        await txn.delete('pending_customers',
            where: 'user_id = ?', whereArgs: [userId]);
      });
    }
    return (await humanReviewTickets())
        .firstWhere((ticket) => ticket.conversationId == userId);
  }

  Future<void> markTicketContacting(int ticketId) async {
    final db = await database;
    final rows = await db.query('human_review_tickets',
        where: 'id = ?', whereArgs: [ticketId], limit: 1);
    if (rows.isEmpty) return;
    final userId = rows.first['user_id']! as String;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update('human_review_tickets',
          {'status': 'contacting', 'updated_at_ms': now},
          where: 'id = ?', whereArgs: [ticketId]);
      await txn.rawInsert('''INSERT INTO conversation_control(
        user_id,state,resume_after_message_id,updated_at_ms)
        VALUES(?,'human_contacting',NULL,?) ON CONFLICT(user_id) DO UPDATE SET
        state='human_contacting',resume_after_message_id=NULL,
        updated_at_ms=excluded.updated_at_ms''', [userId, now]);
      await txn.delete('pending_customers',
          where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('generated_drafts',
          where: 'user_id = ?', whereArgs: [userId]);
    });
  }

  Future<void> markTicketContacted(int ticketId) async {
    final db = await database;
    final rows = await db.query('human_review_tickets',
        where: 'id = ?', whereArgs: [ticketId], limit: 1);
    if (rows.isEmpty) return;
    final userId = rows.first['user_id']! as String;
    final document = await (await history).read(userId);
    final messages = (document?['messages'] as List<Object?>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final boundary = messages.reversed
        .where((message) => message['direction'] == 'incoming')
        .map((message) => message['id'] as String?)
        .whereType<String>()
        .firstOrNull;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update(
          'human_review_tickets', {'status': 'contacted', 'updated_at_ms': now},
          where: 'id = ?', whereArgs: [ticketId]);
      await txn.rawInsert('''INSERT INTO conversation_control(
        user_id,state,resume_after_message_id,updated_at_ms)
        VALUES(?,'waiting_for_customer',?,?) ON CONFLICT(user_id) DO UPDATE SET
        state='waiting_for_customer',resume_after_message_id=excluded.resume_after_message_id,
        updated_at_ms=excluded.updated_at_ms''', [userId, boundary, now]);
      await txn.delete('pending_customers',
          where: 'user_id = ?', whereArgs: [userId]);
    });
  }

  Future<bool> isHumanContacting(String userId) async {
    final db = await database;
    final rows = await db.query('conversation_control',
        columns: ['state'],
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1);
    return rows.isNotEmpty && rows.first['state'] == 'human_contacting';
  }

  Future<bool> markReplySent(
      {required String userId, required String reply}) async {
    final db = await database;
    final rows = await db.query('generated_drafts',
        where: 'user_id = ? AND reply = ?',
        whereArgs: [userId, reply],
        limit: 1);
    if (rows.isEmpty) {
      // Compatibility for an unsent draft created by a pre-v5 build.
      return (await history).markReplySent(userId: userId, reply: reply);
    }
    final row = rows.first;
    final raw = jsonDecode(row['raw_json']! as String) as Map<String, dynamic>;
    final draft = AiDraft.fromJson(raw, mediaBaseUrl: Uri());
    await (await history).appendSentReply(
      userId: userId,
      displayName: userId,
      stableKey: userId,
      draft: draft,
    );
    await db
        .delete('generated_drafts', where: 'user_id = ?', whereArgs: [userId]);
    return true;
  }

  Future<void> seedDemoData() async {
    final store = await history;
    final imagePath = await store.saveMedia(
      userId: 'tb32020',
      filename: 'demo_customer_photo.png',
      bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='),
    );
    final now = DateTime.now();
    final firstDemo = CapturedConversation(
      stableKey: 'demo:tb302030',
      customerName: 'tb302030',
      customerExternalId: 'tb302030',
      capturedAt: now,
      messages: const [
        CapturedMessage(
          stableId: 'demo:tb302030:1',
          direction: 'incoming',
          body: 'Ni ha0?',
          axPath: 'demo',
        ),
      ],
    );
    await saveCapture(firstDemo);
    await _upsertPending(firstDemo);
    final secondDemo = CapturedConversation(
      stableKey: 'demo:tb32020',
      customerName: 'tb32020',
      customerExternalId: 'tb32020',
      capturedAt: now.add(const Duration(milliseconds: 1)),
      messages: [
        CapturedMessage(
          stableId: 'demo:tb32020:1',
          direction: 'incoming',
          body: 'hello',
          axPath: 'demo',
          media: [
            CapturedMedia(
              type: 'image',
              path: imagePath,
              mimeType: 'image/png',
              originalName: 'demo_customer_photo.png',
              visualFingerprint: 'ffffffffffffffff',
            ),
          ],
        ),
      ],
    );
    await saveCapture(secondDemo);
    await _upsertPending(secondDemo);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<Directory> _resolveDefaultStorageRoot() async {
    final configured = Platform.environment['QIANNIU_DATA_DIR'];
    if (configured != null && configured.trim().isNotEmpty) {
      return Directory(configured).absolute;
    }

    // Development builds live below <project>/build/macos/...; walk upward to
    // the Flutter project so `open .../jd_automation.app` still writes here.
    for (final startingPoint in <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ]) {
      var candidate = startingPoint.absolute;
      while (candidate.parent.path != candidate.path) {
        if (await File(p.join(candidate.path, 'pubspec.yaml')).exists()) {
          return Directory(p.join(candidate.path, 'data'));
        }
        candidate = candidate.parent;
      }
    }

    // Packaged installations have no source project. Allow an explicit
    // QIANNIU_DATA_DIR there; otherwise use the normal macOS fallback.
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'data'));
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
