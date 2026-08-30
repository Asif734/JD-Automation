import '../domain/capture_models.dart';

abstract interface class CaptureAdapter {
  Stream<CapturedConversation> get captures;
  Stream<Map<String, Object?>> get diagnostics;

  Future<Map<String, Object?>> status();
  Future<bool> requestAccessibility();
  Future<void> start();
  Future<void> stop();
  Future<Map<String, Object?>> inspectTree({int maxDepth = 12});
}
