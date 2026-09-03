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
    expect(service.timeout, const Duration(seconds: 40));
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

  test('rejects a one-character reply before it can be sent', () {
    const response = '''{
      "reply": "1",
      "confidence": 0.8,
      "auto_send_allowed": false
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

  test('recognizes only explicit requests for a human agent', () {
    expect(explicitlyRequestsHumanAgent('Please connect me to a human agent.'),
        isTrue);
    expect(explicitlyRequestsHumanAgent('我要转人工客服'), isTrue);
    expect(explicitlyRequestsHumanAgent('macOs 26.6.2'), isFalse);
    expect(
        explicitlyRequestsHumanAgent('Does TP732 work with my Mac?'), isFalse);
  });

  test('recognizes product catalog intent across follow-up context', () {
    expect(
        hasProductCatalogIntent(
            'I need to buy an attendance machine. Which model should we buy?'),
        isTrue);
    expect(
        hasProductCatalogIntent(
            'What attendance machine products do you have?'),
        isTrue);
    expect(
        hasProductCatalogIntent(
            'We need paper card attendance for 4,000 employees.'),
        isFalse);
  });

  test('counts clarification slots across the current topic only', () {
    Map<String, dynamic> generated(String decision, List<String> slots) => {
          'direction': 'outgoing',
          'source': 'generated_reply',
          'reply_metadata': {
            'decision': decision,
            'raw_response': {
              'decision': decision,
              'required_slots': slots,
            },
          },
        };

    final messages = <Map<String, dynamic>>[
      generated('ask_clarification', ['old question']),
      generated('draft', []),
      generated('ask_clarification', [
        'number_of_employees',
        'preferred_attendance_method',
      ]),
      {
        'direction': 'outgoing',
        'source': 'jd_automation',
        'body': 'OCR copy must not count',
      },
      {
        'direction': 'incoming',
        'source': 'jd_automation',
        'body': 'paper card',
      },
    ];

    expect(clarificationQuestionsUsed(messages), 2);
  });

  test('technical uncertainty cannot create human review without a request',
      () {
    final draft = service.parseResponse('''{
      "reply":"This requires confirmation from our technical team.",
      "decision":"human_review_required",
      "confidence":0.7,
      "used_record_ids":[],
      "required_slots":[],
      "actions":[{"type":"route_human","description":"Confirm compatibility."}],
      "risk_level":"high",
      "risk_triggers":["unknown macOS compatibility"],
      "auto_send_allowed":false,
      "model":"ignored",
      "attachments":[],
      "image_descriptions":[],
      "human_review_required":true,
      "reason":"Technical confirmation required"
    }''');

    final guarded =
        service.enforceExplicitHumanReviewPolicy(draft, 'macOs 26.6.2');

    expect(draftRequiresHumanReview(guarded), isFalse);
    expect(guarded.decision, 'draft');
    expect(guarded.riskLevel, 'low');
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

  test('routes a closing thank-you without retrieving old product context', () {
    final draft = const LocalReplyRouter().route([
      <String, dynamic>{
        'direction': 'incoming',
        'body': 'I have an M880 attendance machine.'
      },
      <String, dynamic>{
        'direction': 'outgoing',
        'body': 'Here are the M880 instructions.'
      },
      <String, dynamic>{
        'direction': 'incoming',
        'body': 'great, love your support'
      },
    ]);

    expect(draft, isNotNull);
    expect(draft!.reply, "You're very welcome! I'm glad I could help.");
    expect(draft.usedRecordIds, ['intent:thanks']);
    expect(draft.reply, isNot(contains('M880')));
  });

  test('routes a transferred-account summary to the standard welcome', () {
    final draft = const LocalReplyRouter().route([
      <String, dynamic>{
        'direction': 'incoming',
        'body': '请你转给子账号小甘 Grozziie 您好老板 上次会话小结 '
            '用户诉求：催促转接 商品sku:10228712869040 咨询轨迹：查看72h内咨询轨迹',
      },
    ]);

    expect(draft, isNotNull);
    expect(draft!.reply, LocalReplyRouter.transferWelcome);
    expect(draft.usedRecordIds, ['intent:transfer_welcome']);
    expect(draft.reply, isNot(contains('人工')));
    expect(draft.reply, isNot(contains('human')));
  });

  test('retrieval query contains only the current customer turn', () {
    final messages = <Map<String, dynamic>>[
      {'direction': 'incoming', 'body': 'I have an M880 attendance machine.'},
      {
        'direction': 'outgoing',
        'body': 'Use these M880 attendance instructions.'
      },
      {
        'direction': 'incoming',
        'body': 'This is a portable printer, not an attendance machine.'
      },
      {'direction': 'incoming', 'body': 'The model is TP879.'},
    ];

    expect(buildTurnScopedRetrievalQuery(messages),
        'This is a portable printer, not an attendance machine.\nThe model is TP879.');
    expect(buildTurnScopedRetrievalQuery(messages), isNot(contains('M880')));
  });

  test('detects an explicit product correction and model replacement', () {
    expect(
        resetsPreviousProductContext(
          'This is a portable printer, not an attendance machine. Model TP879.',
          'The machine is M880.',
        ),
        isTrue);
    expect(explicitProductModels('Model TP879.'), {'tp879'});
  });

  test('filters conflicting attendance knowledge after printer correction', () {
    final filtered = filterKnowledgeForLatestProduct(
      <Map<String, Object?>>[
        {
          'id': 'attendance_product_selling_points',
          'product_line': 'attendance',
          'models': ['M880', 'M880D'],
          'issue': 'Paper-card attendance machine',
        },
        {
          'id': 'portable_printer_tp879',
          'product_line': 'portable printer',
          'models': ['TP879'],
          'issue': 'Open the paper cover',
        },
        {
          'id': 'global_refund_return_high_risk',
          'product_line': 'global',
          'models': <String>[],
          'issue': 'Refund policy',
        },
      ],
      'This is a portable printer, not an attendance machine. Model TP879.',
    );

    expect(filtered.map((record) => record['id']),
        ['portable_printer_tp879', 'global_refund_return_high_risk']);
  });

  test('catalog intent does not persist into a later courtesy turn', () {
    expect(hasProductCatalogIntent('great, love your support'), isFalse);
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

  test('retrieves an available attendance product for a buying conversation',
      () async {
    final projectRoot = Directory.current;
    final retriever = LocalKnowledgeRetriever(
        Directory('${projectRoot.path}/格志中国市场客服完整知识库-2026-08-16'));
    final records = await retriever.retrieve(
      'I need to buy an attendance machine. Which model should we buy? '
      'Paper card, 4,000 employees, one site.',
      limit: 5,
    );

    expect(
        records.any(
            (record) => record['id'] == 'attendance_product_selling_points'),
        isTrue);
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
