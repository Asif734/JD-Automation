import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/codex/codex_reply_service.dart';
import 'package:jd_automation/codex/local_knowledge_retriever.dart';
import 'package:jd_automation/codex/local_reply_router.dart';
import 'package:jd_automation/codex/semantic_knowledge_scorer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('frozen batch uses answered cursor even if earlier reply is last', () {
    final messages = <Map<String, dynamic>>[
      {'id': 'image-1', 'direction': 'incoming', 'body': '[image]'},
      {'id': 'text-2', 'direction': 'incoming', 'body': 'What is this?'},
      {'id': 'reply-1', 'direction': 'outgoing', 'body': 'Image reply'},
    ];
    final batch = customerBatchThroughMessage(messages,
        endMessageId: 'text-2', answeredMessageId: 'image-1');
    expect(batch.map((message) => message['id']), ['text-2']);
  });

  test('orphaned OCR cursor falls back to the last sent reply', () {
    final messages = <Map<String, dynamic>>[
      {'id': 'old-question', 'direction': 'incoming', 'body': 'M880UT shift'},
      {'id': 'old-reply', 'direction': 'outgoing', 'source': 'generated_reply'},
      {'id': 'model', 'direction': 'incoming', 'body': 'I have TP732'},
      {
        'id': 'question',
        'direction': 'incoming',
        'body': 'How to connect app?'
      },
    ];
    final batch = customerBatchThroughMessage(messages,
        endMessageId: 'question', answeredMessageId: 'replaced-ocr-id');
    expect(batch.map((message) => message['id']), ['model', 'question']);
  });

  test('creates a durable read-only session with structured output', () {
    expect(service.timeout, isNull);
    final arguments = service.buildArguments(
      outputPath: '${root.path}/reply.json',
      imagePaths: const ['/tmp/customer image.png'],
    );
    expect(arguments, containsAllInOrder(['--sandbox', 'read-only']));
    expect(arguments, isNot(contains('--ephemeral')));
    expect(arguments, contains('--json'));
    expect(arguments, contains('--ignore-user-config'));
    expect(arguments, contains('--skip-git-repo-check'));
    expect(arguments, containsAllInOrder(['--model', 'gpt-5.6-sol']));
    expect(arguments,
        containsAllInOrder(['--config', 'model_reasoning_effort="low"']));
    expect(
        arguments, containsAllInOrder(['--config', 'model_verbosity="low"']));
    expect(arguments, contains('--output-schema'));
    expect(arguments, contains('--output-last-message'));
    expect(
        arguments, containsAllInOrder(['--image', '/tmp/customer image.png']));
    expect(arguments.last, '-');
  });

  test('resumes only the specified customer session', () {
    final arguments = service.buildArguments(
      outputPath: '${root.path}/reply.json',
      sessionId: 'customer-thread-id',
    );
    expect(arguments.take(2), ['exec', 'resume']);
    expect(arguments, isNot(contains('--ephemeral')));
    expect(arguments, isNot(contains('--cd')));
    expect(arguments, containsAllInOrder(['customer-thread-id', '-']));
    expect(
        parseCodexThreadId(
            '{"type":"thread.started","thread_id":"customer-thread-id"}\n'
            '{"type":"turn.completed"}\n'),
        'customer-thread-id');
  });

  test('uses a fast bounded model for contextual query planning', () {
    final arguments =
        service.buildPlannerArguments(outputPath: '${root.path}/plan.json');
    expect(arguments, containsAllInOrder(['--model', 'gpt-5.6-luna']));
    expect(arguments, contains(service.searchPlanSchema.absolute.path));
    expect(arguments, isNot(contains('--image')));
    expect(arguments.last, '-');
  });

  test('parses exactly one focused knowledge query', () {
    expect(
      parseKnowledgeSearchPlan(
          '{"queries":["M880D previous year","M880D 去年日期","third","fourth"]}'),
      ['M880D previous year'],
    );
  });

  test('plans only context-dependent customer turns', () {
    expect(needsKnowledgeQueryPlanning('yes'), isTrue);
    expect(needsKnowledgeQueryPlanning('what about it?'), isTrue);
    expect(needsKnowledgeQueryPlanning('Can M880D change its date to 2025?'),
        isFalse);
  });

  test('merges planned and raw retrieval without duplicate records', () {
    final merged = mergeKnowledgeResults([
      [
        {'id': 'planned-a'},
        {'id': 'shared'},
      ],
      [
        {'id': 'raw-a'},
        {'id': 'shared'},
      ],
    ]);
    expect(
        merged.map((record) => record['id']), ['planned-a', 'raw-a', 'shared']);
  });

  test('timeout fallback routes the conversation to human review', () {
    final draft = service.contextAwareFallback(
      <Map<String, dynamic>>[
        {'direction': 'incoming', 'body': 'model is TP732'},
        {
          'direction': 'outgoing',
          'body': 'How are you connecting it and which macOS version?'
        },
        {
          'direction': 'incoming',
          'body': 'by blutooth, macos version 26.6; it is not connecting'
        },
      ],
      hasImage: false,
      failure: CodexFallbackFailure.timeout,
    );

    expect(draft.model, 'local-timeout-fallback-v2');
    expect(draft.reply, contains('进一步准确核对'));
    expect(draft.reply, isNot(contains('senior customer service agent')));
    expect(draft.reply, isNot(contains('forwarded')));
    expect(draft.decision, 'human_review_required');
    expect(draftRequiresHumanReview(draft), isTrue);
    expect(draft.actions, isEmpty);
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

  test('uses Codex-classified message IDs for transfer requests', () {
    final draft = service.parseResponse('''{
      "reply":"I can help with that.",
      "decision":"draft",
      "confidence":0.9,
      "used_record_ids":[],
      "required_slots":[],
      "actions":[],
      "risk_level":"low",
      "risk_triggers":[],
      "auto_send_allowed":false,
      "model":"test",
      "attachments":[],
      "image_descriptions":[],
      "human_review_required":false,
      "human_transfer_request_message_ids":["first","second"],
      "reason":null
    }''');
    expect(codexHumanTransferRequestIds(draft), {'first', 'second'});
  });

  test('recognizes dissatisfaction with automated support', () {
    expect(isCustomerDissatisfiedWithSupport('I am not satisfied'), isTrue);
    expect(
        isCustomerDissatisfiedWithSupport('This reply did not help'), isTrue);
    expect(isCustomerDissatisfiedWithSupport('还是没解决，一直重复'), isTrue);
    expect(isCustomerDissatisfiedWithSupport('The printer is not connected'),
        isFalse);
  });

  test('excludes truncated Qianniu sidebar previews from Codex context', () {
    expect(
        isLikelySidebarPreviewLeak({
          'source': 'jd_automation',
          'direction': 'incoming',
          'body': 'For only 3 employees, the M880... what is the other model',
        }),
        isTrue);
    expect(
        isLikelySidebarPreviewLeak({
          'source': 'qianniu_capture',
          'direction': 'outgoing',
          'body': 'For 300 employees, our confirm... You\'re welcome!',
        }),
        isTrue);
    expect(
        isLikelySidebarPreviewLeak({
          'source': 'generated_reply',
          'direction': 'outgoing',
          'body': 'Please wait... I am checking that for you.',
        }),
        isFalse);
  });

  test('customer model excludes conflicting polluted assistant context', () {
    final filtered = excludeOutgoingModelConflicts([
      {'direction': 'incoming', 'body': 'I mean TD630G'},
      {
        'direction': 'outgoing',
        'body': 'The TD630 is the other printer model.'
      },
      {'direction': 'outgoing', 'body': 'The other model was M880.'},
      {'direction': 'incoming', 'body': 'is it a printer?'},
    ], {
      'td630g'
    });

    expect(filtered.map((message) => message['body']), [
      'I mean TD630G',
      'The TD630 is the other printer model.',
      'is it a printer?',
    ]);
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
    expect(hasProductSuggestionIntent('What do you suggest?'), isTrue);
    expect(
        hasProductContext('We need a paper-card attendance machine.'), isTrue);
    expect(
        hasProductCatalogIntentWithContext(
          'What do you suggest?',
          'We need a paper-card attendance machine.',
        ),
        isTrue);
    expect(
        hasProductCatalogIntentWithContext(
          'Great, thank you.',
          'Which printer do you recommend?',
        ),
        isFalse);
    expect(hasProductCatalogIntent('what are the thermal printer you have?'),
        isTrue);
    expect(hasProductCatalogIntent('can i get a model.list?'), isTrue);
    expect(hasProductListIntent('热敏打印机有哪些型号？'), isTrue);
    expect(
        hasProductCatalogIntentWithContext(
            'what are the other model?', 'I need a thermal printer.'),
        isTrue);
  });

  test('loads the dedicated product recommendation catalog', () async {
    final projectRoot = Directory.current;
    final catalog = await loadProductRecommendationCatalog(Directory(
        '${projectRoot.path}/格志中国市场客服完整知识库-2026-09-15-r21-consolidated'));

    expect(catalog, contains('knowledge_base: product_model_feature_catalog'));
    expect(catalog, contains('## r21 Current 型号清单'));
    expect(catalog, contains('TD630G'));
  });

  test('model feature questions use exact r21 catalog evidence', () async {
    final catalog = await loadProductRecommendationCatalog(Directory(
        '${Directory.current.path}/格志中国市场客服完整知识库-2026-09-15-r21-consolidated'));
    expect(hasProductFeatureIntent('what are the features for tp730?'), isTrue);
    expect(hasProductFeatureIntent('what features tp874 offers?'), isTrue);
    expect(hasProductFeatureIntent('TP874 打印参数和纸宽？'), isTrue);
    expect(hasProductFeatureIntent('Does TP874 support Android?'), isTrue);
    expect(hasProductFeatureIntent('Tell me about TP730'), isTrue);
    expect(hasProductFeatureIntent('My TP874 is not connecting'), isFalse);

    final tp730 = verifiedCatalogRowsForModels(catalog, {'tp730'});
    expect(
        tp730.map((row) => row['source_row']).join('\n'), contains('30–100mm'));
    expect(
        verifiedCatalogRowsForModels(
            '## test\n| TP730S | 30–80mm | other SKU |', {'tp730'}),
        isEmpty);

    final tp874 = verifiedCatalogRowsForModels(catalog, {'tp874'});
    final evidence = tp874.map((row) => row['source_row']).join('\n');
    expect(evidence, contains('30–80mm'));
    expect(evidence, contains('USB+蓝牙'));
    expect(evidence, contains('203DPI'));
    expect(evidence, contains('macOS USB'));
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

  test('unresolved technical issue can create human review', () {
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

    final guarded = service.enforceHumanReviewPolicy(draft, 'macOs 26.6.2');

    expect(draftRequiresHumanReview(guarded), isTrue);
    expect(guarded.decision, 'human_review_required');
    expect(guarded.riskLevel, 'high');
    expect(guarded.reply, contains('进一步准确核对'));
    expect(guarded.reply, isNot(contains('senior customer service agent')));
    expect(guarded.reply, isNot(contains('forwarded')));
  });

  test('second technical investigation retains a requested review ticket', () {
    final draft = service.parseResponse('''{
      "reply":"The available checks are complete, but this needs a service colleague.",
      "decision":"human_review_required",
      "confidence":0.4,
      "used_record_ids":[],
      "required_slots":[],
      "actions":[],
      "risk_level":"high",
      "risk_triggers":["remaining technical issue"],
      "auto_send_allowed":false,
      "model":"test",
      "attachments":[],
      "image_descriptions":[],
      "human_review_required":true,
      "reason":"Second investigation could not find a safe fix."
    }''');

    final guarded = service.enforceHumanReviewPolicy(
      draft,
      'My printer has error 42',
      technicalSecondInvestigationCompleted: true,
    );

    expect(draftRequiresHumanReview(guarded), isTrue);
    expect(guarded.decision, 'human_review_required');
    expect(guarded.reply, contains('进一步准确核对'));
  });

  test('recognizes refund and video-guide review requests', () {
    expect(isRefundRequest('I need a refund'), isTrue);
    expect(isRefundRequest('我要退款'), isTrue);
    expect(isVideoGuideRequest('Please send the setup video guide'), isTrue);
    expect(isVideoGuideRequest('请发设置视频教程'), isTrue);
    expect(isVideoGuideRequest('I sent a fault video'), isFalse);
  });

  test('keeps the technical subject for a short follow-up complaint', () {
    const recent = 'I use macOS\nWhere can I get the TP874 driver?\n'
        'Then how do I connect it?';
    expect(
        isTechnicalSupportTurn('you should have product link', recent), isTrue);
    expect(isTechnicalSupportTurn('thank you', recent), isFalse);
  });

  test('selects one reply route before prompt construction', () {
    String route({
      String text = 'help',
      bool technical = false,
      bool list = false,
      bool catalog = false,
      bool features = false,
    }) =>
        selectReplyRoute(
          currentTurnText: text,
          technicalSupportRequested: technical,
          productListRequested: list,
          productCatalogRequested: catalog,
          productFeatureRequested: features,
        );

    expect(route(technical: true, catalog: true), 'technical_support');
    expect(route(list: true), 'product_list');
    expect(route(catalog: true), 'product_recommendation');
    expect(route(features: true), 'product_features');
    expect(route(text: 'I need a refund', technical: true), 'refund_review');
    expect(route(), 'general_support');
  });

  test('recognizes Codex video-thumbnail descriptions', () {
    expect(
        codexIdentifiedVideoThumbnail(
            'A blurred video thumbnail with a play button.'),
        isTrue);
    expect(codexIdentifiedVideoThumbnail('画面中有一个视频缩略图和播放按钮'), isTrue);
    expect(codexIdentifiedVideoThumbnail('A printer with a round power key.'),
        isFalse);
  });

  test('forces refund and video-guide requests into human review', () {
    final ordinary = service.parseResponse('''{
      "reply":"I can help.",
      "decision":"draft",
      "confidence":0.9,
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

    final refund =
        service.enforceHumanReviewPolicy(ordinary, 'I need a refund');
    final video = service.enforceHumanReviewPolicy(
        ordinary, 'Please send the setup video guide');

    expect(draftRequiresHumanReview(refund), isTrue);
    expect(refund.reply, contains('退款申请'));
    expect(draftHumanReviewReason(refund), contains('refund'));
    expect(draftRequiresHumanReview(video), isTrue);
    expect(video.reply, contains('视频教程'));
  });

  test('first human request offers help and the repeated request transfers',
      () {
    final ordinary = service.parseResponse('''{
      "reply":"I can continue troubleshooting.",
      "decision":"draft",
      "confidence":0.9,
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
    final noSolution = service.parseResponse('''{
      "reply":"I cannot find a reliable solution.",
      "decision":"draft",
      "confidence":0.4,
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

    final firstHuman = service.enforceHumanReviewPolicy(
        ordinary, 'Please connect me to a human agent',
        humanTransferRequested: true);
    final repeatedHuman = service.enforceHumanReviewPolicy(
        ordinary, 'Please transfer',
        humanTransferRequested: true, repeatedHumanTransferRequest: true);
    final dissatisfied =
        service.enforceHumanReviewPolicy(ordinary, 'This reply did not help');
    final unresolved =
        service.enforceHumanReviewPolicy(noSolution, 'My printer still fails');

    expect(draftRequiresHumanReview(firstHuman), isFalse);
    expect(firstHuman.decision, 'ask_clarification');
    expect(firstHuman.reply, contains('请问您遇到了什么问题'));
    expect(firstHuman.reply.toLowerCase(), isNot(contains('human agent')));
    expect(draftRequiresHumanReview(repeatedHuman), isTrue);
    expect(draftHumanReviewReason(repeatedHuman),
        contains('explicitly requested'));
    expect(draftRequiresHumanReview(dissatisfied), isTrue);
    expect(draftHumanReviewReason(dissatisfied), contains('dissatisfied'));
    expect(draftRequiresHumanReview(unresolved), isTrue);
    expect(draftHumanReviewReason(unresolved), contains('reliable solution'));
    for (final guarded in [repeatedHuman, dissatisfied, unresolved]) {
      expect(guarded.reply, isNot(contains('senior customer service agent')));
      expect(guarded.reply.toLowerCase(), isNot(contains('forwarded')));
      expect(guarded.reply.toLowerCase(), isNot(contains('transferred')));
    }
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

  test('welcomes a returning customer after a long gap', () {
    final draft = const LocalReplyRouter().route([
      <String, dynamic>{
        'direction': 'incoming',
        'body': 'What is the price?',
        'captured_at': '2026-09-20T08:52:34Z',
      },
      <String, dynamic>{
        'direction': 'outgoing',
        'body': 'I will check.',
        'captured_at': '2026-09-20T08:53:41Z',
      },
      <String, dynamic>{
        'direction': 'incoming',
        'body': 'hi',
        'captured_at': '2026-09-21T08:16:01Z',
      },
    ]);

    expect(draft, isNotNull);
    expect(draft!.reply, LocalReplyRouter.transferWelcome);
  });

  test('welcomes a greeting after transfer even with recent history', () {
    final transferAt = DateTime.utc(2026, 9, 21, 8, 15);
    final messages = <Map<String, dynamic>>[
      {
        'direction': 'incoming',
        'body': 'What about the price?',
        'captured_at': '2026-09-21T08:14:00Z',
      },
      {
        'direction': 'incoming',
        'body': 'hi',
        'captured_at': '2026-09-21T08:16:00Z',
      },
    ];
    final router = const LocalReplyRouter();

    expect(router.route(messages), isNull);
    expect(router.route(messages, transferNoticeAt: transferAt)?.reply,
        LocalReplyRouter.transferWelcome);
    messages.insert(1, {
      'direction': 'outgoing',
      'body': LocalReplyRouter.transferWelcome,
      'captured_at': '2026-09-21T08:15:30Z',
    });
    expect(router.route(messages, transferNoticeAt: transferAt), isNull);
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
    expect(draft!.reply, '不客气，很高兴能帮到您！');
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

  test('answers recent context instead of welcoming after a transfer', () {
    final draft = const LocalReplyRouter().route([
      <String, dynamic>{
        'direction': 'incoming',
        'body': 'How do I install the TP874 driver?'
      },
      <String, dynamic>{
        'direction': 'incoming',
        'body': '请你转给子账号小甘 Grozziie 上次会话小结 用户诉求：安装驱动',
      },
    ]);

    expect(draft, isNull);
  });

  test('identifies as a JD customer service agent', () {
    final draft = const LocalReplyRouter().route([
      <String, dynamic>{
        'direction': 'incoming',
        'body': 'Are you an AI assistant?'
      },
    ]);

    expect(draft, isNotNull);
    expect(draft!.reply, contains('客服人员'));
    expect(draft.reply.toLowerCase(), isNot(contains('ai')));
  });

  test('keeps other marketplace questions within JD scope', () {
    final draft = const LocalReplyRouter().route([
      <String, dynamic>{
        'direction': 'incoming',
        'body': 'Can you check my Tmall order?'
      },
    ]);

    expect(draft, isNotNull);
    expect(draft!.reply, contains('京东店铺'));
    expect(draft.reply, isNot(contains('Tmall')));
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

  test('focused retrieval uses the latest three customer turns only', () {
    final messages = <Map<String, dynamic>>[
      {'direction': 'incoming', 'body': 'An unrelated older question'},
      {'direction': 'outgoing', 'body': 'An old assistant reply'},
      {
        'direction': 'incoming',
        'body': 'can you suggest me a printer that can print labels'
      },
      {
        'direction': 'outgoing',
        'body': 'TP874 may work, but compatibility needs checking.'
      },
      {'direction': 'incoming', 'body': 'phone and MacBook too'},
      {'direction': 'outgoing', 'body': 'Incorrectly mentioned M880DT.'},
      {
        'direction': 'incoming',
        'body': "I don't require an attendance machine; I need a label printer."
      },
    ];

    final turns = latestRelevantCustomerTurns(messages);
    expect(turns.map((message) => message['body']), [
      'can you suggest me a printer that can print labels',
      'phone and MacBook too',
      "I don't require an attendance machine; I need a label printer.",
    ]);
    expect(
        lastAssistantReply(messages)?['body'], 'Incorrectly mentioned M880DT.');

    final constraints = inferProductRetrievalConstraints(turns);
    expect(constraints.requiredCategories, contains('thermal_label_printer'));
    expect(constraints.excludedCategories, contains('attendance_machine'));

    final query = buildFocusedRetrievalQuery(
      customerTurns: turns,
      confirmedModels: const <String>{},
      categoryConstraints: constraints,
    );
    expect(query, contains('phone and MacBook too'));
    expect(query, contains('thermal_label_printer'));
    expect(query, contains('Exclude product category: attendance_machine'));
    expect(query, isNot(contains('Incorrectly mentioned M880DT')));
  });

  test('retrieval conversation keeps clarification questions with answers', () {
    final messages = <Map<String, dynamic>>[
      {'direction': 'incoming', 'body': 'Unrelated older request'},
      {'direction': 'outgoing', 'body': 'Unrelated older reply'},
      {'direction': 'incoming', 'body': 'I need a thermal label printer'},
      {
        'direction': 'outgoing',
        'body': 'I recommend TP874. Will you use Windows or Android?',
        'source': 'generated_reply',
      },
      {'direction': 'incoming', 'body': 'Android'},
    ];

    final conversation =
        latestRelevantConversation(messages, customerTurnLimit: 2);

    expect(conversation.map((message) => message['body']), [
      'I need a thermal label printer',
      'I recommend TP874. Will you use Windows or Android?',
      'Android',
    ]);
    expect(conversation[1]['context_role'], 'untrusted_assistant_context');
    expect(conversation[2]['context_role'], 'customer_requirement');
  });

  test('model parser rejects ordinary words followed by quantities', () {
    expect(explicitProductModels('for 300 employees'), isEmpty);
    expect(explicitProductModels('nor 300'), isEmpty);
    expect(explicitProductModels('not 300'), isEmpty);
    expect(explicitProductModels('TP874 and M880D'), {'tp874', 'm880d'});
    expect(explicitProductModels('GZP510 and JPW760S'), {'gzp510', 'jpw760s'});
    expect(explicitProductModels('macOS 26 and iOS18 with 203DPI'), isEmpty);
  });

  test('conversation resolves this and clarification answers to TP874', () {
    final base = <Map<String, dynamic>>[
      {'direction': 'incoming', 'body': 'I need other model'},
      {'direction': 'incoming', 'body': 'I require a thermal printer'},
      {
        'direction': 'outgoing',
        'body': 'I recommend TP874 for thermal labels.',
      },
    ];

    final reference = resolveProductModels(
      recentConversation: [
        ...base,
        {'direction': 'incoming', 'body': 'how to use this'},
      ],
      currentCustomerText: 'how to use this',
      productContextReset: false,
    );
    expect(reference.models, {'tp874'});
    expect(reference.source, 'assistant_reference');

    final answer = resolveProductModels(
      recentConversation: [
        ...base,
        {
          'direction': 'outgoing',
          'body': 'For TP874, will you use Windows or Android?',
        },
        {'direction': 'incoming', 'body': 'Android'},
      ],
      currentCustomerText: 'Android',
      productContextReset: false,
    );
    expect(answer.models, {'tp874'});
    expect(answer.source, 'assistant_reference');
  });

  test('confirmation retrieval includes the question it answers', () {
    final messages = <Map<String, dynamic>>[
      {'direction': 'incoming', 'body': 'can i set date to the last year'},
      {
        'direction': 'outgoing',
        'body': 'Do you mean setting the M880D date to 2025?'
      },
      {'direction': 'incoming', 'body': 'yes'},
      {
        'direction': 'incoming',
        'body': 'you got it right 请尽快回复客户咨询，即将为客户推荐相似商品哦~'
      },
    ];

    expect(
      buildKnowledgeRetrievalQuery(messages),
      contains('can i set date to the last year'),
    );
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

  test('carries the latest customer model into pronoun follow-ups', () {
    final messages = <Map<String, dynamic>>[
      {'direction': 'incoming', 'body': 'my old machine was TP879'},
      {'direction': 'outgoing', 'body': 'Okay'},
      {'direction': 'incoming', 'body': 'it is only TP874, no D'},
      {'direction': 'outgoing', 'body': 'Understood'},
      {'direction': 'incoming', 'body': 'what are the features of it?'},
      {'direction': 'incoming', 'body': 'what is different from others?'},
    ];

    expect(activeProductModels(messages), {'tp874'});
  });

  test('model-free product change clears inherited product memory', () {
    final messages = <Map<String, dynamic>>[
      {'direction': 'incoming', 'body': 'tell me about TP874'},
      {'direction': 'outgoing', 'body': 'Okay'},
      {'direction': 'incoming', 'body': 'this is another product'},
      {'direction': 'incoming', 'body': 'what are its features?'},
    ];

    expect(activeProductModels(messages), isEmpty);
  });

  test('other model resets inherited product memory', () {
    final messages = <Map<String, dynamic>>[
      {'direction': 'incoming', 'body': 'my old printer is TP732'},
      {'direction': 'outgoing', 'body': 'Understood'},
      {'direction': 'incoming', 'body': 'I need other model'},
      {'direction': 'incoming', 'body': 'which one should I buy?'},
    ];

    expect(activeProductModels(messages), isEmpty);
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

  test('category constraints reject the Mac-address attendance false match',
      () {
    final constraints = inferProductRetrievalConstraints([
      {
        'direction': 'incoming',
        'body': 'can you suggest me a printer that can print labels'
      },
      {'direction': 'incoming', 'body': 'phone and MacBook too'},
      {
        'direction': 'incoming',
        'body': 'shipping labels, size does not matter'
      },
    ]);
    final filtered = filterKnowledgeForLatestProduct(
      <Map<String, Object?>>[
        {
          'id': 'attendance_manual_bluetooth_app_connect',
          'product_line': 'attendance_machine',
          'models': ['M880UT'],
          'issue': 'Attendance machine Bluetooth App and MAC address',
        },
        {
          'id': 'thermal_product_selling_points',
          'product_line': 'thermal_printer',
          'models': ['TP874'],
          'issue': 'Shipping-label thermal printer',
        },
      ],
      'phone and MacBook too',
      categoryConstraints: constraints,
    );

    expect(filtered.map((record) => record['id']),
        ['thermal_product_selling_points']);
  });

  test('short MAC keyword does not match MacBook as a substring', () async {
    final knowledge = Directory('${root.path}/mac-boundary-knowledge');
    final ragCards = Directory('${knowledge.path}/rag_cards');
    await ragCards.create(recursive: true);
    await File('${ragCards.path}/customer_service_rag_cards.jsonl')
        .writeAsString(
      '{"id":"attendance_mac","status":"active","keywords":["MAC"],"issue":"Attendance machine MAC address","priority":100}\n'
      '{"id":"computer_compatibility","status":"active","keywords":["MacBook"],"issue":"Computer compatibility","priority":1}\n',
    );

    final records =
        await LocalKnowledgeRetriever(knowledge).retrieve('MacBook', limit: 2);

    expect(records.first['id'], 'computer_compatibility');
  });

  test('catalog intent does not persist into a later courtesy turn', () {
    expect(hasProductCatalogIntent('great, love your support'), isFalse);
  });

  test('retrieves compact curated knowledge before Codex', () async {
    final projectRoot = Directory.current;
    final retriever = LocalKnowledgeRetriever(Directory(
        '${projectRoot.path}/格志中国市场客服完整知识库-2026-09-15-r21-consolidated'));
    final records = await retriever.retrieve('我要退款', limit: 3);
    expect(records, isNotEmpty);
    expect(records.first['id'], 'global_refund_return_high_risk');
    expect(records.first, isNot(contains('keywords')));
  });

  test('retrieves customer knowledge without indexing planning documents',
      () async {
    final knowledge = Directory('${root.path}/knowledge');
    final ragCards = Directory('${knowledge.path}/rag_cards');
    await ragCards.create(recursive: true);
    await File('${ragCards.path}/customer_service_rag_cards.jsonl').writeAsString(
        '{"id":"card_zephyr","status":"active","issue":"zephyrcardtoken","reply_template":"card answer"}\n');
    await File('${ragCards.path}/source_chunks.jsonl').writeAsString(
        '{"id":"chunk_orbit","type":"source_chunk","source_file":"source.md","content":"orbitchunktoken"}\n');
    await File('${knowledge.path}/first_kb.md')
        .writeAsString('# First\n\nzirconmarkdownone');
    final nestedMarkdownFile = File('${knowledge.path}/docs/plan.md');
    await nestedMarkdownFile.create(recursive: true);
    await nestedMarkdownFile.writeAsString('# Second\n\nquasarmarkdowntwo');

    final retriever = LocalKnowledgeRetriever(knowledge);
    final card = await retriever.retrieve('zephyrcardtoken', limit: 1);
    final sourceChunk = await retriever.retrieve('orbitchunktoken', limit: 1);
    final firstMarkdown =
        await retriever.retrieve('zirconmarkdownone', limit: 1);
    final nestedMarkdown =
        await retriever.retrieve('quasarmarkdowntwo', limit: 1);

    expect(card.single['id'], 'card_zephyr');
    expect(sourceChunk.single['id'], 'chunk_orbit');
    expect(firstMarkdown.single['source_file'], 'first_kb.md');
    expect(firstMarkdown.single['content'], contains('zirconmarkdownone'));
    expect(
      nestedMarkdown.any((record) => record['source_file'] == 'docs/plan.md'),
      isFalse,
    );
  });

  test('retrieval omits non-JD marketplace evidence', () async {
    final knowledge = Directory('${root.path}/jd_only_knowledge');
    final ragCards = Directory('${knowledge.path}/rag_cards');
    await ragCards.create(recursive: true);
    await File('${ragCards.path}/customer_service_rag_cards.jsonl')
        .writeAsString(
      '{"id":"tmall_only","status":"active","title":"Tmall order rule","issue":"scopechecktoken","reply_template":"Tmall answer"}\n'
      '{"id":"jd_mixed","status":"active","title":"JD support","issue":"scopechecktoken","reply_template":"JD answer. Tmall answer."}\n',
    );

    final records = await LocalKnowledgeRetriever(knowledge)
        .retrieve('scopechecktoken', limit: 5);
    final encoded = records.toString().toLowerCase();

    expect(records.map((record) => record['id']), contains('jd_mixed'));
    expect(
        records.map((record) => record['id']), isNot(contains('tmall_only')));
    expect(encoded, isNot(contains('tmall')));
    expect(encoded, contains('jd answer'));
  });

  test('retrieves an available attendance product for a buying conversation',
      () async {
    final projectRoot = Directory.current;
    final retriever = LocalKnowledgeRetriever(Directory(
        '${projectRoot.path}/格志中国市场客服完整知识库-2026-09-15-r21-consolidated'));
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

  test('semantic similarity reranks matching lexical candidates', () async {
    final knowledge = Directory('${root.path}/semantic_knowledge');
    final ragCards = Directory('${knowledge.path}/rag_cards');
    await ragCards.create(recursive: true);
    await File('${ragCards.path}/customer_service_rag_cards.jsonl').writeAsString(
        '{"id":"card_a","status":"active","keywords":["printer"],"issue":"alpha"}\n'
        '{"id":"card_b","status":"active","keywords":["printer"],"issue":"beta"}\n');
    final lexical = await LocalKnowledgeRetriever(knowledge,
            semanticScorer: _FixedSemanticScorer(const {}))
        .retrieve('printer', limit: 2);
    final hybrid = await LocalKnowledgeRetriever(knowledge,
            semanticScorer: _FixedSemanticScorer(const {'card_b': 0.95}))
        .retrieve('printer', limit: 2);

    expect(lexical.map((record) => record['id']), ['card_a', 'card_b']);
    expect(hybrid.map((record) => record['id']), ['card_b', 'card_a']);
  });

  test('semantic scorer maps an English thermal model list to Chinese terms',
      () async {
    const channel =
        MethodChannel('com.grozziie.jdAutomation/semanticRetrieval');
    Map<Object?, Object?>? request;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      request = (call.arguments as Map).cast<Object?, Object?>();
      return {'thermal_models': 0.8};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final scores = await const MacOSSemanticKnowledgeScorer().score(
      'what are the thermal printer you have?',
      [
        {'id': 'thermal_models', 'issue': '热敏打印机型号清单'}
      ],
    );

    expect(request?['query'], contains('热敏打印机'));
    expect(request?['query'], contains('清单'));
    expect(scores['thermal_models'], 0.8);
  });

  test('semantic scorer maps English Android app compatibility to Chinese',
      () async {
    const channel =
        MethodChannel('com.grozziie.jdAutomation/semanticRetrieval');
    Map<Object?, Object?>? request;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      request = (call.arguments as Map).cast<Object?, Object?>();
      return {'app_support': 0.8};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await const MacOSSemanticKnowledgeScorer().score(
      'Do these printers support the Grozziie app on Android?',
      [
        {'id': 'app_support', 'issue': '速印通安卓手机兼容性'}
      ],
    );

    expect(request?['query'], contains('安卓'));
    expect(request?['query'], contains('速印通'));
    expect(request?['query'], contains('支持'));
  });

  test('extracts the requested product capabilities without inventing facts',
      () {
    expect(
      requestedProductCapabilities(
          'Do GZP510 and GZP820 support the Grozziie app on Android?'),
      {'android', 'mobile_app'},
    );
    expect(requestedProductCapabilities('What paper width does TP874 use?'),
        {'paper_width'});
  });

  test('English Android app query retrieves Chinese app guidance', () async {
    final knowledge = Directory('${root.path}/android_app_knowledge');
    final ragCards = Directory('${knowledge.path}/rag_cards');
    await ragCards.create(recursive: true);
    await File('${ragCards.path}/customer_service_rag_cards.jsonl').writeAsString(
        '{"id":"android_app","status":"active","keywords":["安卓","手机系统","速印通","兼容","支持"],"issue":"速印通安卓手机兼容性","reply_template":"按精确型号确认"}\n');

    final records = await LocalKnowledgeRetriever(knowledge,
            semanticScorer: _FixedSemanticScorer(const {}))
        .retrieve('Do GZP510 and GZP820 support the Grozziie app on Android?',
            limit: 3);

    expect(records.map((record) => record['id']), contains('android_app'));
  });

  test('retrieves the Android and iOS implication for confirmed app support',
      () async {
    final retriever = LocalKnowledgeRetriever(Directory(
        '${Directory.current.path}/格志中国市场客服完整知识库-2026-09-15-r21-consolidated'));

    final records = await retriever.retrieve(
      'If this printer supports the Grozziie app, does it work on Android and iOS?',
      limit: 8,
    );

    expect(
      records.map((record) => record['id']),
      contains('official_mobile_app_android_ios_implication'),
    );
    final rule = records.firstWhere((record) =>
        record['id'] == 'official_mobile_app_android_ios_implication');
    expect(rule['reply_template'].toString(), contains('Android'));
    expect(rule['reply_template'].toString(), contains('iOS'));
  });

  test('reloads edited knowledge files without restarting the retriever',
      () async {
    final knowledge = Directory('${root.path}/live_knowledge');
    final ragCards = Directory('${knowledge.path}/rag_cards');
    await ragCards.create(recursive: true);
    final cardFile = File('${ragCards.path}/customer_service_rag_cards.jsonl');
    await cardFile.writeAsString(
        '{"id":"live_card","status":"active","keywords":["refreshmarker"],"reply_template":"old answer"}\n');
    final retriever = LocalKnowledgeRetriever(knowledge,
        semanticScorer: _FixedSemanticScorer(const {}));

    final first = await retriever.retrieve('refreshmarker', limit: 1);
    expect(first.single['reply_template'], 'old answer');

    await cardFile.writeAsString(
        '{"id":"live_card","status":"active","keywords":["refreshmarker"],"reply_template":"updated answer from raw text"}\n');
    final updated = await retriever.retrieve('refreshmarker', limit: 1);
    expect(updated.single['reply_template'], 'updated answer from raw text');

    await File('${knowledge.path}/new_kb.md')
        .writeAsString('# New section\n\nnewknowledgeuniquetoken');
    final added = await retriever.retrieve('newknowledgeuniquetoken', limit: 2);
    expect(added.any((record) => record['source_file'] == 'new_kb.md'), isTrue);
  });

  test('retrieves M880D previous-year date instructions', () async {
    final projectRoot = Directory.current;
    final retriever = LocalKnowledgeRetriever(Directory(
        '${projectRoot.path}/格志中国市场客服完整知识库-2026-09-15-r21-consolidated'));
    final records = await retriever.retrieve(
      'Can I set the M880D system date to last year, 2025?',
      limit: 5,
    );

    expect(
      records
          .any((record) => record['id'] == 'attendance_manual_date_time_setup'),
      isTrue,
    );
  });

  test('retrieves TP874 Mac driver and connection evidence without a link',
      () async {
    final retriever = LocalKnowledgeRetriever(Directory(
        '${Directory.current.path}/格志中国市场客服完整知识库-2026-09-15-r21-consolidated'));
    final raw = await retriever.retrieve(
      'TP874 macOS where can I get driver then how to connect?',
      limit: 35,
    );
    final records = filterKnowledgeForLatestProduct(
      raw,
      'TP874 macOS driver download connect thermal printer',
      categoryConstraints: const ProductRetrievalConstraints(
        requiredCategories: {'thermal_label_printer'},
      ),
    );
    final evidence = records
        .map((record) => [
              record['id'],
              record['title'],
              record['issue'],
              record['reply_template'],
              record['content'],
            ].join(' '))
        .join('\n');

    expect(hasTechnicalSupportIntent('where can I get driver?'), isTrue);
    expect(evidence, contains('TP874'));
    expect(evidence, anyOf(contains('download.htm'), contains('下载')));
    expect(evidence, contains('USB'));
  });

  test('exact-model filtering retains generic same-category support cards', () {
    final records = filterKnowledgeForLatestProduct(
      const [
        {
          'id': 'generic_download',
          'models': ['all'],
          'product_line': 'all_printers',
          'issue': 'official driver download',
        },
        {
          'id': 'thermal_setup',
          'models': ['热敏打印机'],
          'product_line': 'thermal_printer',
          'issue': 'USB driver setup',
        },
        {
          'id': 'wrong_exact_model',
          'models': ['TD630'],
          'product_line': 'dot_matrix_printer',
          'issue': 'driver setup',
        },
      ],
      'TP874 thermal printer driver',
      categoryConstraints: const ProductRetrievalConstraints(
        requiredCategories: {'thermal_label_printer'},
      ),
    );

    expect(records.map((record) => record['id']),
        ['generic_download', 'thermal_setup']);
  });

  test('retrieves verified media paths linked by selected cards', () async {
    final projectRoot = Directory.current;
    final retriever = LocalKnowledgeRetriever(Directory(
        '${projectRoot.path}/格志中国市场客服完整知识库-2026-09-15-r21-consolidated'));
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
    final retriever = LocalKnowledgeRetriever(Directory(
        '${projectRoot.path}/格志中国市场客服完整知识库-2026-09-15-r21-consolidated'));
    final records = await retriever.retrieve(
        'M880 paper-card attendance machine\n'
        'Let us continue with M880D\n'
        'send the battery comparison photo',
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

  test('recognizes only explicit requests to describe customer media', () {
    expect(asksForMediaDescription('What does this image show?'), isTrue);
    expect(asksForMediaDescription('Please describe this video.'), isTrue);
    expect(asksForMediaDescription('这张图片里有什么？'), isTrue);
    expect(asksForMediaDescription('这是什么？'), isTrue);
    expect(asksForMediaDescription('Check this and help me fix it.'), isFalse);
    expect(
        asksForMediaDescription('The printer is not feeding paper.'), isFalse);
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
    expect(guarded.reply, contains('产品图片'));
    expect(guarded.reply, isNot(contains('senior customer service agent')));
    expect(guarded.reply, isNot(contains('forwarded')));
    expect(draftHumanReviewReason(guarded),
        contains('Customer requested product photos'));
  });

  test('customer-facing guard removes internal identity and media reports', () {
    final generated = service.parseResponse('''{
      "reply":"As an AI assistant, my image analysis report says the printer is offline.",
      "decision":"draft",
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

    final guarded = service.enforceCustomerFacingPolicy(
      generated,
      'What do you see in the photo?',
    );

    expect(guarded.reply, contains('客服人员'));
    expect(guarded.reply.toLowerCase(), isNot(contains('ai')));
    expect(guarded.reply.toLowerCase(), isNot(contains('analysis')));
  });

  test('does not claim a colleague is arranged without a review ticket', () {
    final generated = service.parseResponse('''{
      "reply":"Understood. I've arranged for a human agent to assist you.",
      "decision":"draft",
      "confidence":0.8,
      "used_record_ids":[],
      "required_slots":[],
      "actions":[],
      "risk_level":"low",
      "risk_triggers":[],
      "auto_send_allowed":false,
      "model":"test",
      "attachments":[],
      "image_descriptions":[],
      "human_review_required":false,
      "reason":null
    }''');

    final guarded =
        service.enforceCustomerFacingPolicy(generated, 'Where is it?');

    expect(guarded.reply, contains('继续为您核对'));
    expect(guarded.reply.toLowerCase(), isNot(contains('human agent')));
    expect(draftRequiresHumanReview(guarded), isFalse);
  });

  test('customer-facing guard removes an unsolicited video inventory', () {
    final generated = service.parseResponse('''{
      "reply":"The video shows a desk, monitor, keyboard, cables, and a notebook. No JD product is visible.",
      "decision":"draft",
      "confidence":0.8,
      "used_record_ids":[],
      "required_slots":[],
      "actions":[],
      "risk_level":"low",
      "risk_triggers":[],
      "auto_send_allowed":false,
      "model":"ignored",
      "attachments":[],
      "image_descriptions":[{"path":"/data/frame.png","description":"A desk is visible."}],
      "human_review_required":false,
      "reason":null
    }''', approvedImagePaths: {'/data/frame.png'});

    final guarded =
        service.enforceCustomerFacingPolicy(generated, 'did you find it now?');

    expect(guarded.reply, contains('希望解决的具体问题'));
    expect(guarded.reply, isNot(contains('视频')));
    expect(guarded.reply.toLowerCase(), isNot(contains('desk')));
    expect(guarded.reply.toLowerCase(), isNot(contains('monitor')));
  });

  test('customer-facing guard keeps the action and removes image description',
      () {
    final generated = service.parseResponse('''{
      "reply":"图片显示的是一朵白色的花，没有看到M880UT或色带仓。请重新拍摄色带盒和打开的色带仓。",
      "decision":"ask_clarification",
      "confidence":0.9,
      "used_record_ids":[],
      "required_slots":[],
      "actions":[],
      "risk_level":"low",
      "risk_triggers":[],
      "auto_send_allowed":false,
      "model":"ignored",
      "attachments":[],
      "image_descriptions":[{"path":"/data/flower.png","description":"A white flower is visible."}],
      "human_review_required":false,
      "reason":null
    }''', approvedImagePaths: {'/data/flower.png'});

    final guarded = service.enforceCustomerFacingPolicy(
      generated,
      '[Customer sent an image; visible portion captured]',
    );

    expect(guarded.reply, contains('请重新拍摄色带盒'));
    expect(guarded.reply, isNot(contains('白色的花')));
    expect(guarded.reply, isNot(contains('图片显示')));
    expect(guarded.reply, isNot(contains('视频')));
  });

  test('customer-facing guard removes unrequested JD purchase pressure', () {
    final generated = service.parseResponse('''{
      "reply":"Great! Please make sure the JD purchase option includes power backup before placing your order.",
      "decision":"draft",
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

    final natural =
        service.enforceCustomerFacingPolicy(generated, 'looks good');
    final buying = service.enforceCustomerFacingPolicy(
        generated, 'Where can I buy this model?');

    expect(natural.reply.toLowerCase(), isNot(contains('jd purchase')));
    expect(natural.reply.toLowerCase(), isNot(contains('place your order')));
    expect(natural.reply, contains('符合您刚才提到的需求'));
    expect(buying.reply, contains('JD purchase option'));
  });
}

class _FixedSemanticScorer implements SemanticKnowledgeScorer {
  const _FixedSemanticScorer(this.scores);

  final Map<String, double> scores;

  @override
  Future<Map<String, double>> score(
          String query, List<Map<String, dynamic>> records) async =>
      scores;
}
