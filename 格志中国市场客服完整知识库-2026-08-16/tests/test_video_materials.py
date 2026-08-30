from __future__ import annotations

import unittest

from video_materials import PlatformRequiredError, match_video_material


class VideoMaterialsTest(unittest.TestCase):
    def test_group_02_value_01_meaning_question_is_clarified_without_media(self) -> None:
        result = match_video_material("第02组01是什么意思？", platform="Tmall")
        assert result is not None
        self.assertEqual("clarification", result["type"])
        self.assertTrue(result["needs_clarification"])
        self.assertIsNone(result["video_url"])
        self.assertEqual([], result["screenshots"])

    def test_group_02_color_change_requests_always_clarify_without_media(self) -> None:
        questions = [
            "我两班，只想打印黑色",
            "怎么只打印黑色",
            "怎么开启双色打印",
            "怎样关闭红色打印",
        ]
        for question in questions:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual("clarification", result["type"])
                self.assertTrue(result["needs_clarification"])
                self.assertIsNone(result["video_url"])
                self.assertEqual([], result["screenshots"])
                self.assertEqual([], result["actions"])

    def test_changed_password_uses_current_password_not_default_0000(self) -> None:
        result = match_video_material("我修改过密码，还能输入0000吗？", platform="Tmall")
        assert result is not None
        self.assertEqual("text_answer", result["type"])
        self.assertIn("当前密码", result["reply"])
        self.assertIn("不能继续使用默认的 0000", result["reply"])
        self.assertIsNone(result["video_url"])
        self.assertEqual([], result["screenshots"])
        self.assertEqual([], result["actions"])

    def test_settings_card_questions_select_relevant_nodes_and_manual_term(self) -> None:
        cases = [
            ("上半月纸卡应该看哪一面", "identify_days_01_15", "00:33–00:36"),
            ("下半月16到31日用纸卡哪一面", "identify_days_16_31", "00:36–00:41"),
            ("纸卡底部识别点在哪里", "locate_card_identification_mark", "00:41–00:47"),
            ("第二班次打卡在哪两列", "identify_second_shift_columns", "00:53–00:55"),
            ("加班打卡应该落在哪一栏", "identify_overtime_columns", "00:55–00:59"),
        ]
        for question, expected_node, expected_time in cases:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual("attendance_settings_card", result["content_id"])
                self.assertEqual(
                    [expected_node],
                    [node["node_id"] for node in result["selected_nodes"]],
                )
                self.assertEqual(expected_time, result["time_cue"])
                self.assertEqual(1, len(result["screenshots"]))
                self.assertIn("491049460842.mp4", result["video_url"])

        overtime = match_video_material("Over Time栏是什么意思", platform="JD")
        assert overtime is not None
        self.assertIn("加班", overtime["selected_nodes"][0]["manual_notes"])
        self.assertNotIn("普通第三班次栏", overtime["reply"])

    def test_ribbon_questions_select_only_relevant_node_and_platform_link(self) -> None:
        gap = match_video_material(
            "色带应该装在打印头什么位置",
            platform="Tmall",
        )
        assert gap is not None
        self.assertEqual("attendance_replace_ribbon", gap["content_id"])
        self.assertEqual(
            ["identify_printhead_steel_gap"],
            [node["node_id"] for node in gap["selected_nodes"]],
        )
        self.assertEqual("00:46–00:51", gap["time_cue"])
        self.assertIn("491106253912.mp4", gap["video_url"])
        self.assertEqual(1, len(gap["screenshots"]))

        loose = match_video_material(
            "色带装好以后太松了怎么办",
            platform="JD",
        )
        assert loose is not None
        self.assertEqual(
            ["tighten_ribbon_after_install"],
            [node["node_id"] for node in loose["selected_nodes"]],
        )
        self.assertEqual("01:01–01:04", loose["time_cue"])
        self.assertIn(
            "6f64a1d65b3a4004862da086df5d1296.mp4",
            loose["video_url"],
        )
        self.assertEqual(1, len(loose["screenshots"]))

    def test_tmall_time_question_returns_one_card_and_only_tmall_link(self) -> None:
        result = match_video_material("考勤机时间不准，怎么调？", platform="Tmall")
        self.assertIsNotNone(result)
        assert result is not None
        self.assertEqual("attendance_set_time", result["content_id"])
        self.assertEqual("set_current_time", result["segment_id"])
        self.assertEqual("Tmall", result["platform"])
        self.assertIn("cloud.video.taobao.com", result["video_url"])
        self.assertNotIn("300hu.com", result["video_url"])
        self.assertNotIn("pddpic.com", result["video_url"])
        self.assertIn(result["video_url"], result["reply"])
        self.assertLessEqual(len(result["screenshots"]), 2)

    def test_qianniu_channel_alias_is_forced_to_tmall(self) -> None:
        result = match_video_material("色带怎么更换？", platform="QianNiu")
        assert result is not None
        self.assertEqual("Tmall", result["platform"])
        self.assertIn("cloud.video.taobao.com", result["video_url"])

    def test_pinduoduo_two_shift_question_uses_two_shift_link(self) -> None:
        result = match_video_material("一天两个班次怎么设置？", platform="Pinduoduo")
        assert result is not None
        self.assertEqual("two_shifts", result["segment_id"])
        self.assertEqual(
            "https://video5.pddpic.com/i1/2024-03-05/7e37990d089dae49b35cb9c20752a8bd.mp4",
            result["video_url"],
        )
        self.assertIsNone(result["time_cue"])
        self.assertNotIn("请看视频", result["reply"])

    def test_shift_count_is_a_hard_constraint_for_one_two_and_three(self) -> None:
        cases = [
            ("一天1个班次怎么设置", "one_shift"),
            ("一天两个班次怎么设置", "two_shifts"),
            ("一天3个班次怎么设置", "three_shifts"),
        ]
        for question, expected in cases:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Pinduoduo")
                assert result is not None
                self.assertEqual(expected, result["segment_id"])

    def test_shift_questions_select_the_focused_operation_nodes_and_exact_time_cues(self) -> None:
        cases = [
            ("第一班上班时间怎么设置？", ["set_first_shift_start"], "00:29–00:42"),
            ("第一班下班时间怎么设置？", ["set_first_shift_end"], "00:42–00:56"),
            ("第二班开始时间在哪里设置？", ["set_second_shift_start"], "03:09–03:18"),
            ("第二班结束时间怎么设置？", ["set_second_shift_end"], "03:18–03:27"),
            ("第三班开始时间怎么设置？", ["set_third_shift_start"], "03:27–03:34"),
            ("第三班结束时间怎么设置？", ["set_third_shift_end_and_save"], "03:34–03:43"),
            ("为什么迟到打卡会打印红色？", ["demonstrate_late_punch"], "02:04–02:16"),
            ("为什么早退打卡会打印红色？", ["demonstrate_early_leave"], "02:27–02:37"),
        ]
        for question, expected_nodes, expected_range in cases:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual("attendance_set_shifts", result["content_id"])
                self.assertEqual(expected_nodes, [node["node_id"] for node in result["selected_nodes"]])
                self.assertEqual(expected_range, result["time_cue"])
                expected_start = expected_range.split("–", 1)[0]
                self.assertIn(f"本段内容从视频 {expected_start} 开始", result["reply"])
                self.assertIn(f"对应操作范围 {expected_range}", result["reply"])
                self.assertGreaterEqual(len(result["screenshots"]), 1)
                self.assertLessEqual(len(result["screenshots"]), 2)

    def test_generic_shift_count_questions_return_only_the_relevant_schedule_pair(self) -> None:
        cases = [
            ("一天一个班次怎么设置？", "one_shift", ["set_first_shift_start", "set_first_shift_end"]),
            ("一天两个班次怎么设置？", "two_shifts", ["set_second_shift_start", "set_second_shift_end"]),
            ("一天三个班次怎么设置？", "three_shifts", ["set_third_shift_start", "set_third_shift_end_and_save"]),
        ]
        for question, segment_id, node_ids in cases:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual(segment_id, result["segment_id"])
                self.assertEqual(node_ids, [node["node_id"] for node in result["selected_nodes"]])
                self.assertEqual(2, len(result["screenshots"]))

    def test_intro_questions_select_only_the_focused_node_and_start_time(self) -> None:
        cases = [
            ("5号键长按怎么返回主界面？", "return_home", "00:18–00:22"),
            ("屏幕右上角插头图标是什么意思？", "dc_power_icon", "00:50–00:54"),
            ("M880D备用电池开关在哪里？", "locate_backup_switch", "00:57–01:02"),
        ]
        for question, node_id, expected_range in cases:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual("attendance_intro_buttons", result["content_id"])
                self.assertEqual([node_id], [node["node_id"] for node in result["selected_nodes"]])
                self.assertEqual(expected_range, result["time_cue"])
                start = expected_range.split("–", 1)[0]
                self.assertIn(f"本段内容从视频 {start} 开始", result["reply"])
                self.assertEqual(1, len(result["screenshots"]))

    def test_battery_instructions_require_model_confirmation_before_sending_media(self) -> None:
        result = match_video_material("备用电池开关在哪里？", platform="Tmall")
        assert result is not None
        self.assertEqual("clarification", result["type"])
        self.assertTrue(result["needs_clarification"])
        self.assertFalse(result["auto_reply_allowed"])
        self.assertIsNone(result["video_url"])
        self.assertEqual([], result["screenshots"])
        self.assertIn("M880D", result["reply"])

    def test_missing_platform_never_returns_a_video_link(self) -> None:
        with self.assertRaises(PlatformRequiredError):
            match_video_material("考勤机时间怎么调？", platform=None)

    def test_ambiguous_attendance_question_returns_no_material_card(self) -> None:
        self.assertIsNone(match_video_material("这个考勤机不会用", platform="JD"))

    def test_unrelated_or_high_risk_question_returns_no_material_card(self) -> None:
        self.assertIsNone(match_video_material("帮我查一下客户手机号和订单", platform="Tmall"))

    def test_date_questions_select_the_focused_operation_nodes_and_time_cues(self) -> None:
        cases = [
            ("考勤机年份怎么修改？", ["adjust_year"], "00:18–00:24"),
            ("月份怎么调？", ["adjust_month_or_day_value"], "00:26–00:29"),
            ("日期中的日怎么改？", ["move_to_month_or_day", "adjust_month_or_day_value"], "00:24–00:29"),
            ("日期调好以后怎么确认保存？", ["confirm_date_settings"], "00:29–00:31"),
            ("考勤机日期怎么调整？", ["enter_settings", "identify_date_fields"], "00:02–00:31"),
        ]
        for question, expected_nodes, expected_range in cases:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual(expected_nodes, [node["node_id"] for node in result["selected_nodes"]])
                self.assertEqual(expected_range, result["time_cue"])
                expected_start = expected_range.split("–", 1)[0]
                self.assertIn(f"本段内容从视频 {expected_start} 开始", result["reply"])
                self.assertIn(f"对应操作范围 {expected_range}", result["reply"])
                self.assertGreaterEqual(len(result["screenshots"]), 1)
                self.assertLessEqual(len(result["screenshots"]), 2)
                self.assertEqual(len(result["screenshots"]) * 2, len(result["actions"]))

    def test_time_questions_select_focused_nodes_and_exact_time_cues(self) -> None:
        cases = [
            ("怎样进入考勤机时间设置？", ["enter_settings"], "00:03–00:05"),
            ("进入00组后怎么到01组？", ["confirm_open_group_01"], "00:16–00:18"),
            ("考勤机小时怎么调？", ["move_between_time_digits"], "00:21–00:28"),
            ("考勤机分钟怎么修改？", ["adjust_minute_value"], "00:28–00:32"),
            ("时间调好后怎么保存？", ["confirm_time_settings"], "00:32–00:34"),
            ("考勤机时间不准，怎么调？", ["enter_settings", "identify_time_fields"], "00:03–00:34"),
        ]
        for question, expected_nodes, expected_range in cases:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual("attendance_set_time", result["content_id"])
                self.assertEqual(expected_nodes, [node["node_id"] for node in result["selected_nodes"]])
                self.assertEqual(expected_range, result["time_cue"])
                expected_start = expected_range.split("–", 1)[0]
                self.assertIn(f"本段内容从视频 {expected_start} 开始", result["reply"])
                self.assertIn(f"对应操作范围 {expected_range}", result["reply"])
                self.assertGreaterEqual(len(result["screenshots"]), 1)
                self.assertLessEqual(len(result["screenshots"]), 2)

    def test_dual_color_natural_questions_select_one_exact_node(self) -> None:
        cases = [
            ("什么时候会是红色？", "dual_color_meaning", "explain_red_exception", "00:12–00:16"),
        ]
        for question, segment_id, node_id, time_cue in cases:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual("attendance_dual_color", result["content_id"])
                self.assertEqual(segment_id, result["segment_id"])
                self.assertEqual([node_id], [node["node_id"] for node in result["selected_nodes"]])
                self.assertEqual(time_cue, result["time_cue"])
                self.assertEqual(1, len(result["screenshots"]))

    def test_reset_password_questions_select_only_the_focused_nodes(self) -> None:
        cases = [
            ("忘记密码怎么进入恢复模式？", "enter_reset_mode", ["hold_settings_until_hh", "hold_next_until_music"], "00:03–00:15"),
            ("重置时音乐一直响怎么办？", "wait_for_reset_music", ["wait_for_music_to_finish"], "00:15–00:59"),
            ("铃声结束以后怎么做？", "enter_default_after_reset", ["enter_default_password_after_reset", "confirm_default_and_enter_f1"], "00:59–01:07"),
            ("F1和F2的新密码怎么输入？", "set_and_confirm_new_password", ["enter_new_password_in_f1", "repeat_new_password_in_f2"], "01:07–01:19"),
            ("新密码怎么确认保存？", "save_reset_password", ["confirm_save_and_return_home"], "01:19–01:22"),
        ]
        for question, segment_id, node_ids, time_cue in cases:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual("attendance_reset_password", result["content_id"])
                self.assertEqual(segment_id, result["segment_id"])
                self.assertEqual(node_ids, [node["node_id"] for node in result["selected_nodes"]])
                self.assertEqual(time_cue, result["time_cue"])
                self.assertLessEqual(len(result["screenshots"]), 2)
                self.assertIn("cloud.video.taobao.com", result["video_url"])

    def test_remaining_videos_return_one_focused_card_and_platform_link(self) -> None:
        cases = [
            ("打印偏下怎么往上调？", "attendance_punch_position"),
            ("手动打卡第一班开始时间怎么设？", "attendance_manual_punch"),
            ("怎么打印考勤机测试页？", "attendance_test_print"),
            ("闹钟响多久怎么设置？", "attendance_ring"),
            ("怎样修改考勤机密码？", "attendance_modify_password"),
        ]
        for question, content_id in cases:
            for platform, host in (
                ("Tmall", "cloud.video.taobao.com"),
                ("JD", "300hu.com"),
                ("Pinduoduo", "video5.pddpic.com"),
            ):
                with self.subTest(question=question, platform=platform):
                    result = match_video_material(question, platform=platform)
                    assert result is not None
                    self.assertEqual(content_id, result["content_id"])
                    self.assertIn(host, result["video_url"])
                    self.assertGreaterEqual(len(result["screenshots"]), 1)
                    self.assertLessEqual(len(result["screenshots"]), 2)
                    self.assertIn("本段内容从视频", result["reply"])
                    self.assertEqual("video_material_card", result["type"])

    def test_cross_tutorial_conflicts_are_clarified_or_routed_safely(self) -> None:
        forgot = match_video_material("忘记密码怎么修改？", platform="Tmall")
        assert forgot is not None
        self.assertEqual("attendance_reset_password", forgot["content_id"])
        self.assertEqual("enter_reset_mode", forgot["segment_id"])

        for question in ("两个班次怎么开启双色打印？", "三个班次还能设置红色吗？"):
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual("clarification", result["type"])
                self.assertIsNone(result["video_url"])
                self.assertEqual([], result["screenshots"])
                self.assertIn("02 组", result["reply"])

        ambiguous = match_video_material("第02组设01是什么意思？", platform="Tmall")
        assert ambiguous is not None
        self.assertEqual("clarification", ambiguous["type"])
        self.assertIsNone(ambiguous["video_url"])

        expected = {
            "第02组设00是什么意思？": ("attendance_manual_punch", "enable_manual_punch"),
            "第02组设02是什么意思？": ("attendance_set_shifts", "two_shifts"),
            "第02组设03是什么意思？": ("attendance_set_shifts", "three_shifts"),
        }
        for question, (content_id, segment_id) in expected.items():
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual(content_id, result["content_id"])
                self.assertEqual(segment_id, result["segment_id"])
                self.assertLessEqual(len(result["screenshots"]), 2)

    def test_print_position_conflict_queries_keep_exact_time_cues(self) -> None:
        cases = [
            ("打印在线下方怎么往上调？", "raise_print_position", "00:19–00:22"),
            ("打印在线上方怎么往下调？", "lower_print_position", "00:22–00:26"),
            ("第三方纸卡打印位置偏了", "third_party_card_adjustment", "00:26–00:38"),
        ]
        for question, segment_id, cue in cases:
            with self.subTest(question=question):
                result = match_video_material(question, platform="Tmall")
                assert result is not None
                self.assertEqual("attendance_punch_position", result["content_id"])
                self.assertEqual(segment_id, result["segment_id"])
                self.assertEqual(cue, result["time_cue"])

        buttons = match_video_material("按键分别什么功能？", platform="Tmall")
        assert buttons is not None
        self.assertEqual("00:05–00:30", buttons["time_cue"])


if __name__ == "__main__":
    unittest.main()
