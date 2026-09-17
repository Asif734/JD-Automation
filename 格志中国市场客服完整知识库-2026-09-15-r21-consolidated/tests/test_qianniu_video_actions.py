from __future__ import annotations

import unittest

from scripts.qianniu_fixed_window_bot import build_safe_reply, execute_reply_actions


class QianNiuVideoActionsTest(unittest.TestCase):
    def test_qianniu_always_resolves_tmall_video(self) -> None:
        result = build_safe_reply("考勤机时间不准怎么调", product_context="考勤机 M880")
        self.assertIn("cloud.video.taobao.com", result["reply"])
        self.assertTrue(result["actions"])

    def test_image_failure_stops_all_remaining_actions_and_logs(self) -> None:
        calls: list[tuple[str, str]] = []
        logs: list[dict] = []

        def send_image(path: str) -> bool:
            calls.append(("image", path))
            return False

        def send_text(value: str) -> bool:
            calls.append(("text", value))
            return True

        ok = execute_reply_actions(
            [
                {"type": "send_image", "path": "/tmp/a.png"},
                {"type": "send_text", "text": "第一张说明"},
                {"type": "send_image", "path": "/tmp/b.png"},
            ],
            send_image=send_image,
            send_text=send_text,
            log_event=logs.append,
        )
        self.assertFalse(ok)
        self.assertEqual([("image", "/tmp/a.png")], calls)
        self.assertEqual("media_send_failed", logs[0]["event"])

    def test_successful_actions_preserve_image_then_description_order(self) -> None:
        calls: list[tuple[str, str]] = []
        ok = execute_reply_actions(
            [
                {"type": "send_image", "path": "/tmp/a.png"},
                {"type": "send_text", "text": "截图说明"},
            ],
            send_image=lambda value: calls.append(("image", value)) or True,
            send_text=lambda value: calls.append(("text", value)) or True,
        )
        self.assertTrue(ok)
        self.assertEqual([("image", "/tmp/a.png"), ("text", "截图说明")], calls)


if __name__ == "__main__":
    unittest.main()
