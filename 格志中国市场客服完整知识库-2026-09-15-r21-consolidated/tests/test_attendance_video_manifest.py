from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "rag_cards/attendance_video_materials.json"


def count_urls(value: object) -> int:
    if isinstance(value, str):
        return 1
    if isinstance(value, dict):
        return sum(count_urls(item) for item in value.values())
    return 0


class AttendanceVideoManifestTest(unittest.TestCase):
    def manifest(self) -> dict:
        self.assertTrue(MANIFEST.is_file(), f"missing manifest: {MANIFEST}")
        return json.loads(MANIFEST.read_text(encoding="utf-8"))

    def test_manifest_has_fourteen_deduplicated_contents_and_all_platform_links(self) -> None:
        data = self.manifest()
        self.assertEqual("Attendance Machine", data["machine_type"])
        self.assertEqual(14, len(data["contents"]))
        self.assertEqual(14, len({item["content_id"] for item in data["contents"]}))
        self.assertEqual({"JD", "Tmall", "Pinduoduo"}, set(data["platforms"]))
        self.assertEqual(
            44,
            sum(count_urls(item["platform_urls"]) for item in data["contents"]),
        )

    def test_customer_explanation_style_preserves_focused_and_full_tutorial_rules(self) -> None:
        style = self.manifest()["customer_explanation_style"]
        self.assertEqual("image_text_stepwise", style["mode"])
        self.assertEqual(2, style["focused_question"]["max_screenshots"])
        self.assertTrue(style["focused_question"]["include_video_time_range"])
        self.assertTrue(
            style["full_tutorial"]["allowed_only_when_customer_explicitly_requests_complete_process"]
        )
        self.assertTrue(style["full_tutorial"]["send_nodes_in_chronological_order"])
        self.assertEqual(
            {
                "video_time_range", "which_key_to_press", "expected_screen_change",
                "what_to_do_next", "necessary_warning_or_model_difference",
            },
            set(style["each_step_must_include"]),
        )

    def test_capture_policy_derives_node_count_from_actual_video_actions(self) -> None:
        policy = self.manifest()["customer_explanation_style"]["knowledge_capture"]
        self.assertEqual("actual_video_operation_nodes", policy["node_count_basis"])
        self.assertFalse(policy["use_fixed_screenshot_count"])
        self.assertEqual(
            {
                "real_key_press_with_purpose",
                "screen_state_change",
                "field_navigation",
                "value_change",
                "confirmation_or_result",
            },
            set(policy["include_as_nodes"]),
        )
        self.assertEqual(
            {
                "title_card",
                "outro",
                "idle_hold",
                "duplicate_frame_without_state_change",
            },
            set(policy["exclude_as_nodes"]),
        )

    def test_shift_content_maps_three_pinduoduo_links_without_duplicate_knowledge(self) -> None:
        data = self.manifest()
        shift = next(
            item for item in data["contents"]
            if item["content_id"] == "attendance_set_shifts"
        )
        self.assertIsInstance(shift["platform_urls"]["JD"], str)
        self.assertIsInstance(shift["platform_urls"]["Tmall"], str)
        self.assertEqual(
            {"one_shift", "two_shifts", "three_shifts"},
            set(shift["platform_urls"]["Pinduoduo"]),
        )

    def test_shift_video_has_complete_ordered_manual_verified_operation_nodes(self) -> None:
        data = self.manifest()
        content = next(item for item in data["contents"] if item["content_id"] == "attendance_set_shifts")
        nodes = content.get("operation_nodes")
        self.assertTrue(nodes)
        self.assertEqual(
            [
                "enter_settings_for_one_shift", "enter_password_for_one_shift",
                "open_shift_count_group", "set_one_shift_count",
                "set_first_shift_start", "set_first_shift_end",
                "clear_second_shift_start", "clear_second_shift_end",
                "clear_third_shift_start", "clear_third_shift_end_and_save",
                "demonstrate_on_time_punch", "demonstrate_late_punch",
                "demonstrate_after_end_punch", "demonstrate_early_leave",
                "reenter_settings_for_three_shifts", "reenter_password_for_three_shifts",
                "reopen_shift_count_group", "set_three_shift_count",
                "confirm_first_shift_start", "confirm_first_shift_end",
                "set_second_shift_start", "set_second_shift_end",
                "set_third_shift_start", "set_third_shift_end_and_save",
            ],
            [node["node_id"] for node in nodes],
        )
        required = {
            "node_id", "title", "start_ms", "end_ms", "timestamp_label", "action",
            "screen_state", "triggers", "applicable_questions", "screenshot", "entry_keys",
            "operation_steps", "manual_reference", "manual_verdict", "manual_notes",
        }
        previous_end = -1
        for node in nodes:
            with self.subTest(node_id=node.get("node_id")):
                self.assertTrue(required.issubset(node))
                self.assertGreaterEqual(node["start_ms"], previous_end)
                self.assertLess(node["start_ms"], node["end_ms"])
                self.assertLessEqual(node["end_ms"], content["canonical_source"]["duration_ms"])
                self.assertRegex(node["timestamp_label"], r"^\d{2}:\d{2}–\d{2}:\d{2}$")
                self.assertIn("考勤机用户手册", node["manual_reference"])
                self.assertTrue(node["manual_verdict"])
                screenshot_path = ROOT / node["screenshot"]["path"]
                self.assertTrue(screenshot_path.is_file(), screenshot_path)
                self.assertGreater(screenshot_path.stat().st_size, 0)
                previous_end = node["end_ms"]

        all_node_ids = {node["node_id"] for node in nodes}
        for segment in content["segments"]:
            self.assertTrue(segment["operation_node_ids"])
            self.assertTrue(set(segment["operation_node_ids"]).issubset(all_node_ids))
        self.assertEqual("00:03–03:43", content["full_operation_range"])

    def test_intro_video_has_eighteen_ordered_manual_verified_operation_nodes(self) -> None:
        data = self.manifest()
        content = next(
            item for item in data["contents"]
            if item["content_id"] == "attendance_intro_buttons"
        )
        nodes = content.get("operation_nodes")
        self.assertTrue(nodes)
        self.assertEqual(
            [
                "increase_value", "decrease_value", "previous_next",
                "return_previous", "return_home", "confirm", "settings",
                "in_out_labels", "current_punch_cursor", "show_cursor",
                "current_time", "current_date", "weekday", "dc_power_icon",
                "battery_icon", "locate_backup_switch",
                "enable_backup_battery", "verify_battery_icon",
            ],
            [node["node_id"] for node in nodes],
        )
        required = {
            "node_id", "title", "start_ms", "end_ms", "timestamp_label",
            "action", "screen_state", "triggers", "applicable_questions",
            "entry_keys", "operation_steps", "manual_reference",
            "manual_verdict", "manual_notes", "screenshot",
        }
        previous_end = -1
        for node in nodes:
            with self.subTest(node_id=node.get("node_id")):
                self.assertTrue(required.issubset(node))
                self.assertGreaterEqual(node["start_ms"], previous_end)
                self.assertLess(node["start_ms"], node["end_ms"])
                self.assertRegex(node["timestamp_label"], r"^\d{2}:\d{2}–\d{2}:\d{2}$")
                self.assertIn("考勤机用户手册", node["manual_reference"])
                screenshot_path = ROOT / node["screenshot"]["path"]
                self.assertTrue(screenshot_path.is_file(), screenshot_path)
                self.assertGreater(screenshot_path.stat().st_size, 0)
                previous_end = node["end_ms"]

        battery_node_ids = {
            "battery_icon", "locate_backup_switch",
            "enable_backup_battery", "verify_battery_icon",
        }
        for node in nodes:
            if node["node_id"] in battery_node_ids:
                self.assertEqual(["M880D", "M880D-A"], node["supported_models"])
                self.assertTrue(node["requires_model_confirmation"])

        all_node_ids = {node["node_id"] for node in nodes}
        for segment in content["segments"]:
            self.assertTrue(segment["operation_node_ids"])
            self.assertTrue(set(segment["operation_node_ids"]).issubset(all_node_ids))
        self.assertEqual("00:05–01:11", content["full_operation_range"])

    def test_every_content_has_verified_source_and_customer_question_segments(self) -> None:
        data = self.manifest()
        for content in data["contents"]:
            with self.subTest(content_id=content["content_id"]):
                source = content["canonical_source"]
                self.assertGreater(source["duration_ms"], 0)
                self.assertRegex(source["sha256"], r"^[0-9a-f]{64}$")
                self.assertTrue(content["segments"])
                for segment in content["segments"]:
                    self.assertLess(segment["start_ms"], segment["end_ms"])
                    self.assertTrue(segment["triggers"])
                    self.assertTrue(segment["applicable_questions"])
                    self.assertTrue(segment["customer_reply"])
                    self.assertGreaterEqual(len(segment["screenshots"]), 1)
                    self.assertLessEqual(len(segment["screenshots"]), 2)
                    for screenshot in segment["screenshots"]:
                        self.assertTrue(screenshot["path"].endswith(".png"))
                        self.assertTrue(screenshot["description"])

    def test_date_video_has_complete_ordered_operation_nodes(self) -> None:
        data = self.manifest()
        content = next(item for item in data["contents"] if item["content_id"] == "attendance_modify_date")
        segment = next(item for item in content["segments"] if item["segment_id"] == "set_current_date")
        nodes = segment.get("operation_nodes")
        self.assertTrue(nodes)
        self.assertEqual(8, len(nodes))
        required = {
            "node_id", "title", "start_ms", "end_ms", "timestamp_label",
            "action", "screen_state", "triggers", "applicable_questions", "screenshot",
            "entry_keys", "operation_steps", "manual_reference", "manual_verdict", "manual_notes",
        }
        previous_end = -1
        for node in nodes:
            with self.subTest(node_id=node.get("node_id")):
                self.assertTrue(required.issubset(node))
                self.assertGreaterEqual(node["start_ms"], previous_end)
                self.assertLess(node["start_ms"], node["end_ms"])
                self.assertLessEqual(node["end_ms"], content["canonical_source"]["duration_ms"])
                self.assertRegex(node["timestamp_label"], r"^\d{2}:\d{2}–\d{2}:\d{2}$")
                self.assertTrue(node["action"])
                self.assertTrue(node["screen_state"])
                self.assertTrue(node["triggers"])
                self.assertTrue(node["applicable_questions"])
                self.assertTrue(node["entry_keys"])
                self.assertTrue(node["operation_steps"])
                self.assertIn("考勤机用户手册", node["manual_reference"])
                self.assertTrue(node["manual_verdict"])
                self.assertTrue(node["manual_notes"])
                screenshot = node["screenshot"]
                screenshot_path = ROOT / screenshot["path"]
                self.assertTrue(screenshot_path.is_file(), screenshot_path)
                self.assertGreater(screenshot_path.stat().st_size, 0)
                self.assertEqual(".png", screenshot_path.suffix.lower())
                self.assertTrue(screenshot["description"])
                previous_end = node["end_ms"]

        password_node = next(node for node in nodes if node["node_id"] == "enter_settings_password")
        self.assertNotIn("数字键", password_node["action"])
        self.assertIn("下一键", password_node["entry_keys"])
        self.assertIn("0000", password_node["manual_notes"])

    def test_time_video_has_complete_manual_verified_operation_nodes(self) -> None:
        data = self.manifest()
        content = next(item for item in data["contents"] if item["content_id"] == "attendance_set_time")
        segment = next(item for item in content["segments"] if item["segment_id"] == "set_current_time")
        nodes = segment.get("operation_nodes")
        self.assertTrue(nodes)
        self.assertEqual(
            [
                "enter_settings", "enter_settings_password", "confirm_password_open_group_00",
                "confirm_open_group_01", "identify_time_fields", "move_between_time_digits",
                "adjust_minute_value", "confirm_time_settings",
            ],
            [node["node_id"] for node in nodes],
        )
        required = {
            "node_id", "title", "start_ms", "end_ms", "timestamp_label", "action",
            "screen_state", "triggers", "applicable_questions", "screenshot", "entry_keys",
            "operation_steps", "manual_reference", "manual_verdict", "manual_notes",
        }
        previous_end = -1
        for node in nodes:
            with self.subTest(node_id=node.get("node_id")):
                self.assertTrue(required.issubset(node))
                self.assertGreaterEqual(node["start_ms"], previous_end)
                self.assertLess(node["start_ms"], node["end_ms"])
                self.assertLessEqual(node["end_ms"], content["canonical_source"]["duration_ms"])
                screenshot_path = ROOT / node["screenshot"]["path"]
                self.assertTrue(screenshot_path.is_file(), screenshot_path)
                self.assertGreater(screenshot_path.stat().st_size, 0)
                self.assertIn("考勤机用户手册", node["manual_reference"])
                previous_end = node["end_ms"]
        minute_node = next(node for node in nodes if node["node_id"] == "adjust_minute_value")
        self.assertIn("07:30", minute_node["manual_notes"])
        self.assertIn("小时", minute_node["manual_notes"])

    def test_ribbon_video_has_ten_ordered_manual_verified_operation_nodes(self) -> None:
        data = self.manifest()
        content = next(
            item for item in data["contents"]
            if item["content_id"] == "attendance_replace_ribbon"
        )
        nodes = content.get("operation_nodes")
        self.assertEqual(
            [
                "open_transparent_cover", "center_ribbon_cartridge",
                "remove_old_ribbon_cartridge", "locate_ribbon_wheel",
                "advance_ribbon_with_wheel", "identify_printhead_steel_gap",
                "insert_ribbon_into_gap", "seat_ribbon_cartridge",
                "tighten_ribbon_after_install", "verify_ribbon_installation",
            ],
            [node["node_id"] for node in nodes],
        )
        required = {
            "node_id", "title", "display_title", "start_ms", "end_ms",
            "timestamp_label", "action", "screen_state", "triggers",
            "applicable_questions", "entry_keys", "operation_steps",
            "manual_reference", "manual_verdict", "manual_notes", "screenshot",
        }
        previous_end = -1
        for index, node in enumerate(nodes, start=1):
            with self.subTest(node_id=node.get("node_id")):
                self.assertTrue(required.issubset(node))
                self.assertGreaterEqual(node["start_ms"], previous_end)
                self.assertLess(node["start_ms"], node["end_ms"])
                self.assertEqual("无需按键。", node["entry_keys"])
                self.assertIn("考勤机用户手册", node["manual_reference"])
                self.assertRegex(
                    node["display_title"],
                    rf"^{index}\. .+（\d{{2}}:\d{{2}}）$",
                )
                screenshot_path = ROOT / node["screenshot"]["path"]
                self.assertTrue(screenshot_path.is_file(), screenshot_path)
                self.assertGreater(screenshot_path.stat().st_size, 0)
                previous_end = node["end_ms"]

        segment = content["segments"][0]
        self.assertEqual(
            [node["node_id"] for node in nodes],
            segment["operation_node_ids"],
        )
        self.assertEqual("00:11–01:07", content["full_operation_range"])
        self.assertEqual("00:11–01:07", segment["full_operation_range"])
        self.assertNotIn("合上上盖", segment["customer_reply"])

    def test_settings_card_video_has_thirteen_ordered_manual_verified_nodes(self) -> None:
        data = self.manifest()
        content = next(
            item for item in data["contents"]
            if item["content_id"] == "attendance_settings_card"
        )
        nodes = content.get("operation_nodes")
        self.assertEqual(
            [
                "enter_ff_settings", "enter_default_password",
                "confirm_enter_group_00", "identify_group_number",
                "cycle_group_number", "introduce_half_month_cards",
                "identify_days_01_15", "identify_days_16_31",
                "locate_card_identification_mark", "identify_three_column_groups",
                "identify_first_shift_columns", "identify_second_shift_columns",
                "identify_overtime_columns",
            ],
            [node["node_id"] for node in nodes],
        )
        required = {
            "node_id", "title", "display_title", "start_ms", "end_ms",
            "timestamp_label", "action", "screen_state", "triggers",
            "applicable_questions", "entry_keys", "operation_steps",
            "manual_reference", "manual_verdict", "manual_notes", "screenshot",
        }
        previous_end = -1
        for index, node in enumerate(nodes, start=1):
            with self.subTest(node_id=node.get("node_id")):
                self.assertTrue(required.issubset(node))
                self.assertGreaterEqual(node["start_ms"], previous_end)
                self.assertLess(node["start_ms"], node["end_ms"])
                self.assertRegex(
                    node["display_title"],
                    rf"^{index}\. .+（\d{{2}}:\d{{2}}）$",
                )
                self.assertIn("考勤机用户手册", node["manual_reference"])
                screenshot_path = ROOT / node["screenshot"]["path"]
                self.assertTrue(screenshot_path.is_file(), screenshot_path)
                self.assertGreater(screenshot_path.stat().st_size, 0)
                previous_end = node["end_ms"]

        all_ids = {node["node_id"] for node in nodes}
        for segment in content["segments"]:
            self.assertTrue(segment["operation_node_ids"])
            self.assertTrue(set(segment["operation_node_ids"]).issubset(all_ids))
        overtime = nodes[-1]
        self.assertIn("视频字幕称第三班次", overtime["manual_notes"])
        self.assertIn("加班栏", overtime["operation_steps"])
        self.assertEqual("00:02–00:59", content["full_operation_range"])

    def test_dual_color_video_has_confirmed_nodes_and_preserves_unverified_00_warning(self) -> None:
        data = self.manifest()
        content = next(
            item for item in data["contents"]
            if item["content_id"] == "attendance_dual_color"
        )
        nodes = content.get("operation_nodes")
        self.assertEqual(
            [
                "introduce_black_red_printing", "explain_black_on_time",
                "explain_red_exception", "complete_groups_before_color",
                "enter_ff_settings", "enter_default_password",
                "confirm_enter_group_00", "review_groups_01_15",
                "return_to_group_02", "set_group_02_to_01",
                "confirm_01_dual_color", "explain_00_black_only_unverified",
                "confirm_remaining_groups_and_exit",
            ],
            [node["node_id"] for node in nodes],
        )
        required = {
            "node_id", "title", "display_title", "start_ms", "end_ms",
            "timestamp_label", "action", "screen_state", "triggers",
            "applicable_questions", "entry_keys", "operation_steps",
            "manual_reference", "manual_verdict", "manual_notes", "screenshot",
        }
        previous_end = -1
        for index, node in enumerate(nodes, start=1):
            with self.subTest(node_id=node.get("node_id")):
                self.assertTrue(required.issubset(node))
                self.assertGreaterEqual(node["start_ms"], previous_end)
                self.assertLess(node["start_ms"], node["end_ms"])
                self.assertRegex(node["display_title"], rf"^{index}\. .+（\d{{2}}:\d{{2}}）$")
                self.assertIn("考勤机用户手册", node["manual_reference"])
                screenshot_path = ROOT / node["screenshot"]["path"]
                self.assertTrue(screenshot_path.is_file(), screenshot_path)
                self.assertGreater(screenshot_path.stat().st_size, 0)
                previous_end = node["end_ms"]

        black_only = next(
            node for node in nodes
            if node["node_id"] == "explain_00_black_only_unverified"
        )
        self.assertIn("没有稳定显示完整 00", black_only["manual_notes"])
        self.assertIn("不能", black_only["operation_steps"])
        self.assertEqual("00:02–01:00", content["full_operation_range"])
        self.assertEqual(250, content["canonical_source"]["sampling_interval_ms"])
        self.assertIn("all 1597 decoded frames", content["canonical_source"]["inspection"])

        all_ids = {node["node_id"] for node in nodes}
        for segment in content["segments"]:
            self.assertTrue(segment["operation_node_ids"])
            self.assertTrue(set(segment["operation_node_ids"]).issubset(all_ids))
            self.assertLessEqual(len(segment["screenshots"]), 2)
            self.assertIn("customer_time_wording", segment)

        serialized = json.dumps(content, ensure_ascii=False)
        self.assertNotIn("enable_dual_color_1_14000ms.png", serialized)
        self.assertNotIn("dual_color_card_result_2_55000ms.png", serialized)
        self.assertEqual(3, len(set(content["platform_urls"].values())))

    def test_reset_password_video_has_confirmed_nodes_and_safety_limits(self) -> None:
        data = self.manifest()
        content = next(
            item for item in data["contents"]
            if item["content_id"] == "attendance_reset_password"
        )
        nodes = content.get("operation_nodes")
        self.assertEqual(
            [
                "hold_settings_until_hh", "hold_next_until_music",
                "wait_for_music_to_finish", "enter_default_password_after_reset",
                "confirm_default_and_enter_f1", "enter_new_password_in_f1",
                "confirm_f1_and_enter_f2", "repeat_new_password_in_f2",
                "confirm_save_and_return_home",
            ],
            [node["node_id"] for node in nodes],
        )
        required = {
            "node_id", "title", "display_title", "start_ms", "end_ms",
            "timestamp_label", "action", "screen_state", "triggers",
            "applicable_questions", "entry_keys", "operation_steps",
            "manual_reference", "manual_verdict", "manual_notes", "screenshot",
        }
        previous_end = -1
        for index, node in enumerate(nodes, start=1):
            with self.subTest(node_id=node.get("node_id")):
                self.assertTrue(required.issubset(node))
                self.assertGreaterEqual(node["start_ms"], previous_end)
                self.assertLess(node["start_ms"], node["end_ms"])
                self.assertRegex(node["display_title"], rf"^{index}\. .+（\d{{2}}:\d{{2}}）$")
                screenshot_path = ROOT / node["screenshot"]["path"]
                self.assertTrue(screenshot_path.is_file(), screenshot_path)
                self.assertGreater(screenshot_path.stat().st_size, 0)
                previous_end = node["end_ms"]

        first = nodes[0]
        self.assertIn("没有稳定拍到 FF", first["manual_notes"])
        self.assertIn("继续长按", first["operation_steps"])
        f1 = next(node for node in nodes if node["node_id"] == "enter_new_password_in_f1")
        self.assertIn("示例", f1["manual_notes"])
        save = nodes[-1]
        self.assertIn("不能承诺", save["manual_notes"])
        self.assertEqual("00:03–01:22", content["full_operation_range"])
        self.assertEqual(250, content["canonical_source"]["sampling_interval_ms"])
        self.assertIn("all 2084 decoded frames", content["canonical_source"]["inspection"])

        all_ids = {node["node_id"] for node in nodes}
        for segment in content["segments"]:
            self.assertTrue(segment["operation_node_ids"])
            self.assertTrue(set(segment["operation_node_ids"]).issubset(all_ids))
            self.assertLessEqual(len(segment["screenshots"]), 2)
            self.assertIn("customer_time_wording", segment)
        self.assertEqual(3, len(set(content["platform_urls"].values())))

    def test_remaining_attendance_videos_have_frame_verified_nodes(self) -> None:
        data = self.manifest()
        expected = {
            "attendance_punch_position": (8, "00:03–00:38"),
            "attendance_manual_punch": (13, "00:03–00:49"),
            "attendance_test_print": (6, "00:02–00:37"),
            "attendance_ring": (6, "00:02–00:22"),
            "attendance_modify_password": (7, "00:03–00:32"),
        }
        by_id = {item["content_id"]: item for item in data["contents"]}
        for content_id, (node_count, full_range) in expected.items():
            with self.subTest(content_id=content_id):
                content = by_id[content_id]
                self.assertEqual(node_count, len(content.get("operation_nodes", [])))
                self.assertEqual(full_range, content["full_operation_range"])
                self.assertEqual(250, content["canonical_source"]["sampling_interval_ms"])
                self.assertIn("decoded frames inspected", content["canonical_source"]["inspection"])
                self.assertEqual(3, len(set(content["platform_urls"].values())))
                all_ids = {node["node_id"] for node in content["operation_nodes"]}
                for node in content["operation_nodes"]:
                    self.assertTrue((ROOT / node["screenshot"]["path"]).is_file())
                    self.assertIn("考勤机用户手册", node["manual_reference"])
                for segment in content["segments"]:
                    self.assertTrue(set(segment["operation_node_ids"]).issubset(all_ids))
                    self.assertLessEqual(len(segment["screenshots"]), 2)
                    self.assertIn("customer_time_wording", segment)

        punch = by_id["attendance_punch_position"]
        self.assertIn("没有演示插卡试打", punch["operation_nodes"][-1]["manual_notes"])
        manual = by_id["attendance_manual_punch"]
        self.assertIn("黑色", manual["operation_nodes"][-1]["manual_notes"])
        test_print = by_id["attendance_test_print"]
        self.assertIn("自动", test_print["operation_nodes"][-1]["screen_state"])

    def test_group_02_cross_tutorial_conflict_is_explicitly_registered(self) -> None:
        data = self.manifest()
        conflicts = data.get("cross_tutorial_conflicts", [])
        conflict = next(item for item in conflicts if item["conflict_id"] == "group_02_overloaded_meaning")
        self.assertEqual("user_confirmed_guard", conflict["status"])
        self.assertEqual("2026-08-09", conflict["confirmed_by_user_on"])
        self.assertEqual(
            {"attendance_set_shifts", "attendance_manual_punch", "attendance_dual_color"},
            set(conflict["content_ids"]),
        )
        self.assertIn("two_or_three_shifts", conflict["automation_policy"]["clarify_or_handoff_if"])
        self.assertIn("any_group_02_color_value_change", conflict["automation_policy"]["clarify_or_handoff_if"])
        self.assertIn("do_not_send_dual_color_01", conflict["automation_policy"]["prohibited_actions"])

    def test_all_attendance_nodes_and_segments_have_consistent_evidence_metadata(self) -> None:
        data = self.manifest()
        for content in data["contents"]:
            with self.subTest(content_id=content["content_id"]):
                self.assertEqual(250, content["canonical_source"]["sampling_interval_ms"])
                self.assertIn("decoded frames inspected", content["canonical_source"]["inspection"])
                nodes = content.get("operation_nodes") or [
                    node
                    for segment in content["segments"]
                    for node in segment.get("operation_nodes", [])
                ]
                for node in nodes:
                    timestamp = node["screenshot"]["timestamp_ms"]
                    self.assertLessEqual(node["start_ms"], timestamp, node["node_id"])
                    self.assertLessEqual(timestamp, node["end_ms"], node["node_id"])
                for segment in content["segments"]:
                    self.assertEqual(
                        "本段内容从视频 {start} 开始（对应操作范围 {range}）",
                        segment.get("customer_time_wording"),
                    )


if __name__ == "__main__":
    unittest.main()
