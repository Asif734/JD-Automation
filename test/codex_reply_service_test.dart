import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/codex/codex_reply_service.dart';
import 'package:jd_automation/codex/local_knowledge_retriever.dart';
import 'package:jd_automation/codex/local_reply_router.dart';

void main() {
  late Directory root;
  late CodexReplyService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('codex_service_test_');
    service = CodexReplyService(
      executable: '/test/codex',
      workspace: Directory('${root.path}/workspace'),
      knowledgeDirectory: Directory('${root.path}/knowledge'),
      outputSchema: File('${root.path}/reply.schema.json'),
    );
  });

  tearDown(() => root.delete(recursive: true));

  test('uses ephemeral read-only execution and structured output', () {
    expect(service.timeout, const Duration(seconds: 90));
    final arguments = service.buildArguments(
      outputPath: '${root.path}/reply.json',
      imagePaths: const ['/tmp/customer image.png'],
    );
    expect(arguments,
        containsAllInOrder(['--ephemeral', '--sandbox', 'read-only']));
    expect(arguments, contains('--skip-git-repo-check'));
    expect(arguments, containsAllInOrder(['--model', 'gpt-5.6-sol']));
    expect(arguments, contains('--output-schema'));
    expect(arguments, contains('--output-last-message'));
    expect(
        arguments, containsAllInOrder(['--image', '/tmp/customer image.png']));
    expect(arguments.last, '-');
  });

  test('accepts a safe structured draft', () {
    const response = '''{
      "reply": "您好～请问有什么可以帮您？",
      "decision": "draft",
      "confidence": 0.98,
      "used_record_ids": [],
      "required_slots": [],
      "actions": [],
      "risk_level": "low",
      "risk_triggers": [],
      "auto_send_allowed": false,
      "model": "codex-cli",
      "attachments": [],
      "human_review_required": false,
      "reason": null
    }''';
    final draft = service.parseResponse(response);
    expect(draft.reply, contains('您好'));
    expect(draft.confidence, 0.98);
    expect(draft.model, 'gpt-5.6-sol');
  });

  test('rejects any response that enables auto-send', () {
    const response = '''{
      "reply": "hello",
      "confidence": 0.8,
      "auto_send_allowed": true
    }''';
    expect(() => service.parseResponse(response),
        throwsA(isA<CodexReplyException>()));
  });

  test('routine clarification cannot raise human review from conflicting flag',
      () {
    final draft = service.parseResponse('''{
      "reply":"Please confirm whether you use iPhone or Android.",
      "decision":"ask_clarification",
      "confidence":0.96,
      "used_record_ids":["attendance_manual_bluetooth_app_connect"],
      "required_slots":["phone system"],
      "actions":[],
      "risk_level":"medium",
      "risk_triggers":[],
      "auto_send_allowed":false,
      "model":"gpt-5.4-mini",
      "attachments":[],
      "human_review_required":true,
      "reason":"Inconsistent model flag"
    }''');

    expect(draftRequiresHumanReview(draft), isFalse);
  });

  test('builds a useful human-review reason when model reason is null', () {
    final draft = service.parseResponse('''{
      "reply":"Please provide the order number.",
      "decision":"human_review_required",
      "confidence":0.98,
      "used_record_ids":[],
      "required_slots":["order number"],
      "actions":[{"type":"route_human_if_abnormal","description":"Refund requires order verification."}],
      "risk_level":"high",
      "risk_triggers":["refund request"],
      "auto_send_allowed":false,
      "model":"gpt-5.4-mini",
      "attachments":[],
      "human_review_required":true,
      "reason":null
    }''');

    expect(draftHumanReviewReason(draft), contains('refund request'));
    expect(draftHumanReviewReason(draft), contains('order verification'));
  });

  test('routes standalone greeting without a Codex process', () {
    final draft = const LocalReplyRouter().route([
      <String, dynamic>{'direction': 'incoming', 'body': 'Ni ha0?'},
    ]);
    expect(draft, isNotNull);
    expect(draft!.model, 'local-intent-router-v1');
    expect(draft.reply, contains('您好'));
  });

  test('does not fast-route a substantive question', () {
    final draft = const LocalReplyRouter().route([
      <String, dynamic>{
        'direction': 'incoming',
        'body': 'How do I connect M880UT?'
      },
    ]);
    expect(draft, isNull);
  });

  test('does not restart an established conversation with a greeting', () {
    final draft = const LocalReplyRouter().route([
      <String, dynamic>{'direction': 'incoming', 'body': 'My printer failed.'},
      <String, dynamic>{'direction': 'outgoing', 'body': 'What happens?'},
      <String, dynamic>{'direction': 'incoming', 'body': 'Hi'},
    ]);
    expect(draft, isNull);
  });

  test('retrieves compact curated knowledge before Codex', () async {
    final projectRoot = Directory.current;
    final retriever = LocalKnowledgeRetriever(
        Directory('${projectRoot.path}/格志中国市场客服完整知识库-2026-08-16'));
    final records = await retriever.retrieve('我要退款', limit: 3);
    expect(records, isNotEmpty);
    expect(records.first['id'], 'global_refund_return_high_risk');
    expect(records.first, isNot(contains('keywords')));
  });

  test('retrieves verified media paths linked by selected cards', () async {
    final projectRoot = Directory.current;
    final retriever = LocalKnowledgeRetriever(
        Directory('${projectRoot.path}/格志中国市场客服完整知识库-2026-08-16'));
    final records = await retriever
        .retrieve('Show the 20-slot attendance-card rack', limit: 5);
    final media = await retriever.mediaForRecords(records);

    expect(media, isNotEmpty);
    expect(
        media.any((item) => item['path']
            .toString()
            .endsWith('attendance_card_rack_20_slot.jpg')),
        isTrue);
    expect(media.every((item) => File(item['path'].toString()).existsSync()),
        isTrue);
  });

  test('retains model context for a short comparison-photo follow-up',
      () async {
    final projectRoot = Directory.current;
    final retriever = LocalKnowledgeRetriever(
        Directory('${projectRoot.path}/格志中国市场客服完整知识库-2026-08-16'));
    final records = await retriever.retrieve(
        'M880 paper-card attendance machine\n'
        'Let us continue with M880D\n'
        'send the comparison photo',
        limit: 5);
    final media = await retriever.mediaForRecords(records);

    expect(
        records.any((item) =>
            item['id'] ==
            'attendance_m880_m880d_battery_visual_identification'),
        isTrue);
    expect(
        media.any((item) => item['path']
            .toString()
            .endsWith('m880d_rear_cover_removed_with_battery.jpg')),
        isTrue);
    expect(
        media.any((item) => item['path']
            .toString()
            .endsWith('m880_rear_cover_removed_without_battery.png')),
        isTrue);
  });

  test('strips all outbound attachments for JD text-only replies', () {
    final response = '''{
      "reply":"Here is the image.",
      "decision":"draft",
      "confidence":0.9,
      "used_record_ids":[],
      "required_slots":[],
      "actions":[],
      "risk_level":"low",
      "risk_triggers":[],
      "auto_send_allowed":false,
      "model":"ignored",
      "attachments":[
        {"media_id":"approved","kind":"image","caption":"fake","path":"/etc/passwd"},
        {"media_id":"invented","kind":"image","caption":"bad","path":"/tmp/bad.png"}
      ],
      "image_descriptions":[
        {"path":"/data/customer.png","description":"A white printer is visible."},
        {"path":"/tmp/invented.png","description":"Must be rejected."}
      ],
      "human_review_required":false,
      "reason":null
    }''';
    final draft = service.parseResponse(
      response,
      approvedAttachments: const [
        {
          'media_id': 'approved',
          'kind': 'image',
          'caption': 'Verified product image',
          'path': '/knowledge/product.jpg',
        }
      ],
      approvedImagePaths: const {'/data/customer.png'},
    );

    expect(draft.attachments, isEmpty);
    expect(draft.imageDescriptions,
        {'/data/customer.png': 'A white printer is visible.'});
  });

  test('recognizes product photo requests in English and Chinese', () {
    expect(
        isProductPhotoRequest('Can you send photos of this printer?'), isTrue);
    expect(isProductPhotoRequest('你们有这个产品的图片吗？'), isTrue);
    expect(isProductPhotoRequest('I attached a photo of the error'), isFalse);
    expect(isProductPhotoRequest('How do I connect the printer?'), isFalse);
  });

  test('forces product photo requests into human review', () {
    final ordinary = service.parseResponse('''{
      "reply":"Which photo do you need?",
      "decision":"ask_clarification",
      "confidence":0.8,
      "used_record_ids":[],
      "required_slots":[],
      "actions":[],
      "risk_level":"low",
      "risk_triggers":[],
      "auto_send_allowed":false,
      "model":"ignored",
      "attachments":[],
      "image_descriptions":[],
      "human_review_required":false,
      "reason":null
    }''');

    final guarded = service.enforceProductPhotoReview(
        ordinary, 'Please send photos of this printer.');

    expect(guarded.decision, 'human_review_required');
    expect(draftRequiresHumanReview(guarded), isTrue);
    expect(guarded.attachments, isEmpty);
    expect(guarded.reply, contains('agent will follow up'));
    expect(draftHumanReviewReason(guarded),
        contains('Customer requested product photos'));
  });
}
