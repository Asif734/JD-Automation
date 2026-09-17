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
    expect(draft.reply, contains('human support agent'));
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

  test('recognizes only explicit requests for a human agent', () {
    expect(explicitlyRequestsHumanAgent('Please connect me to a human agent.'),
        isTrue);
    expect(explicitlyRequestsHumanAgent('我要转人工客服'), isTrue);
    expect(explicitlyRequestsHumanAgent('macOs 26.6.2'), isFalse);
    expect(
        explicitlyRequestsHumanAgent('Does TP732 work with my Mac?'), isFalse);
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
  });

  test('loads the dedicated product recommendation catalog', () async {
    final projectRoot = Directory.current;
    final catalog = await loadProductRecommendationCatalog(
        Directory('${projectRoot.path}/格志中国市场客服完整知识库-2026-08-16'));

    expect(catalog, contains('knowledge_base: product_model_feature_catalog'));
    expect(catalog, contains('## 2. 快速选型结论'));
    expect(catalog, contains('TD630G'));
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
  });

  test('recognizes refund and video-guide review requests', () {
    expect(isRefundRequest('I need a refund'), isTrue);
    expect(isRefundRequest('我要退款'), isTrue);
    expect(isVideoGuideRequest('Please send the setup video guide'), isTrue);
    expect(isVideoGuideRequest('请发设置视频教程'), isTrue);
    expect(isVideoGuideRequest('I sent a fault video'), isFalse);
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
    expect(refund.reply, contains('refund request'));
    expect(draftHumanReviewReason(refund), contains('refund'));
    expect(draftRequiresHumanReview(video), isTrue);
    expect(video.reply, contains('video-guide request'));
  });

  test('forces human requests, dissatisfaction, and no-solution replies', () {
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

    final human = service.enforceHumanReviewPolicy(
        ordinary, 'Please connect me to a human agent');
    final dissatisfied =
        service.enforceHumanReviewPolicy(ordinary, 'This reply did not help');
    final unresolved =
        service.enforceHumanReviewPolicy(noSolution, 'My printer still fails');

    expect(draftRequiresHumanReview(human), isTrue);
    expect(draftHumanReviewReason(human), contains('explicitly requested'));
    expect(draftRequiresHumanReview(dissatisfied), isTrue);
    expect(draftHumanReviewReason(dissatisfied), contains('dissatisfied'));
    expect(draftRequiresHumanReview(unresolved), isTrue);
    expect(draftHumanReviewReason(unresolved), contains('reliable solution'));
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
    final retriever = LocalKnowledgeRetriever(
        Directory('${projectRoot.path}/格志中国市场客服完整知识库-2026-08-16'));
    final records = await retriever.retrieve('我要退款', limit: 3);
    expect(records, isNotEmpty);
    expect(records.first['id'], 'global_refund_return_high_risk');
    expect(records.first, isNot(contains('keywords')));
  });

  test('retrieves every Markdown file and both RAG JSONL stores', () async {
    final knowledge = Directory('${root.path}/knowledge');
    final ragCards = Directory('${knowledge.path}/rag_cards');
    await ragCards.create(recursive: true);
    await File('${ragCards.path}/customer_service_rag_cards.jsonl').writeAsString(
        '{"id":"card_zephyr","status":"active","issue":"zephyrcardtoken","reply_template":"card answer"}\n');
    await File('${ragCards.path}/source_chunks.jsonl').writeAsString(
        '{"id":"chunk_orbit","type":"source_chunk","source_file":"source.md","content":"orbitchunktoken"}\n');
    await File('${knowledge.path}/first.md')
        .writeAsString('# First\n\nzirconmarkdownone');
    final nestedMarkdownFile = File('${knowledge.path}/nested/second.md');
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
    expect(firstMarkdown.single['source_file'], 'first.md');
    expect(firstMarkdown.single['content'], contains('zirconmarkdownone'));
    expect(nestedMarkdown.single['source_file'], 'nested/second.md');
    expect(nestedMarkdown.single['content'], contains('quasarmarkdowntwo'));
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

  test('retrieves M880D previous-year date instructions', () async {
    final projectRoot = Directory.current;
    final retriever = LocalKnowledgeRetriever(
        Directory('${projectRoot.path}/格志中国市场客服完整知识库-2026-08-16'));
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
