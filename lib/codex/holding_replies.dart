import 'dart:math';

const englishHoldingReplies = <String>[
  'One moment, please. We are checking your question.',
  'Thanks for waiting. We are working on your answer.',
  'Please hold on a moment while we check this.',
  'We are looking into this for you. Thanks for your patience.',
  'Please give us a moment to review the details.',
  'Thanks for your patience. We are still checking.',
  'One moment while we verify the information for you.',
  'We are working through the details of your question.',
  'Please bear with us while we prepare your answer.',
  'Thanks for waiting. We are reviewing your request.',
];

const chineseHoldingReplies = <String>[
  '请稍等片刻，我们正在核对您的问题。',
  '感谢您的耐心等待，我们正在为您查询。',
  '请稍候，我们正在确认相关信息。',
  '我们正在查看您的问题，请稍等一下。',
  '请给我们一点时间核对详情。',
  '感谢您的等待，我们还在核实中。',
  '请稍等，我们正在整理答复。',
  '我们正在进一步确认，请您稍候。',
  '请耐心等待片刻，我们正在处理您的问题。',
  '感谢您的耐心，我们正在查看具体情况。',
];

String chooseHoldingReply(String latestCustomerText, {Random? random}) {
  final replies = RegExp(r'[\u3400-\u9fff]').hasMatch(latestCustomerText)
      ? chineseHoldingReplies
      : englishHoldingReplies;
  return replies[(random ?? Random()).nextInt(replies.length)];
}
