import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jd_automation/codex/holding_replies.dart';

void main() {
  test('holding replies vary but always use Chinese', () {
    expect(chineseHoldingReplies.toSet(), hasLength(20));
    final random = Random(7);
    for (var index = 0; index < 30; index++) {
      expect(
          chineseHoldingReplies,
          contains(chooseHoldingReply('What are the printer features?',
              random: random)));
      expect(chineseHoldingReplies,
          contains(chooseHoldingReply('这个型号有什么功能？', random: random)));
    }
  });
}
