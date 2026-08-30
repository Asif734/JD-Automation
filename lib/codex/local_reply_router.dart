import '../domain/capture_models.dart';

class LocalReplyRouter {
  const LocalReplyRouter();

  static const _greetings = <String>{
    'hi',
    'hii',
    'hiii',
    'hello',
    'hellothere',
    'hey',
    'hlw',
    'nihao',
    '你好',
    '您好',
    '在吗',
    '亲在吗',
  };

  AiDraft? route(List<Map<String, dynamic>> messages) {
    Map<String, dynamic>? latestIncoming;
    for (final message in messages.reversed) {
      if (message['direction'] == 'incoming') {
        latestIncoming = message;
        break;
      }
    }
    final body = latestIncoming?['body'];
    if (body is! String) return null;
    final normalized = _normalize(body);
    if (!_greetings.contains(normalized)) return null;
    // A deterministic greeting is appropriate only for the first customer
    // turn. In an established conversation, Codex must use recent context
    // instead of restarting the interaction.
    final incomingCount =
        messages.where((message) => message['direction'] == 'incoming').length;
    if (incomingCount > 1) return null;

    final useChinese =
        RegExp(r'[\u3400-\u9fff]').hasMatch(body) || normalized == 'nihao';
    final reply =
        useChinese ? '您好亲，在的，请问有什么可以帮您？' : 'Hello! How can I help you today?';
    final response = <String, Object?>{
      'reply': reply,
      'decision': 'draft',
      'confidence': 0.99,
      'used_record_ids': ['intent:greeting'],
      'required_slots': <String>[],
      'actions': <Object?>[],
      'risk_level': 'low',
      'risk_triggers': <String>[],
      'auto_send_allowed': false,
      'model': 'local-intent-router-v1',
      'attachments': <Object?>[],
      'image_descriptions': <Object?>[],
      'human_review_required': false,
      'reason': null,
    };
    return AiDraft.fromJson(response,
        mediaBaseUrl: Uri.parse('http://127.0.0.1'));
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('0', 'o')
      .replaceAll(RegExp(r'[^a-z\u3400-\u9fff]+'), '');
}
