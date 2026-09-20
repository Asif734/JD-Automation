import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/codex/holding_replies.dart';

void main() {
  test('holding replies vary and follow the customer language', () {
    expect(englishHoldingReplies.toSet(), hasLength(20));
    expect(chineseHoldingReplies.toSet(), hasLength(20));
    final random = Random(7);
    for (var index = 0; index < 30; index++) {
      expect(
          englishHoldingReplies,
          contains(chooseHoldingReply('What are the printer features?',
              random: random)));
      expect(chineseHoldingReplies,
          contains(chooseHoldingReply('这个型号有什么功能？', random: random)));
    }
  });
}
