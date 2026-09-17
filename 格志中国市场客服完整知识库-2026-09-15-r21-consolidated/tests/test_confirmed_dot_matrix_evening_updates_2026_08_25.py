from __future__ import annotations

import json
from pathlib import Path

from scripts.search_rag import search


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "confirmed_dot_matrix_updates_2026_08_25_evening_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards/high_frequency_queries.json"

NEW_CARD_IDS = {
    "dot_matrix_fixed_white_line_multipart_confirmation",
    "dot_matrix_rear_feed_red_light_stuck_printhead",
    "dot_matrix_printhead_hot_continuous_normal_branch",
    "dot_matrix_paper_jam_lever_position_6",
    "dot_matrix_hidden_spool_tasks_stop_resume",
    "dot_matrix_no_power_top_button",
    "suyintong_local_template_save_no_sync",
    "suyintong_excel_word_local_file_path",
    "dot_matrix_chinese_indonesian_bilingual",
    "dot_matrix_no_response_paper_ready_usb_port_match",
    "printer_white_line_product_route",
}


def load_cards() -> dict[str, dict]:
    return {
        item["id"]: item
        for item in (
            json.loads(line)
            for line in CARDS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }


def test_confirmed_source_contains_all_eleven_update_groups() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    for value in [
        "Automatic → 下一步",
        "查看第二联",
        "后进纸感应器",
        "发热通常正常",
        "最高的第 6 档",
        "输入 `SPOOL`",
        "没有 I/O 按钮",
        "不随账号同步",
        "Excel 和 Word",
        "印度尼西亚语",
        "设备端口和驱动端口",
        "客户只说“打印有白线”",
        "蓝牙搜索不到且面板灯全部熄灭",
    ]:
        assert value in text


def test_new_cards_are_active_unique_and_have_actions() -> None:
    cards = load_cards()
    assert NEW_CARD_IDS <= cards.keys()
    assert all(cards[card_id]["status"] == "active" for card_id in NEW_CARD_IDS)
    assert all(cards[card_id].get("actions") for card_id in NEW_CARD_IDS)
    ids = [json.loads(line)["id"] for line in CARDS.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert len(ids) == len(set(ids))


def test_existing_cards_follow_confirmed_driver_and_template_boundaries() -> None:
    cards = load_cards()
    install = cards["windows_usb_driver_install_visual_guide"]["reply_template"]
    phones = cards["suyintong_multiple_phones_templates"]["reply_template"]
    assert "Automatic" in install and "USB" in install
    assert "仅支持USB" in install
    assert "不随账号同步" in phones
    assert "不能转移" in phones


def test_customer_replies_preserve_the_confirmed_scope() -> None:
    cards = load_cards()
    assert "通常是正常现象" in cards["dot_matrix_printhead_hot_continuous_normal_branch"]["reply_template"]
    assert "第6档" in cards["dot_matrix_paper_jam_lever_position_6"]["reply_template"]
    assert "SPOOL" in cards["dot_matrix_hidden_spool_tasks_stop_resume"]["reply_template"]
    no_power = cards["dot_matrix_no_power_top_button"]
    assert "更换一个正常工作的电源插座" in no_power["reply_template"]
    assert "长按电源按钮" in no_power["reply_template"]
    assert "人工客服申请维修" in no_power["reply_template"]
    assert "静置" not in no_power["reply_template"]
    assert len(no_power["actions"]) == 3
    assert "打印头不动" in cards["dot_matrix_loud_noise_printhead_stuck"]["keywords"]
    assert "打四五张打印头就发烫不打印" in cards["dot_matrix_printhead_hot_continuous_normal_branch"]["synonyms"]
    assert "固定白条" not in cards["dot_matrix_ribbon_film_before_missing_pin"]["keywords"]
    assert cards["printer_white_line_product_route"]["intent"] == "clarification"
    assert cards["dot_matrix_chinese_indonesian_bilingual"]["reply_template"] == "可以的，中文和印度尼西亚语可以正常一起打印。"
    no_response = cards["dot_matrix_no_response_paper_ready_usb_port_match"]
    assert "重新放纸" in no_response["do_not_say"]
    assert "测试页" in no_response["reply_template"] and "USB口" in no_response["reply_template"]


def test_high_frequency_queries_cover_every_new_card_and_resolve() -> None:
    hf = json.loads(HF.read_text(encoding="utf-8"))
    index = json.loads((ROOT / "rag_index/customer_service_rag_index.json").read_text(encoding="utf-8"))
    mapped = {item["card_id"] for item in hf["queries"]}
    assert NEW_CARD_IDS <= mapped
    examples = {
        "打印有白线": "printer_white_line_product_route",
        "针式打印机打印有白线": "dot_matrix_fixed_white_line_multipart_confirmation",
        "如何配置驱动已检测到TD630 SZ USB": "windows_usb_driver_install_visual_guide",
        "打印有一条固定白线怎么确认": "dot_matrix_fixed_white_line_multipart_confirmation",
        "打四五张打印头就发烫不打印": "dot_matrix_printhead_hot_continuous_normal_branch",
        "针式打印机打印头不动": "dot_matrix_loud_noise_printhead_stuck",
        "蓝牙搜索不到面板灯全部熄灭": "dot_matrix_no_power_top_button",
        "打印机无法开机": "dot_matrix_no_power_top_button",
        "打印机昨天还能用今天不开机": "dot_matrix_no_power_top_button",
        "my printer is not turning on what do i do it was still working yesterday": "dot_matrix_no_power_top_button",
        "针式打印机局部笔画固定缺失": "dot_matrix_fixed_white_line_multipart_confirmation",
        "打印头动一下停一下再继续": "dot_matrix_hidden_spool_tasks_stop_resume",
        "速印通找不到Excel和Word文件": "suyintong_excel_word_local_file_path",
        "纸张放好缺纸灯没亮但点击打印没反应": "dot_matrix_no_response_paper_ready_usb_port_match",
    }
    for query, card_id in examples.items():
        assert search(index, query, top_k=1)[0]["id"] == card_id


def test_relevant_existing_sources_received_in_place_corrections() -> None:
    after_sales = (ROOT / "dot_matrix_after_sales_issues_kb.md").read_text(encoding="utf-8")
    wifi = (ROOT / "wifi_bluetooth_printer_kb.md").read_text(encoding="utf-8")
    td630 = (ROOT / "printernoble_td630_dot_matrix_kb.md").read_text(encoding="utf-8")
    driver = (ROOT / "dot_matrix_windows_usb_driver_install_kb.md").read_text(encoding="utf-8")
    assert "打开 `printers` 文件夹" in after_sales
    assert "更换一个确认正常工作的电源插座" in after_sales
    assert "转人工客服申请维修" in after_sales
    assert "长按电源按钮尝试开机" in after_sales
    assert "不提供关机静置、检查多条线缆" in after_sales
    assert "不随账号同步" in wifi and "Excel 和 Word" in wifi
    assert "中文和印度尼西亚语" in wifi
    assert "最高的第 6 档" in td630 and "发热通常属于正常现象" in td630
    assert "Automatic" in driver and "仅支持 USB" in driver
