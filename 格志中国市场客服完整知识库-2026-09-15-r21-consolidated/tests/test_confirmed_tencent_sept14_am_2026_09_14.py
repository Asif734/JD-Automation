from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SOURCE = ROOT / "confirmed_tencent_sept14_am_updates_2026_09_14_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards/high_frequency_queries.json"
QUERY_FILE = ROOT / "rag_cards/customer_service_rag_test_queries.txt"
INDEX = ROOT / "rag_index/customer_service_rag_index.json"


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", value.lower())


def load_cards() -> dict[str, dict]:
    return {
        item["id"]: item
        for item in (
            json.loads(line)
            for line in CARDS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
        if item.get("status") == "active"
    }


EXPECTED_ROUTES = {
    "模板里一排*****是什么意思": "dot_matrix_preprinted_placeholder_fields",
    "针式打印机包装里有色带USB线和测试纸吗": "family_default_package_contents_20260909",
    "APP连接二维码扫不出来怎么手动搜索": "suyintong_app_connect_qr_manual_search",
    "TH880JM灰色TH880JMS在线用哪个": "th880_online_driver_queue_selection",
    "双向打印在哪里设置": "dot_matrix_unified_driver_speed",
    "VIVO手机连接打印机权限怎么开": "suyintong_android_permission_prompt",
    "速印通需要打印机序列号吗": "suyintong_serial_number_not_required",
    "视频里打印机速度太慢怎么加快": "dot_matrix_video_slow_printing_speed",
    "质量问题退货中通顺丰京东运费怎么处理": "quality_return_zto_freight_policy",
    "新款针式打印机色带通用吗": "dot_matrix_ribbon_universal_new_models",
    "TH880JM和TH880JMS纸张尺寸一样吗": "th880_portrait_same_paper_size",
    "官网还能下载驱动看视频和说明书吗": "website_resources_contact_only_closed",
    "速印通固定模板怎么改纸张尺寸增加行数": "suyintong_fixed_template_edit_paper_rows",
    "打印机关机后手机还卡在打印界面": "suyintong_stuck_print_recent_tasks",
    "Windows设置里打印测试页在哪里": "windows_print_test_page_context_routes",
    "扫描app connect二维码一直加载": "suyintong_app_connect_qr_loading",
    "速印通打印手机Excel怎么缩放": "suyintong_excel_document_no_scaling",
    "同一部手机开热点还能用速印通打印吗": "suyintong_same_phone_hotspot_bluetooth_first",
    "鸿蒙平板怎样安装连接针式打印机": "suyintong_harmonyos_bluetooth_setup",
    "换网络后打印机自动关机怎么继续安装": "dot_matrix_wifi_install_power_cycle_continue",
    "打印文字发黑粘在一起要开单向打印吗": "suyintong_mobile_dark_thick_contrast_lever",
}


class TencentSept14AmCorrectionsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.cards = load_cards()
        cls.hf = {
            normalize(item["query"]): item["card_id"]
            for item in json.loads(HF.read_text(encoding="utf-8"))["queries"]
        }

    def test_confirmed_source_records_website_scope_and_operational_rules(self) -> None:
        text = SOURCE.read_text(encoding="utf-8")
        for required in [
            "直接客服联系功能已关闭",
            "驱动下载、视频和说明书",
            "*****",
            "TH880JMS",
            "所有新款针式打印机",
            "中通",
            "顺丰",
            "京东物流",
            "0.6–0.7",
            "同一部手机",
            "没有缩放选项",
        ]:
            with self.subTest(required=required):
                self.assertIn(required, text)

    def test_old_website_and_blanket_driver_cleanup_conflicts_are_removed(self) -> None:
        website = (ROOT / "confirmed_tencent_sept13_updates_2026_09_14_kb.md").read_text(encoding="utf-8")
        afternoon = (ROOT / "confirmed_dot_matrix_updates_2026_08_24_afternoon_kb.md").read_text(encoding="utf-8")
        after_sales = (ROOT / "dot_matrix_after_sales_issues_kb.md").read_text(encoding="utf-8")
        self.assertNotIn("该网站服务已关闭", website)
        self.assertIn("只有直接客服联系功能已关闭", website)
        self.assertNotIn("删除所有重复的在线/离线驱动", afternoon)
        self.assertNotIn("先删除所有重复驱动或 `printdriver`", after_sales)

    def test_all_active_customer_replies_are_free_of_superseded_rules(self) -> None:
        for card_id, card in self.cards.items():
            reply = card.get("reply_template", "")
            with self.subTest(card_id=card_id):
                self.assertNotIn("该网站服务已关闭", reply)
                self.assertNotIn("删除所有重复的在线/离线驱动", reply)
                self.assertNotIn("删除所有重复驱动", reply)
                if card.get("product_line") == "dot_matrix_printer":
                    self.assertNotIn("更换同型号色带", reply)
                    self.assertNotIn("色带购买前核对打印机和色带型号", reply)

    def test_new_behavior_cards_exist_with_required_boundaries(self) -> None:
        for card_id in set(EXPECTED_ROUTES.values()):
            with self.subTest(card_id=card_id):
                self.assertIn(card_id, self.cards)

        website = self.cards["website_resources_contact_only_closed"]
        self.assertIn("驱动", website["reply_template"])
        self.assertIn("视频", website["reply_template"])
        self.assertIn("说明书", website["reply_template"])
        self.assertIn("直接客服", website["reply_template"])
        self.assertNotIn("网站服务已关闭", website["reply_template"])

        ribbon = self.cards["dot_matrix_ribbon_universal_new_models"]
        self.assertIn("通用", ribbon["reply_template"])
        self.assertIn("考勤机", "".join(ribbon["do_not_say"]))

        freight = self.cards["quality_return_zto_freight_policy"]
        self.assertIn("中通", freight["reply_template"])
        self.assertIn("顺丰", freight["reply_template"])
        self.assertIn("京东物流", freight["reply_template"])
        self.assertFalse(freight["auto_reply_allowed"])

    def test_existing_cards_are_narrowed_instead_of_deleted(self) -> None:
        package = self.cards["family_default_package_contents_20260909"]
        self.assertIn("无需确认具体型号", package["reply_template"])
        self.assertNotIn("精确型号/订单选项", package.get("required_slots", []))

        ribbon = self.cards["dot_matrix_ribbon_install"]
        self.assertNotIn("同型号", ribbon["reply_template"])
        self.assertNotIn("色带随便买都一样", ribbon.get("do_not_say", []))

        offline = self.cards["dot_matrix_no_print_offline_queue"]
        self.assertIn("可用在线驱动", offline["reply_template"])
        self.assertNotIn("删除所有重复驱动", offline["reply_template"])

    def test_app_specific_negative_boundaries_are_explicit(self) -> None:
        qr = self.cards["suyintong_app_connect_qr_loading"]
        self.assertNotIn("2.4G", qr["reply_template"])
        self.assertNotIn("手机流量", qr["reply_template"])

        excel = self.cards["suyintong_excel_document_no_scaling"]
        self.assertIn("没有缩放选项", excel["reply_template"])
        self.assertIn("文档打印", excel["reply_template"])

        stuck = self.cards["suyintong_stuck_print_recent_tasks"]
        self.assertIn("最近任务", stuck["reply_template"])
        self.assertIn("无需强制停止", stuck["reply_template"])

        dark = self.cards["suyintong_mobile_dark_thick_contrast_lever"]
        self.assertIn("单向打印与此问题无关", dark["reply_template"])

    def test_email_delivery_customer_copy_omits_package_alias_explanation(self) -> None:
        source = (ROOT / "confirmed_qq_mail_driver_delivery_2026_09_14_kb.md").read_text(encoding="utf-8")
        recommended = source.split("## 5. 推荐邮件正文", 1)[1]
        self.assertNotIn("ThermalNobleDriver", recommended)
        self.assertNotIn("DotNobleDriver", recommended)
        email_card = self.cards["printer_driver_email_reusable_large_attachment"]
        self.assertNotIn("同一个通用安装包", email_card["reply_template"])
        self.assertIn("不要主动说明两个名称", "".join(email_card["do_not_say"]))

    def test_exact_high_frequency_routes_cover_confirmed_queries(self) -> None:
        for query, card_id in EXPECTED_ROUTES.items():
            with self.subTest(query=query):
                self.assertEqual(self.hf[normalize(query)], card_id)

    def test_query_fixture_contains_confirmed_routes(self) -> None:
        text = QUERY_FILE.read_text(encoding="utf-8")
        for query, card_id in EXPECTED_ROUTES.items():
            with self.subTest(query=query):
                self.assertIn(f"{query} -> {card_id}", text)

    def test_built_index_routes_every_confirmed_query_to_top_one(self) -> None:
        from scripts.search_rag import search

        index = json.loads(INDEX.read_text(encoding="utf-8"))
        for query, card_id in EXPECTED_ROUTES.items():
            with self.subTest(query=query):
                result = search(index, query, top_k=1)
                self.assertTrue(result)
                self.assertEqual(result[0]["id"], card_id)

    def test_dangerous_queries_do_not_retrieve_wrong_card(self) -> None:
        from scripts.search_rag import search

        index = json.loads(INDEX.read_text(encoding="utf-8"))
        cases = {
            "打印文字发黑粘在一起要开单向打印吗": "dot_matrix_vertical_feed_discontinuity_one_way",
            "扫描app connect二维码一直加载": "wifi_search_device_not_found",
            "新款针式打印机色带通用吗": "dot_matrix_ribbon_install",
        }
        for query, prohibited in cases.items():
            with self.subTest(query=query):
                result = search(index, query, top_k=1)
                self.assertTrue(result)
                self.assertNotEqual(result[0]["id"], prohibited)

    def test_release_metadata_is_consolidated_r21(self) -> None:
        from scripts.package_version import PACKAGE_ROOT, PACKAGE_VERSION

        self.assertEqual(PACKAGE_VERSION, "2026-09-15-r21-consolidated")
        self.assertEqual(PACKAGE_ROOT, "格志中国市场客服完整知识库-2026-09-15-r21-consolidated")
        self.assertEqual(json.loads(HF.read_text(encoding="utf-8"))["version"], PACKAGE_VERSION)
        self.assertEqual(json.loads(INDEX.read_text(encoding="utf-8"))["version"], PACKAGE_VERSION)


if __name__ == "__main__":
    unittest.main()
