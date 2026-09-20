import '../domain/capture_models.dart';

class LocalReplyRouter {
  const LocalReplyRouter();

  static const transferWelcome =
      'Hello! Welcome to Grozziie customer service. I’m here to help you. What can I assist you with today?';

  static const jdOnlyEnglish =
      'This customer service account supports only the JD store and JD orders. How can I help with your JD purchase or product?';
  static const jdOnlyChinese = '本客服账号仅处理京东店铺及京东订单。请问您的京东订单或产品需要什么帮助？';

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

  static const _thanks = <String>{
    'thanks',
    'thankyou',
    'thankyouverymuch',
    'great',
    'greatthanks',
    'greatthankyou',
    'greatloveyoursupport',
    'appreciateit',
    'awesome',
    'perfect',
    '好的谢谢',
    '谢谢',
    '谢谢你',
    '非常感谢',
    '太好了谢谢',
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
    final isTransfer = _isTransferHandoff(body);
    final isUnsupportedPlatform = _isUnsupportedPlatformQuestion(body);
    final isIdentityQuestion = _isIdentityQuestion(body);
    final isGreeting = _greetings.contains(normalized);
    final isThanks = _thanks.contains(normalized);
    if (!isTransfer &&
        !isUnsupportedPlatform &&
        !isIdentityQuestion &&
        !isGreeting &&
        !isThanks) {
      return null;
    }
    // A deterministic greeting is appropriate only for the first customer
    // turn. In an established conversation, Codex must use recent context
    // instead of restarting the interaction.
    final incomingCount =
        messages.where((message) => message['direction'] == 'incoming').length;
    // A transfer marker never replaces a real customer request already in the
    // visible history. Let Codex answer that request from recent context.
    if (isTransfer && incomingCount > 1) return null;
    if (!isTransfer && isGreeting && incomingCount > 1) return null;

    final useChinese =
        RegExp(r'[\u3400-\u9fff]').hasMatch(body) || normalized == 'nihao';
    final reply = isUnsupportedPlatform
        ? useChinese
            ? jdOnlyChinese
            : jdOnlyEnglish
        : isIdentityQuestion
            ? useChinese
                ? '我是京东店铺的客服人员，请问有什么可以帮您？'
                : 'I’m a customer service agent for the JD store. How can I help you?'
            : isTransfer
                ? transferWelcome
                : isThanks
                    ? useChinese
                        ? '不客气，很高兴能帮到您！'
                        : "You're very welcome! I'm glad I could help."
                    : useChinese
                        ? '您好亲，在的，请问有什么可以帮您？'
                        : 'Hello! How can I help you today?';
    final response = <String, Object?>{
      'reply': reply,
      'decision': 'draft',
      'confidence': 0.99,
      'used_record_ids': [
        isUnsupportedPlatform
            ? 'scope:jd_store_only'
            : isIdentityQuestion
                ? 'identity:customer_service_agent'
                : isTransfer
                    ? 'intent:transfer_welcome'
                    : isThanks
                        ? 'intent:thanks'
                        : 'intent:greeting'
      ],
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

  bool _isTransferHandoff(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'(您的)?同事.+将客户.+转接给您|(?:请你)?转给子账号|上次会话小结.*用户诉求[:：]?.*转接')
        .hasMatch(compact);
  }

  bool _isUnsupportedPlatformQuestion(String value) => RegExp(
        r'天猫|淘宝|拼多多|抖音|闲鱼|tmall|taobao|pinduoduo|douyin|tiktok\s*shop|amazon|ebay|aliexpress',
        caseSensitive: false,
      ).hasMatch(value);

  bool _isIdentityQuestion(String value) => RegExp(
        r'\b(?:are you|you are|r u)\s+(?:an?\s+)?(?:ai|bot|robot|human|real person)|\b(?:ai|chatbot|robot)\b|你是(?:ai|人工智能|机器人|真人)|是真人吗',
        caseSensitive: false,
      ).hasMatch(value);
}
