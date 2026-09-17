from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "confirmed_needle_printer_updates_2026_08_24_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards/high_frequency_queries.json"


EXPECTED_CARD_IDS = {
    "dot_matrix_fixed_page_height_refeed",
    "dot_matrix_fixed_page_height_exact_path",
    "dot_matrix_windows_business_software_printing",
    "dot_matrix_mobile_same_flow_no_repeat_question",
    "dot_matrix_mobile_video_verified_platform_only",
    "dot_matrix_continuous_paper_standard_sizes",
    "dot_matrix_two_free_templates",
    "suyintong_china_download",
    "suyintong_store_loading_network",
    "dot_matrix_ribbon_film_before_missing_pin",
    "suyintong_account_password_guest",
    "suyintong_keep_aspect_default_paper",
    "dot_matrix_max_printable_width_203",
    "suyintong_reduce_contrast_dark_print",
    "dot_matrix_skew_physical_alignment_first",
    "dot_matrix_usb_generic_device_names",
    "dot_matrix_driver_direct_link_no_firmware",
    "suyintong_presale_reassurance_video",
    "dot_matrix_loud_noise_printhead_stuck",
    "dot_matrix_ribbon_replacement_tmall_video",
    "dot_matrix_no_photo_screenshot_color_document",
    "dot_matrix_set_physical_printer_default",
    "suyintong_multiple_phones_templates",
}


def load_cards() -> dict[str, dict]:
    cards = {}
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            item = json.loads(line)
            cards[item["id"]] = item
    return cards


def test_authoritative_source_contains_confirmed_measurement_and_links() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    assert "第一孔中心到第三孔中心约为 `1 inch`" in text
    assert "相邻两孔中心距约为 `0.5 inch`" in text
    assert "禁止写成“相邻孔距约 1 inch”" in text
    assert "https://www.zjweiting.com/files_dot/Grozziie.apk" in text
    assert "https://zjweiting.com/nobel/apk/DotNobleDriver.exe" in text
    assert "505903251902" in text
    assert "最大可打印宽度约为 `203 mm`" in text


def test_all_confirmed_issues_have_active_rag_cards() -> None:
    cards = load_cards()
    assert EXPECTED_CARD_IDS <= cards.keys()
    assert all(cards[card_id]["status"] == "active" for card_id in EXPECTED_CARD_IDS)


def test_no_duplicate_rag_card_ids() -> None:
    ids = []
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            ids.append(json.loads(line)["id"])
    assert len(ids) == len(set(ids))


def test_high_frequency_queries_reference_existing_cards() -> None:
    cards = load_cards()
    data = json.loads(HF.read_text(encoding="utf-8"))
    assert all(item["card_id"] in cards for item in data["queries"])
    mapped = {item["card_id"] for item in data["queries"]}
    assert EXPECTED_CARD_IDS <= mapped


def test_existing_conflicting_cards_are_corrected() -> None:
    cards = load_cards()
    app_card = cards["dot_matrix_td630g_iphone_wifi_app"]
    assert app_card["app"] == "速印通"
    assert "Grozziie" not in app_card["reply_template"]
    noise = cards["dot_matrix_td630_normal_speed_noise"]
    assert "六联纸" in noise["normal_branch"]
    assert "打印头卡" in noise["fault_branch"]


def test_key_source_documents_reflect_corrections() -> None:
    after_sales = (ROOT / "dot_matrix_after_sales_issues_kb.md").read_text(encoding="utf-8")
    wifi = (ROOT / "wifi_bluetooth_printer_kb.md").read_text(encoding="utf-8")
    td630 = (ROOT / "printernoble_td630_dot_matrix_kb.md").read_text(encoding="utf-8")
    videos = (ROOT / "qianniu_video_materials_kb.md").read_text(encoding="utf-8")
    driver = (ROOT / "dot_matrix_windows_usb_driver_install_kb.md").read_text(encoding="utf-8")
    assert "完全关闭并重新打开打印软件" in after_sales
    assert "取出纸张" in after_sales
    assert "重新装入" in after_sales
    assert "撕掉色带上的透明保护膜" in after_sales
    assert "速印通" in wifi and "Grozziie.apk" in wifi
    assert "相邻孔中心距约0.5英寸" in td630
    assert "505903251902" in videos
    assert "不需要先升级打印机固件" in driver
