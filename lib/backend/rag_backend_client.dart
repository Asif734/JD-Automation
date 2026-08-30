import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/capture_models.dart';

class RagBackendClient {
  RagBackendClient({
    String? baseUrl,
    HttpClient? httpClient,
  })  : baseUrl = Uri.parse(baseUrl ??
            const String.fromEnvironment('RAG_BACKEND_URL',
                defaultValue: 'http://127.0.0.1:8080')),
        _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 4);
  }

  final Uri baseUrl;
  final HttpClient _httpClient;

  Future<BackendHealth> health() async {
    final json = await _jsonRequest('GET', '/health');
    return BackendHealth(
      available: json['status'] == 'ok',
      openAiConfigured: json['openai_configured'] == true,
      indexReady: json['index_ready'] == true,
      records: (json['records'] as num?)?.toInt() ?? 0,
      model: json['generation_model'] as String? ?? 'unknown',
    );
  }

  Future<AiDraft> draft(ConversationSummary conversation) async {
    final json = await _jsonRequest('POST', '/v1/replies/draft',
        body: buildDraftPayload(conversation));
    return AiDraft.fromJson(json, mediaBaseUrl: baseUrl);
  }

  Future<List<HumanReviewTicket>> tickets() async {
    final json = await _jsonRequest('GET', '/v1/tickets');
    return (json['items'] as List<Object?>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) => HumanReviewTicket.fromJson(item.cast<String, Object?>()))
        .toList(growable: false);
  }

  Future<HumanReviewTicket> markContacting(int ticketId,
      {String? assignedTo}) async {
    final json = await _jsonRequest('POST', '/v1/tickets/$ticketId/contacting',
        body: {'assigned_to': assignedTo});
    return HumanReviewTicket.fromJson(json);
  }

  Future<HumanReviewTicket> markContacted(
      int ticketId, String resumeAfterMessageId) async {
    final json =
        await _jsonRequest('POST', '/v1/tickets/$ticketId/contacted', body: {
      'resume_after_message_id': resumeAfterMessageId,
      'resolution_note': null,
    });
    return HumanReviewTicket.fromJson(json);
  }

  Map<String, Object?> buildDraftPayload(ConversationSummary conversation) {
    final messages = conversation.messages;
    var customerIndex = -1;
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index].direction != 'outgoing') {
        customerIndex = index;
        break;
      }
    }
    if (customerIndex < 0) {
      throw const RagBackendException(
          'No incoming customer message is available to draft a reply.');
    }
    final contextStart = customerIndex > 20 ? customerIndex - 20 : 0;
    final context = messages.sublist(contextStart, customerIndex);
    return {
      'conversation_id': conversation.stableKey,
      'customer_message_id': messages[customerIndex].stableId,
      'customer_message': messages[customerIndex].body,
      'platform': 'jd',
      'product': null,
      'messages': context
          .map((message) => {
                'direction': _apiDirection(message.direction),
                'body': message.body,
              })
          .toList(growable: false),
      'attachments': const [],
    };
  }

  String _apiDirection(String direction) =>
      const {'incoming', 'outgoing', 'unknown'}.contains(direction)
          ? direction
          : 'unknown';

  Future<Map<String, Object?>> _jsonRequest(String method, String path,
      {Map<String, Object?>? body}) async {
    try {
      final request = await _httpClient.openUrl(method, baseUrl.resolve(path));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response =
          await request.close().timeout(const Duration(seconds: 45));
      final text = await utf8.decoder.bind(response).join();
      final decoded = text.isEmpty ? <String, Object?>{} : jsonDecode(text);
      final json = decoded is Map<String, dynamic>
          ? decoded.cast<String, Object?>()
          : <String, Object?>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw RagBackendException(json['detail']?.toString() ??
            'Backend returned HTTP ${response.statusCode}.');
      }
      return json;
    } on RagBackendException {
      rethrow;
    } on SocketException {
      throw RagBackendException(
          'RAG backend is not running at $baseUrl. Start it with docker compose up -d api.');
    } on TimeoutException {
      throw const RagBackendException('The RAG backend request timed out.');
    } on FormatException {
      throw const RagBackendException('The RAG backend returned invalid JSON.');
    }
  }

  void close() => _httpClient.close(force: true);
}

class RagBackendException implements Exception {
  const RagBackendException(this.message);
  final String message;

  @override
  String toString() => message;
}
