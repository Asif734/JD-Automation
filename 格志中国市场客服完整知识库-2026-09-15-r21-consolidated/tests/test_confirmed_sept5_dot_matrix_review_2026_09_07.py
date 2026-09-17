from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "confirmed_dot_matrix_sept5_review_updates_2026_09_07_kb.md"
CARDS = ROOT / "rag_cards" / "customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards" / "high_frequency_queries.json"
SEARCH = ROOT / "scripts" / "search_rag.py"


CARD_IDS = {
    "dot_matrix_job_brief_needle_sound_stops",
    "jd_corporate_transfer_only",
    "printer_installer_package_connection_independent",
    "dot_matrix_rear_feed_skew_top_lever",
    "dot_matrix_saved_document_reusable_template",
    "dot_matrix_stationary_head_twisted_ribbon",
    "positive_review_reward_matrix",
    "dot_matrix_stub_cropped_document_settings",
    "dot_matrix_low_quality_document_ghostlike",
    "printer_model_exchange_same_model_only",
    "dot_matrix_front_feed_job_printing_no_feed",
    "current_product_page_price_coupon_bulk",
    "dot_matrix_unknown_usb_descriptor_failure",
    "dot_matrix_no_matching_driver_manual_install",
    "suyintong_missing_table_border_line_width",
}


def load_cards() -> dict[str, dict]:
    return {
        card["id"]: card
        for card in (
            json.loads(line)
            for line in CARDS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }


def top(query: str) -> dict:
    result = subprocess.run(
        [sys.executable, str(SEARCH), query, "--json", "--top-k", "1"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout)[0]


def test_source_records_all_confirmed_sept5_review_rules() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    for phrase in (
        "只有京东自营店铺支持对公转账",
        "安装包不按 USB、Wi-Fi 或蓝牙连接方式区分下载",
        "纸厚扳手调到最高位置",
        "保存为以后重复使用的模板",
        "打印头完全没有移动",
        "拼多多：所有机器好评后获得5元返现券",
        "针式打印机：优先赠送色带",
        "高质量 PDF",
        "换货只能处理同型号",
        "设备描述符请求失败",
        "控制面板 → 设备和打印机",
        "0.6 或 0.7",
    ):
        assert phrase in text


def test_cards_and_query_mappings_cover_all_confirmed_rules() -> None:
    cards = load_cards()
    assert CARD_IDS <= cards.keys()
    assert all(cards[card_id]["status"] == "active" for card_id in CARD_IDS)
    mapped = {item["card_id"] for item in json.loads(HF.read_text(encoding="utf-8"))["queries"]}
    assert CARD_IDS <= mapped


def test_high_risk_business_and_driver_boundaries_are_exact() -> None:
    cards = load_cards()
    payment = cards["jd_corporate_transfer_only"]["reply_template"]
    assert "只有京东自营店铺" in payment and "其他店铺不支持" in payment

    rewards = cards["positive_review_reward_matrix"]["reply_template"]
    for phrase in ("拼多多", "5元返现券", "考勤机", "针式打印机", "色带", "10元返现"):
        assert phrase in rewards

    installer = cards["printer_installer_package_connection_independent"]["reply_template"]
    assert "不需要按连接方式" in installer
    assert "热敏打印机" in installer


def test_visual_diagnosis_cards_preserve_observed_evidence() -> None:
    cards = load_cards()
    stopped = cards["dot_matrix_job_brief_needle_sound_stops"]["reply_template"]
    assert "电源指示灯已亮" in stopped and "短暂" in stopped and "打印队列" in stopped

    ribbon = cards["dot_matrix_stationary_head_twisted_ribbon"]["reply_template"]
    assert "打印头没有移动" in ribbon and "色带扭曲" in ribbon and "重启" in ribbon

    paper = cards["dot_matrix_rear_feed_skew_top_lever"]["reply_template"]
    assert "后进纸" in paper and "纸厚扳手" in paper and "最高" in paper
    assert "齿轮打滑" not in paper

    border = cards["suyintong_missing_table_border_line_width"]["reply_template"]
    assert "任意单元格" in border and "0.6" in border and "0.7" in border


def test_document_quality_and_usb_errors_are_not_misclassified() -> None:
    cards = load_cards()
    quality = cards["dot_matrix_low_quality_document_ghostlike"]["reply_template"]
    assert "高质量PDF" in quality and "灰度阈值" in quality and "对比度" in quality
    assert "单向打印" not in quality and "财务" not in quality

    usb = cards["dot_matrix_unknown_usb_descriptor_failure"]["reply_template"]
    assert "AT32" in usb and "设备描述符请求失败" in usb
    assert "更换USB接口" in usb and "数据线" in usb

    driver = cards["dot_matrix_no_matching_driver_manual_install"]["reply_template"]
    assert "设备和打印机" in driver and "手动安装驱动" in driver


def test_key_queries_retrieve_the_new_confirmed_cards() -> None:
    expected = {
        "京东自营店铺怎么对公转账": "jd_corporate_transfer_only",
        "好评不要色带想要现金返现": "positive_review_reward_matrix",
        "低质量PDF打印出来灰蒙蒙像重影": "dot_matrix_low_quality_document_ghostlike",
        "未知USB设备设备描述符请求失败": "dot_matrix_unknown_usb_descriptor_failure",
        "安装程序提示没有匹配的驱动": "dot_matrix_no_matching_driver_manual_install",
        "速印通模板表格边框有些线没有打印": "suyintong_missing_table_border_line_width",
        "任务显示正在打印但是前进纸不吸纸": "dot_matrix_front_feed_job_printing_no_feed",
    }
    for query, card_id in expected.items():
        assert top(query)["id"] == card_id
