import 'dart:async';

import '../domain/capture_models.dart';
import '../platform/capture_adapter.dart';
import '../storage/capture_database.dart';

class CaptureCoordinator {
  CaptureCoordinator(this.adapter, this.database);

  final CaptureAdapter adapter;
  final CaptureDatabase database;
  final _updates = StreamController<List<ConversationSummary>>.broadcast();
  StreamSubscription<CapturedConversation>? _subscription;
  Future<void> _writeTail = Future.value();

  Stream<List<ConversationSummary>> get updates => _updates.stream;

  Future<void> start() async {
    _subscription ??= adapter.captures.listen((capture) {
      // A serialized persistence queue decouples AX capture from database and future AI work.
      _writeTail = _writeTail.then((_) async {
        await database.saveCapture(capture);
        _updates.add(await database.conversations());
      }).catchError((Object error, StackTrace stack) {
        _updates.addError(error, stack);
      });
    });
    _updates.add(await database.conversations());
    await adapter.start();
  }

  Future<void> stop() => adapter.stop();

  Future<void> refresh() async => _updates.add(await database.conversations());
}
