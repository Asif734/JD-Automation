from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "confirmed_dot_matrix_updates_2026_08_24_afternoon_kb.md"
CARDS_PATH = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF_PATH = ROOT / "rag_cards/high_frequency_queries.json"

EXPECTED_IDS = {
    "dot_matrix_windows_driver_cross_model_port_test",
    "dot_matrix_remove_duplicate_drivers_clean_reinstall",
    "dot_matrix_front_feed_paper_sensor",
    "suyintong_template_inventory_records",
    "suyintong_no_device_found_refresh_icon",
    "dot_matrix_narrow_front_feed_skew",
    "dot_matrix_left_sprocket_hole_offset",
    "dot_matrix_page_too_black_reduce_density",
    "dot_matrix_density_dpi_location",
    "dot_matrix_package_test_paper_layers",
    "tmall_zto_no_sf_no_next_day_promise",
    "dot_matrix_multi_device_sequential_jobs",
    "platform_chat_then_phone_handoff",
    "dot_matrix_standard_half_third_page_height",
    "dot_matrix_qr_code_types_china",
    "tmall_invoice_return_dot_matrix",
    "dot_matrix_preprinted_form_duplicate_overlay",
    "dot_matrix_ribbon_model_match",
    "dot_matrix_outdoor_power_800w",
}


def load_cards() -> dict[str, dict]:
    return {
        item["id"]: item
        for item in (
            json.loads(line)
            for line in CARDS_PATH.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }


def test_confirmed_source_contains_all_critical_values() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    for value in [
        "AK890/TG890",
        "AK890/TD630",
        "100–241 mm",
        "93.1 mm",
        "139.7 mm",
        "1–6 联",
        "0.45 mm",
        "No Device Found",
        "APP连接二维码",
        "www.zjweiting.com/download.htm",
        "中通快递",
        "不承诺顺丰",
        "特殊付费安排",
        "200 W",
        "机器内置电源线",
        "没有外接电源适配器",
    ]:
        assert value in text


def test_new_cards_exist_are_active_and_unique() -> None:
    cards = load_cards()
    assert EXPECTED_IDS <= cards.keys()
    assert all(cards[card_id]["status"] == "active" for card_id in EXPECTED_IDS)
    raw_ids = [json.loads(line)["id"] for line in CARDS_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert len(raw_ids) == len(set(raw_ids))


def test_updated_existing_cards_follow_confirmed_rules() -> None:
    cards = load_cards()
    offline = cards["dot_matrix_no_print_offline_queue"]["reply_template"]
    assert "可用在线驱动" in offline
    assert "持续的重复或错误驱动故障" in offline
    assert "删除所有重复" not in offline
    assert "不需要按进纸键" in cards["dot_matrix_feed_sensor"]["reply_template"]
    assert "取下色带" in cards["dot_matrix_feed_sensor"]["reply_template"]
    assert "不受打印机品牌限制" in cards["dot_matrix_windows_business_software_printing"]["reply_template"]
    assert "同一时间只处理一个" in cards["suyintong_multiple_phones_templates"]["reply_template"]
    assert "中通" in cards["confirmed_platform_shipping_2026_08_18"]["reply_template"]
    assert "不承诺顺丰" in cards["confirmed_platform_shipping_2026_08_18"]["reply_template"]
    assert "人工核实" in cards["confirmed_platform_shipping_2026_08_18"]["reply_template"]


def test_customer_templates_respect_confirmed_response_scope() -> None:
    cards = load_cards()
    black_reply = cards["dot_matrix_page_too_black_reduce_density"]["reply_template"]
    feed_reply = cards["dot_matrix_narrow_front_feed_skew"]["reply_template"]
    install_reply = cards["windows_usb_driver_install_visual_guide"]["reply_template"]
    assert "亮度" not in black_reply
    assert "孔位决定" not in feed_reply
    assert "猜型号" not in install_reply


def test_high_frequency_queries_point_to_existing_cards() -> None:
    cards = load_cards()
    hf = json.loads(HF_PATH.read_text(encoding="utf-8"))
    assert all(item["card_id"] in cards for item in hf["queries"])
    mapped = {item["card_id"] for item in hf["queries"]}
    assert EXPECTED_IDS <= mapped


def test_china_customer_facing_app_name_is_suyintong() -> None:
    cards = load_cards()
    for card_id in [
        "suyintong_no_device_found_refresh_icon",
        "suyintong_template_inventory_records",
        "dot_matrix_qr_code_types_china",
    ]:
        assert "速印通" in cards[card_id]["reply_template"]
        assert "Grozziie App" not in cards[card_id]["reply_template"]


def test_source_documents_received_direct_corrections() -> None:
    after_sales = (ROOT / "dot_matrix_after_sales_issues_kb.md").read_text(encoding="utf-8")
    wifi = (ROOT / "wifi_bluetooth_printer_kb.md").read_text(encoding="utf-8")
    shipping = (ROOT / "confirmed_customer_service_updates_2026_08_18_kb.md").read_text(encoding="utf-8")
    training = (ROOT / "qianniu_customer_service_training_kb.md").read_text(encoding="utf-8")
    assert "AK890/TG890" in after_sales and "AK890/TD630" in after_sales
    assert "No Device Found/未找到设备" in wifi
    assert "模板功能中创建、编辑并打印库存管理" in wifi
    assert "常规使用中通快递" in shipping
    assert "非质量问题的寄回运费由买家承担" in training
