from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
UPDATE = ROOT / "confirmed_tencent_sept13_updates_2026_09_14_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards/high_frequency_queries.json"


EXPECTED_CARDS = {
    "S13-C01": "dot_matrix_daibaiprint_dotnet_crash",
    "S13-C02": "dot_matrix_daibaiprint_dotnet_crash",
    "S13-C03": "printer_universal_installer_package_aliases",
    "S13-C04": "positive_review_reward_matrix",
    "S13-C05": "current_product_page_price_coupon_bulk",
    "S13-C06": "global_refund_return_high_risk",
    "S13-C07": "dot_matrix_portrait_default_orientation",
    "S13-C08": "dot_matrix_isolated_glyph_font_compatibility",
    "S13-C09": "suyintong_reduce_contrast_dark_print",
    "S13-C10": "dot_matrix_immediate_eject_blank_job_router",
    "S13-C11": "dot_matrix_feed_sensor",
    "S13-C12": "dot_matrix_visible_internal_paper_jam",
    "S13-C13": "suyintong_no_device_found_refresh_icon",
    "S13-C14": "website_brand_service_closed_platform_support",
    "S13-C15": "document_correct_orientation_content_too_small",
}


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", value.lower())


def load_cards() -> dict[str, dict]:
    return {
        card["id"]: card
        for line in CARDS.read_text(encoding="utf-8").splitlines()
        if line.strip()
        for card in [json.loads(line)]
    }


def resolution_ids(card: dict) -> set[str]:
    values = set(card.get("resolution_ids", []))
    if card.get("resolution_id"):
        values.add(card["resolution_id"])
    return values


class ConfirmedTencentSept13Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.update_text = UPDATE.read_text(encoding="utf-8")
        cls.cards = load_cards()
        hf = json.loads(HF.read_text(encoding="utf-8"))
        cls.hf = {normalize(item["query"]): item["card_id"] for item in hf["queries"]}

    def test_authoritative_source_contains_all_confirmed_decisions(self) -> None:
        for resolution in EXPECTED_CARDS:
            with self.subTest(resolution=resolution):
                self.assertIn(f"## {resolution}", self.update_text)

        required = [
            "DaiBaiPrint", ".NET", "ThermalNobleDriver", "DotNobleDriver",
            "同一通用安装包", "不得索取密码或验证码", "5 元券",
            "商家不发放优惠券", "不在自动回复中指示客户选择运费险",
            "默认纵向", "隶书", "纸厚扳手调到最高第 6 档",
            "SPOOL", "纸张感应器", "不得拉扯白色排线", "Cancel",
            "直接客服联系功能已关闭", "关闭自动适应",
        ]
        for phrase in required:
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, self.update_text)

    def test_every_resolution_has_one_active_source_backed_card(self) -> None:
        counts = {resolution: 0 for resolution in EXPECTED_CARDS}
        for card in self.cards.values():
            if card.get("status") != "active":
                continue
            for resolution in resolution_ids(card) & counts.keys():
                counts[resolution] += 1

        for resolution, card_id in EXPECTED_CARDS.items():
            with self.subTest(resolution=resolution, card_id=card_id):
                card = self.cards[card_id]
                self.assertEqual(card["status"], "active")
                self.assertIn(resolution, resolution_ids(card))
                self.assertIn(UPDATE.name, card["source_files"])
                self.assertEqual(counts[resolution], 1)

    def test_daibaiprint_crash_is_evidence_gated_and_has_no_usb_detour(self) -> None:
        card = self.cards[EXPECTED_CARDS["S13-C01"]]
        reply = card["reply_template"]
        self.assertIn(".NET", reply)
        self.assertIn("重启", reply)
        self.assertIn("重新运行安装程序", reply)
        self.assertNotIn("USB", reply)
        self.assertEqual(card["trigger_policy"], "only_when_daibaiprint_or_dotnet_error_is_observed_or_reported")

    def test_universal_installer_aliases_keep_product_settings_separate(self) -> None:
        card = self.cards[EXPECTED_CARDS["S13-C03"]]
        reply = card["reply_template"]
        self.assertIn("ThermalNobleDriver", reply)
        self.assertIn("DotNobleDriver", reply)
        self.assertIn("同一通用安装包", reply)
        self.assertIn("热敏", reply)
        self.assertIn("针式", reply)
        self.assertIn("安装后", reply)
        self.assertIn("型号", reply)

    def test_reward_coupon_and_shipping_boundaries(self) -> None:
        reward = self.cards[EXPECTED_CARDS["S13-C04"]]["reply_template"]
        self.assertIn("天猫和京东", reward)
        self.assertIn("付款账号", reward)
        self.assertIn("人工", reward)
        self.assertIn("不得索取密码或验证码", reward)
        self.assertIn("拼多多", reward)
        self.assertIn("5元", reward)
        self.assertIn("自动", reward)

        coupon = self.cards[EXPECTED_CARDS["S13-C05"]]["reply_template"]
        self.assertIn("商品页面当前显示的价格", coupon)
        self.assertIn("平台券或补贴", coupon)
        self.assertIn("具体购买数量", coupon)
        self.assertIn("转人工客服", coupon)

        refund = self.cards[EXPECTED_CARDS["S13-C06"]]["reply_template"]
        self.assertIn("已有运费险", refund)
        self.assertIn("可以按平台规则使用", refund)
        self.assertNotIn("购买运费险", refund)
        self.assertIn("运费", refund)
        self.assertIn("人工", refund)

    def test_printing_troubleshooting_sequences(self) -> None:
        portrait = self.cards[EXPECTED_CARDS["S13-C07"]]
        self.assertEqual(portrait["default_orientation"], "portrait")
        self.assertIn("纵向", portrait["reply_template"])

        font = self.cards[EXPECTED_CARDS["S13-C08"]]
        self.assertIn("隶书", font["keywords"] + font.get("synonyms", []))
        self.assertIn("更换", font["reply_template"])

        dark = self.cards[EXPECTED_CARDS["S13-C09"]]
        self.assertEqual(
            [action["type"] for action in dark["actions"]],
            ["raise_paper_thickness_lever_to_6", "reduce_suyintong_contrast_or_windows_grayscale_threshold", "test_one_page"],
        )

        eject = self.cards[EXPECTED_CARDS["S13-C10"]]
        self.assertEqual(
            [action["type"] for action in eject["actions"]],
            ["clear_print_queue_and_spool_hidden_jobs", "remove_leading_blank_pages", "send_fresh_job", "clean_sensor_if_still_abnormal"],
        )

        sensor = self.cards[EXPECTED_CARDS["S13-C11"]]
        self.assertIn("红灯闪烁", sensor["reply_template"])
        self.assertEqual(
            [action["type"] for action in sensor["actions"]],
            ["power_off", "clean_paper_sensor_with_small_amount_of_alcohol", "dry_completely", "reload_and_test"],
        )

        jam = self.cards[EXPECTED_CARDS["S13-C12"]]
        self.assertEqual(
            [action["type"] for action in jam["actions"]],
            ["stop_printing_and_power_off", "set_paper_thickness_lever_to_6", "remove_ribbon_if_blocking", "use_feed_eject_controls_safely", "remove_scraps", "reload_flat_aligned_paper"],
        )
        self.assertIn("白色排线", "".join(jam["do_not_say"]))

    def test_mobile_website_and_small_content_guidance(self) -> None:
        mobile = self.cards[EXPECTED_CARDS["S13-C13"]]
        self.assertIn("Cancel", mobile["reply_template"])
        self.assertIn("Refresh", mobile["reply_template"])
        self.assertNotIn("手动输入IP", mobile["reply_template"])
        self.assertEqual(mobile["manual_ip_policy"], "windows_abnormal_internal_only")

        website = self.cards[EXPECTED_CARDS["S13-C14"]]["reply_template"]
        self.assertIn("直接客服联系功能已关闭", website)
        self.assertIn("购买平台聊天", website)
        self.assertIn("下载驱动", website)
        self.assertIn("视频", website)
        self.assertIn("说明书", website)
        self.assertNotIn("网站服务已关闭", website)

        small = self.cards[EXPECTED_CARDS["S13-C15"]]["reply_template"]
        self.assertIn("增大字号", small)
        self.assertIn("关闭自动适应", small)
        self.assertIn("行高", small)
        self.assertIn("列宽", small)
        self.assertIn("保持当前正确方向", small)

    def test_high_frequency_routes_cover_all_confirmed_cases(self) -> None:
        expected = {
            "DaiBaiPrint报错退出": "S13-C01",
            "没有DaiBaiPrint报错要不要安装net": "S13-C02",
            "ThermalNobleDriver和DotNobleDriver是同一个驱动吗": "S13-C03",
            "好评返现要支付宝账号吗": "S13-C04",
            "商家可以发优惠券吗": "S13-C05",
            "退货要不要选运费险": "S13-C06",
            "打印方向默认选纵向还是横向": "S13-C07",
            "隶书字体打印异常": "S13-C08",
            "打印整张全黑怎么办": "S13-C09",
            "纸张进入后立即退出再放才打印": "S13-C10",
            "纸全部被吸进去红灯闪烁": "S13-C11",
            "机器里面明显卡纸": "S13-C12",
            "手机APP提示输入IP": "S13-C13",
            "官网提示无该品牌": "S13-C14",
            "方向正确但打印内容太小": "S13-C15",
        }
        for query, resolution in expected.items():
            with self.subTest(query=query):
                self.assertEqual(self.hf[normalize(query)], EXPECTED_CARDS[resolution])

    def test_release_version_is_bumped(self) -> None:
        from scripts.package_version import PACKAGE_ROOT, PACKAGE_VERSION

        self.assertEqual(PACKAGE_VERSION, "2026-09-15-r21-consolidated")
        self.assertEqual(PACKAGE_ROOT, "格志中国市场客服完整知识库-2026-09-15-r21-consolidated")

    def test_release_audit_covers_all_new_resolutions(self) -> None:
        from scripts.audit_kb_conflicts import EXPECTED_RESOLUTIONS

        self.assertTrue(set(EXPECTED_CARDS).issubset(EXPECTED_RESOLUTIONS))

    def test_built_index_routes_representative_queries_to_correct_cards(self) -> None:
        from scripts.search_rag import search

        index = json.loads((ROOT / "rag_index/customer_service_rag_index.json").read_text(encoding="utf-8"))
        expected = {
            "DaiBaiPrint报错退出": "dot_matrix_daibaiprint_dotnet_crash",
            "ThermalNobleDriver和DotNobleDriver是同一个驱动吗": "printer_universal_installer_package_aliases",
            "商家可以发优惠券吗": "current_product_page_price_coupon_bulk",
            "打印整张全黑怎么办": "suyintong_reduce_contrast_dark_print",
            "纸张进入后立即退出再放才打印": "dot_matrix_immediate_eject_blank_job_router",
            "机器里面明显卡纸": "dot_matrix_visible_internal_paper_jam",
            "手机APP提示输入IP": "suyintong_no_device_found_refresh_icon",
            "官网提示无该品牌": "website_brand_service_closed_platform_support",
            "方向正确但打印内容太小": "document_correct_orientation_content_too_small",
        }
        for query, card_id in expected.items():
            with self.subTest(query=query):
                results = search(index, query, top_k=1)
                self.assertTrue(results)
                self.assertEqual(results[0]["id"], card_id)


if __name__ == "__main__":
    unittest.main()
