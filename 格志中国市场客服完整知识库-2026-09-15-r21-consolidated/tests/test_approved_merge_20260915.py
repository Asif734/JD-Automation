import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARDS_PATH = ROOT / "rag_cards" / "customer_service_rag_cards.jsonl"
QUERIES_PATH = ROOT / "rag_cards" / "high_frequency_queries.json"


def load_cards():
    return {
        row["id"]: row
        for row in (
            json.loads(line)
            for line in CARDS_PATH.read_text(encoding="utf-8-sig").splitlines()
            if line.strip()
        )
    }


class ApprovedMergeRules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cards = load_cards()

    def reply(self, card_id):
        return self.cards[card_id]["reply_template"]

    def test_ak910_a3_and_native_macos_are_unsupported(self):
        reply = self.reply("ak910_presale_fast_answers")
        self.assertIn("A3=不支持", reply)
        self.assertIn("不支持原生macOS", reply)

    def test_bulk_discount_request_routes_to_human(self):
        card = self.cards["current_product_page_price_coupon_bulk"]
        text = json.dumps(card, ensure_ascii=False)
        self.assertIn("批量", text)
        self.assertIn("转人工", text)
        self.assertIn(
            {"type": "collect_info", "fields": ["具体购买数量"]},
            card["actions"],
        )
        self.assertIn(
            {"type": "route_human_for_bulk_price"},
            card["actions"],
        )

    def test_fixed_page_height_applies_to_all_dot_matrix_models(self):
        reply = self.reply("dot_matrix_fixed_page_height_exact_path")
        self.assertIn("所有针式打印机型号", reply)
        self.assertNotIn("仅用于TD630", reply)
        self.assertNotIn("仅用于TD630G", reply)

    def test_all_dot_matrix_models_support_front_single_sheet_feed(self):
        reply = self.reply("dot_matrix_model_feed_modes")
        self.assertIn("所有针式打印机型号都支持前部单张进纸", reply)

    def test_multi_device_jobs_are_sequential_and_third_party_files_use_suyintong(self):
        reply = self.reply("dot_matrix_multi_device_sequential_jobs")
        self.assertIn("按队列顺序", reply)
        self.assertIn("同一时间只处理一个任务", reply)
        self.assertIn("速印通", reply)
        self.assertNotIn("多台手机可以同时发送", reply)

    def test_table_line_guidance_omits_thin_border_and_position_two(self):
        reply = self.reply("dot_matrix_thick_table_lines_settings")
        self.assertNotIn("细线", reply)
        self.assertNotIn("位置2", reply)
        self.assertNotIn("标记位置2", reply)
        self.assertIn("第 6 档", reply)

    def test_speed_reply_does_not_explicitly_name_unavailable_modes(self):
        reply = self.reply("dot_matrix_unified_driver_speed")
        self.assertNotIn("High Speed", reply)
        self.assertNotIn("Draft", reply)
        self.assertNotIn("高速或草稿", reply)

    def test_existing_shipping_insurance_may_be_used_without_purchase_instruction(self):
        reply = self.reply("global_refund_return_high_risk")
        self.assertIn("已有运费险", reply)
        self.assertIn("可以按平台规则使用", reply)
        self.assertNotIn("优先走平台运费险", reply)
        self.assertNotIn("购买运费险", reply)

    def test_windows_universal_installer_is_default_first_response(self):
        reply = self.reply("printer_driver_confirm_model_label_before_download")
        self.assertIn("先发送Windows通用安装包", reply)
        self.assertIn("如果您使用Mac", reply)

    def test_ribbon_rule_matches_confirmed_2024_clasp_policy(self):
        reply = self.reply("dot_matrix_ribbon_model_match")
        for expected in ("其他品牌", "一般建议选002", "2024年以前", "灰色卡扣选002", "黑色卡扣选001"):
            self.assertIn(expected, reply)

    def test_consolidated_card_and_query_sets_are_unique_and_resolved(self):
        rows = [json.loads(line) for line in CARDS_PATH.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
        self.assertEqual(len(rows), 435)
        self.assertEqual(len({row["id"] for row in rows}), 435)
        queries = json.loads(QUERIES_PATH.read_text(encoding="utf-8-sig"))["queries"]
        self.assertEqual(len(queries), 711)
        self.assertEqual(len({row["query"] for row in queries}), 711)
        ids = {row["id"] for row in rows}
        self.assertFalse({row["card_id"] for row in queries} - ids)


if __name__ == "__main__":
    unittest.main()
