from __future__ import annotations

import unittest

from app import build_reply


class AppVideoReplyTest(unittest.TestCase):
    def test_build_reply_returns_one_platform_video_card(self) -> None:
        result = build_reply("考勤机日期不对怎么改", platform="JD")
        self.assertEqual("video_material_card", result["matches"][0]["type"])
        self.assertIn("300hu.com", result["reply"])
        self.assertIn("本段内容从视频 00:02 开始", result["reply"])
        self.assertIn("对应操作范围 00:02–00:31", result["reply"])
        self.assertEqual("00:02–00:31", result["time_cue"])
        self.assertEqual(4, len(result["actions"]))
        self.assertEqual(["send_image", "send_text", "send_image", "send_text"], [a["type"] for a in result["actions"]])

    def test_missing_platform_is_a_safe_text_only_clarification(self) -> None:
        result = build_reply("考勤机日期不对怎么改", platform=None)
        self.assertFalse(result["auto_reply_allowed"])
        self.assertEqual([], result["actions"])
        self.assertIn("平台", result["reply"])
        self.assertNotIn("http", result["reply"])

    def test_ambiguous_attendance_request_asks_which_topic(self) -> None:
        result = build_reply("考勤机不会用", platform="Tmall")
        self.assertEqual([], result["actions"])
        self.assertIn("时间", result["reply"])
        self.assertIn("班次", result["reply"])


if __name__ == "__main__":
    unittest.main()
