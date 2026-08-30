import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/backend/rag_backend_client.dart';
import 'package:jd_automation/domain/capture_models.dart';

void main() {
  test('draft payload separates latest customer message from prior context',
      () {
    final client = RagBackendClient();
    final conversation = ConversationSummary(
      id: 1,
      userId: 'customer-1',
      customerName: 'Customer',
      stableKey: 'conversation-1',
      lastActivityAt: DateTime.fromMillisecondsSinceEpoch(4),
      messages: [
        StoredMessage(
            stableId: '1',
            direction: 'incoming',
            body: 'Show M880 pictures',
            capturedAt: DateTime.fromMillisecondsSinceEpoch(1)),
        StoredMessage(
            stableId: '2',
            direction: 'outgoing',
            body: 'Which view?',
            capturedAt: DateTime.fromMillisecondsSinceEpoch(2)),
        StoredMessage(
            stableId: '3',
            direction: 'incoming',
            body: 'Both exterior and screen',
            capturedAt: DateTime.fromMillisecondsSinceEpoch(3)),
      ],
    );

    final payload = client.buildDraftPayload(conversation);
    expect(payload['customer_message'], 'Both exterior and screen');
    expect(payload['customer_message_id'], '3');
    expect(payload['conversation_id'], 'conversation-1');
    expect(payload['messages'], hasLength(2));
    expect(payload['product'], isNull);
    client.close();
  });
}
