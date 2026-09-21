import 'dart:math';

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
  '请稍等一下，我们正在为您确认。',
  '我们正在核对详情，请稍候。',
  '请稍等片刻，我们正在核实。',
  '感谢等待，我们正在确认准确答复。',
  '我们正在仔细查看，请您稍候。',
  '请稍候，我们正在核对信息。',
  '我们还在处理您的问题，请稍等。',
  '请给我们一点时间确认详情。',
  '感谢您的等待，我们正在查询。',
  '我们正在核实，很快回复您。',
];

String chooseHoldingReply(String latestCustomerText, {Random? random}) {
  return chineseHoldingReplies[
      (random ?? Random()).nextInt(chineseHoldingReplies.length)];
}
