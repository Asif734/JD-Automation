from __future__ import annotations

import json
from pathlib import Path

from scripts.search_rag import search


ROOT = Path(__file__).resolve().parents[1]
CARDS_PATH = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
INDEX_PATH = ROOT / "rag_index/customer_service_rag_index.json"


NEW_CARD_IDS = {
    "dot_matrix_tear_off_second_title_alignment",
    "printer_brand_verify_customer_service_disabled",
    "suyintong_default_textbox_double_click_delete",
    "dot_matrix_front_feed_paper_slider_width",
    "dot_matrix_template_row_count_full_length_22_hole",
    "dot_matrix_bluetooth_mac_device_not_driver",
    "suyintong_missing_strokes_lines_preview_font_contrast",
    "dot_matrix_printhead_lost_sync_alignment_maintenance",
    "dot_matrix_continuous_black_line_stuck_pin_repair",
    "dot_matrix_preprinted_form_precise_alignment",
    "dot_matrix_paper_damage_flat_paper",
    "dot_matrix_mid_print_stop_usb_sensor_queue",
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


def test_new_review_cards_are_active_and_retrievable() -> None:
    cards = load_cards()
    assert NEW_CARD_IDS <= cards.keys()
    assert all(cards[card_id]["status"] == "active" for card_id in NEW_CARD_IDS)
    assert all(cards[card_id].get("reply_template") for card_id in NEW_CARD_IDS)


def test_existing_cards_follow_confirmed_aug_27_boundaries() -> None:
    cards = load_cards()

    mobile = cards["dot_matrix_td630g_iphone_wifi_app"]["reply_template"]
    assert "系统蓝牙" not in mobile and "直接配对" not in mobile

    feed = cards["dot_matrix_model_feed_modes"]
    assert any("不存在" in item and "进纸" in item for item in feed["do_not_say"])

    garbled = cards["dot_matrix_garbled_spool_usb_os_driver"]["reply_template"]
    assert "打印预览" in garbled
    assert all(term in garbled for term in ["SPOOL", "USB", "系统", "驱动"])

    fixed_white = cards["dot_matrix_fixed_white_line_multipart_confirmation"]
    assert "打印头针断裂" in fixed_white["reply_template"]
    assert "直接" in fixed_white["reply_template"]
    assert "返厂维修" in fixed_white["escalation"]

    mac = cards["dot_matrix_td630g_mac_usb_only"]
    assert "TD630" in mac["models"] and "TD630G" in mac["models"]
    assert "https://zjweiting.com/nobel/apk/MacDriver.pkg" in mac["reply_template"]
    assert mac["reply_template"].index("安装") < mac["reply_template"].index("添加")

    no_power = cards["dot_matrix_no_power_top_button"]
    assert "长按电源按钮" in no_power["reply_template"]


def test_new_cards_preserve_the_confirmed_customer_service_meaning() -> None:
    cards = load_cards()
    assert "声音属于正常" in cards["dot_matrix_tear_off_second_title_alignment"]["reply_template"]
    assert "不需要打印测试页" in cards["dot_matrix_tear_off_second_title_alignment"]["reply_template"]
    assert "购买平台" in cards["printer_brand_verify_customer_service_disabled"]["reply_template"]
    assert "默认文字" in cards["suyintong_default_textbox_double_click_delete"]["reply_template"]
    assert "纸张宽度" in cards["dot_matrix_front_feed_paper_slider_width"]["reply_template"]
    assert "22孔" in cards["dot_matrix_template_row_count_full_length_22_hole"]["reply_template"]
    assert "蓝牙MAC地址" in cards["dot_matrix_bluetooth_mac_device_not_driver"]["reply_template"]
    assert "线条粗细" in cards["suyintong_missing_strokes_lines_preview_font_contrast"]["reply_template"]
    assert "失步" in cards["dot_matrix_printhead_lost_sync_alignment_maintenance"]["reply_template"]
    assert "卡在伸出位置" in cards["dot_matrix_continuous_black_line_stuck_pin_repair"]["reply_template"]
    assert "水平和垂直偏移" in cards["dot_matrix_preprinted_form_precise_alignment"]["reply_template"]
    assert "平整" in cards["dot_matrix_paper_damage_flat_paper"]["reply_template"]
    assert "USB接口" in cards["dot_matrix_mid_print_stop_usb_sensor_queue"]["reply_template"]


def test_review_image_summaries_route_to_confirmed_cards() -> None:
    index = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    examples = {
        "撕下连续纸后第二份标题打印在撕纸线上而且进纸声音较大": "dot_matrix_tear_off_second_title_alignment",
        "网站提示输入打印机品牌但不知道品牌或型号怎么填": "printer_brand_verify_customer_service_disabled",
        "连续纸正常走纸但内容只打印右半边预览分成两页": "dot_matrix_print_offset",
        "手机APP一直正在搜索找不到打印机": "wifi_search_device_not_found",
        "连续纸连着打印但机器没有连续纸链式进纸选择开关": "dot_matrix_model_feed_modes",
        "打印大量重复字符横线和重叠文字乱码": "dot_matrix_garbled_spool_usb_os_driver",
        "模板打印出Double click here但原内容没有": "suyintong_default_textbox_double_click_delete",
        "前进纸纸张滑块应该推到哪个位置": "dot_matrix_front_feed_paper_slider_width",
        "14行模板要改成30行并使用22孔全长纸": "dot_matrix_template_row_count_full_length_22_hole",
        "Windows打印机选项只有带字母数字后缀的蓝牙设备没有驱动": "dot_matrix_bluetooth_mac_device_not_driver",
        "手机APP预览中表格线不显示打印缺笔画": "suyintong_missing_strokes_lines_preview_font_contrast",
        "车间多部手机连接打印机是否需要断开其他手机": "suyintong_multiple_phones_templates",
        "TD630苹果电脑怎么下载Mac驱动并添加打印机": "dot_matrix_td630g_mac_usb_only",
        "单据顶部打印黑色背景方框和不清楚图片": "dot_matrix_page_too_black_reduce_density",
        "每一行向右错开右侧对不齐打印头不同步": "dot_matrix_printhead_lost_sync_alignment_maintenance",
        "纸张左侧多余淡印拖痕色带不平": "dot_matrix_smear_missing_text_ribbon_font",
        "每行固定缺印形成白线需要看多联纸第二联": "dot_matrix_fixed_white_line_multipart_confirmation",
        "整张表格有一条连续黑线压过文字和表格线": "dot_matrix_continuous_black_line_stuck_pin_repair",
        "预印表格只填指定框但文字没有对准格子": "dot_matrix_preprinted_form_precise_alignment",
        "打印时纸张被刮破纸张弯曲起皱": "dot_matrix_paper_damage_flat_paper",
        "打印到一半停止纸停在后面USB连接不稳定": "dot_matrix_mid_print_stop_usb_sensor_queue",
        "按进纸键一次吐出太多后进连续纸": "dot_matrix_feed_sensor",
        "打印文字每行固定缺失形成白线": "dot_matrix_fixed_white_line_multipart_confirmation",
        "连续纸倾斜拱起卡住需要纸厚扳手最高档": "dot_matrix_paper_jam_lever_position_6",
    }
    for query, card_id in examples.items():
        assert search(index, query, top_k=1)[0]["id"] == card_id
