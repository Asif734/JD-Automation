from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UPDATE = ROOT / "confirmed_conflict_remediation_2026_09_13_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards/high_frequency_queries.json"


EXPECTED_CARDS = {
    "C01": "dot_matrix_start_position_sensor_after_settings",
    "C02": "suyintong_bold_text_contrast_lever_6",
    "C03": "tmall_paid_sf_exception_handoff",
    "C04": "dot_matrix_dotnet_win7_manual_driver",
    "C05": "dot_matrix_windows_offline_usb_detection_first",
    "C06": "dot_matrix_macos_td630_queue_offline",
    "C07": "dot_matrix_vertical_feed_discontinuity_one_way",
    "C08": "dot_matrix_garbled_output_evidence_router",
    "C09": "dot_matrix_drag_mark_clean_ribbon_free_test",
    "C10": "dot_matrix_multipart_paper_delamination",
    "C11": "dot_matrix_new_housing_logo_model_label",
    "C12": "dot_matrix_shutdown_and_no_feed_router",
    "C13": "dot_matrix_nonfixed_broken_characters_hardware_first",
    "C14": "dot_matrix_isolated_glyph_font_compatibility",
    "C15": "dot_matrix_shutdown_sequence",
    "C16": "dot_matrix_windows_wifi_automatic_search",
    "C17": "dot_matrix_driver_zip_exe_fallback",
    "C18": "dot_matrix_windows_test_page_overlap",
    "C19": "dot_matrix_configure_ui_semantics_internal",
    "C20": "dot_matrix_usb_cable_connector_default_length",
}


def load_cards() -> dict[str, dict]:
    cards: dict[str, dict] = {}
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            card = json.loads(line)
            cards[card["id"]] = card
    return cards


class ConflictRemediationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.update_text = UPDATE.read_text(encoding="utf-8")
        cls.cards = load_cards()
        hf = json.loads(HF.read_text(encoding="utf-8"))
        cls.hf = {"".join(item["query"].lower().split()): item["card_id"] for item in hf["queries"]}

    def test_authoritative_update_contains_every_approved_decision(self) -> None:
        for conflict_id in EXPECTED_CARDS:
            with self.subTest(conflict_id=conflict_id):
                self.assertIn(f"## {conflict_id}", self.update_text)

        required_phrases = [
            "纸张感应器", "最高第 6 档", "人工客服核实是否可以特殊付费安排顺丰",
            ".NET 4.8", "AT32", "NOBLE PARAGON TD630 SZ", "One-way printing",
            "不兼容的第三方手机 App", "不安装色带使用多联纸测试", "分层",
            "不得编造具体型号", "将关机和不进纸拆分处理", "先检查色带和打印头",
            "表格线和其他字体都正常", "红灯闪烁", "Automatic → Search",
            "只有 ZIP 压缩包需要解压", "实际文档", "内部界面语义", "1.2 米",
        ]
        for phrase in required_phrases:
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, self.update_text)

    def test_each_conflict_has_one_active_curated_card(self) -> None:
        for conflict_id, card_id in EXPECTED_CARDS.items():
            with self.subTest(conflict_id=conflict_id, card_id=card_id):
                card = self.cards[card_id]
                self.assertEqual(card["status"], "active")
                self.assertEqual(card["resolution_id"], conflict_id)
                self.assertIn(UPDATE.name, card["source_files"])

    def test_user_override_action_order_is_exact(self) -> None:
        expected = {
            "C02": ["lower_mobile_contrast", "raise_paper_thickness_lever_to_6_or_as_needed", "test_one_page"],
            "C05": ["restore_usb_connection", "verify_at32_detection", "check_matching_port", "then_check_queue_offline_state"],
            "C12": ["split_shutdown_and_no_feed", "try_known_working_outlet", "handoff_if_shutdown_persists", "front_insert_paper", "clean_matching_paper_sensor"],
            "C13": ["diagnose_ribbon", "diagnose_printhead", "then_change_to_common_font", "then_lower_paper_thickness_one_step"],
            "C14": ["compare_other_fonts_and_table_lines", "try_common_font_first", "hardware_only_if_fixed_across_fonts"],
            "C18": ["reposition_paper_start_edge", "print_actual_document", "check_paper_size_and_driver_only_if_document_overlaps"],
        }
        for conflict_id, action_types in expected.items():
            card = self.cards[EXPECTED_CARDS[conflict_id]]
            self.assertEqual([action["type"] for action in card["actions"]], action_types)

    def test_internal_and_customer_facing_boundaries(self) -> None:
        c02 = self.cards[EXPECTED_CARDS["C02"]]
        self.assertNotIn("Density", c02["reply_template"])
        self.assertNotIn("DPI", c02["reply_template"])
        self.assertNotIn("灰度阈值", c02["reply_template"])

        c03 = self.cards[EXPECTED_CARDS["C03"]]
        self.assertFalse(c03["auto_reply_allowed"])
        self.assertIn("不承诺", c03["reply_template"])
        self.assertIn("人工", c03["reply_template"])

        c16 = self.cards[EXPECTED_CARDS["C16"]]
        self.assertNotIn("Standard TCP/IP", c16["reply_template"])
        self.assertEqual(c16["manual_tcp_ip_policy"], "internal_exception_only")

        c19 = self.cards[EXPECTED_CARDS["C19"]]
        self.assertFalse(c19["auto_reply_allowed"])
        self.assertEqual(c19["usage_policy"], "answer_only_when_customer_asks_what_configure_or_adjacent_date_means")

    def test_high_frequency_routes_cover_all_resolutions(self) -> None:
        expected_queries = {
            "纸放对了还是从中间开始打印": "C01", "手机打印字太粗怎么调": "C02",
            "我补差价可以发顺丰吗": "C03", "windows7缺少net怎么安装驱动": "C04",
            "打印机灰色脱机而at32没有出现": "C05", "mac上nobleparagontd630sz显示offline": "C06",
            "表格中间断开有异常空白带": "C07", "针式打印机打出来是乱码": "C08",
            "打印有水平拖墨划痕": "C09", "多联纸分层卷曲进纸歪": "C10",
            "新打印机没有logo也看不到型号": "C11", "打印机会关机而且不进纸": "C12",
            "打印字符断断续续但不固定": "C13", "只有一个字缺笔画表格线和其他字体正常": "C14",
            "打印机无法关机": "C15", "td630g电脑wifi驱动怎么自动安装": "C16",
            "zip驱动包解压失败": "C17", "windows测试页文字重叠": "C18",
            "configure按钮和旁边日期是什么": "C19", "自己买的3米usb线能用吗": "C20",
        }
        for query, conflict_id in expected_queries.items():
            with self.subTest(query=query):
                self.assertEqual(self.hf[query], EXPECTED_CARDS[conflict_id])

    def test_active_cards_do_not_cite_excluded_runtime_paths(self) -> None:
        forbidden = ("outputs/", "work/", "tmp/", "logs/")
        for card in self.cards.values():
            if card.get("status") != "active":
                continue
            for source in card.get("source_files", []):
                with self.subTest(card=card["id"], source=source):
                    self.assertFalse(source.startswith(forbidden))

        normal = self.cards["attendance_normal_punch_mechanical_baseline"]
        self.assertEqual(normal["evidence"]["artifact_availability"], "metadata_only")
        self.assertNotIn("screenshots", normal["evidence"])
        self.assertNotIn("contact_sheets", normal["evidence"])

    def test_package_scoped_versions_share_one_release_constant(self) -> None:
        from scripts.package_version import PACKAGE_ROOT, PACKAGE_VERSION
        from scripts.package_grozziie_china_kb import PACKAGE_ROOT as BUILDER_ROOT
        from scripts.build_rag_index import PACKAGE_VERSION as INDEX_VERSION

        self.assertEqual(PACKAGE_VERSION, "2026-09-15-r21-consolidated")
        self.assertEqual(PACKAGE_ROOT, "格志中国市场客服完整知识库-2026-09-15-r21-consolidated")
        self.assertEqual(BUILDER_ROOT, PACKAGE_ROOT)
        self.assertEqual(INDEX_VERSION, PACKAGE_VERSION)
        self.assertEqual(json.loads(HF.read_text(encoding="utf-8"))["version"], PACKAGE_VERSION)
        catalog = json.loads((ROOT / "rag_cards/china_market_video_catalog.json").read_text(encoding="utf-8"))
        self.assertEqual(catalog["version"], PACKAGE_VERSION)


if __name__ == "__main__":
    unittest.main()
