from __future__ import annotations

import json
from pathlib import Path

from scripts.search_rag import search


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "confirmed_dot_matrix_updates_2026_08_25_morning_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards/high_frequency_queries.json"
INDEX = ROOT / "rag_index/customer_service_rag_index.json"


NEW_CARD_IDS = {
    "dot_matrix_cold_acclimation_condensation",
    "dot_matrix_delivery_template_precision",
    "dot_matrix_template_font_border_layout",
    "dot_matrix_red_light_shutdown_builtin_power",
    "dot_matrix_garbled_spool_usb_os_driver",
    "dot_matrix_upside_down_duplicate_print_settings",
    "dot_matrix_thick_table_lines_settings",
    "dot_matrix_smear_missing_text_ribbon_font",
    "dot_matrix_blank_pages_spool_document_usb",
    "dot_matrix_speed_rear_app_ribbon_combined",
}


EXAMPLES = {
    "东北的冬天非常冷机器怕冻吗冷冻之后拿到常温下会正常使用吗": "dot_matrix_cold_acclimation_condensation",
    "请按图片做一张送货清单表格": "dot_matrix_delivery_template_precision",
    "怎么可以连着打印这个连续纸安装正确了吗": "dot_matrix_model_feed_modes",
    "打印速度怎么调节后进纸怎么放手机要下载什么APP色带用什么型号": "dot_matrix_speed_rear_app_ribbon_combined",
    "模板设置成图片可以打印吗": "dot_matrix_page_too_black_reduce_density",
    "从第四行开始字变小了第四第五行怎么改大": "dot_matrix_template_font_border_layout",
    "这个打出来为什么只有零散点和不完整线条": "suyintong_reduce_contrast_dark_print",
    "亮红灯后自动关机": "dot_matrix_red_light_shutdown_builtin_power",
    "原包装箱已经破损快递说换包装要加30多元怎么处理": "tmall_invoice_return_dot_matrix",
    "打印出现乱码重叠和多余字符怎么处理": "dot_matrix_garbled_spool_usb_os_driver",
    "打印内容上下颠倒重复并重叠怎么处理": "dot_matrix_upside_down_duplicate_print_settings",
    "打印的表格线太粗": "dot_matrix_thick_table_lines_settings",
    "打印有黑色拖痕并且局部文字缺失": "dot_matrix_smear_missing_text_ribbon_font",
    "表格竖线压到下方说明文字版面不对": "dot_matrix_template_font_border_layout",
    "字体有横向重影像重复打印": "dot_matrix_fixed_white_line_multipart_confirmation",
    "打印位置不对内容跑到第二页面": "dot_matrix_print_offset",
    "打印出来有很多点点": "suyintong_reduce_contrast_dark_print",
    "打印有拖痕": "dot_matrix_smear_missing_text_ribbon_font",
    "打印机一直出空白纸": "dot_matrix_blank_pages_spool_document_usb",
    "打印有乱码视频和截图": "dot_matrix_garbled_spool_usb_os_driver",
    "色带散开并缠在打印头附近怎么处理": "dot_matrix_ribbon_install",
    "走纸组件拆出来后打印严重拖黑怎么处理": "dot_matrix_smear_missing_text_ribbon_font",
    "单据部分行字迹变浅或缺印": "dot_matrix_fixed_white_line_multipart_confirmation",
    "打印机不开机视频": "dot_matrix_no_power_top_button",
    "视频中机器只走空白纸这是按进纸键还是发送了打印任务": "dot_matrix_feed_sensor",
    "打印出现一整列重复的圆圈8字符": "dot_matrix_loud_noise_printhead_stuck",
    "无故大量吐纸不关机停不下来": "dot_matrix_feed_sensor",
    "打印位置不对内容只在左侧右侧大面积空白": "dot_matrix_print_offset",
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


def test_source_contains_confirmed_morning_boundaries() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    for value in [
        "行高、列宽和字体大小",
        "左右两侧各三个孔",
        "降低打印质量或分辨率/DPI",
        "没有外接电源适配器",
        "包装费用不由店铺承担",
        "输入 `SPOOL`",
        "灰度阈值",
        "USB 单一连接版本",
        "重复圆圈或“8”字符",
    ]:
        assert value in text


def test_new_cards_active_unique_and_mapped() -> None:
    cards = load_cards()
    assert NEW_CARD_IDS <= cards.keys()
    assert all(cards[card_id]["status"] == "active" for card_id in NEW_CARD_IDS)
    ids = [json.loads(line)["id"] for line in CARDS.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert len(ids) == len(set(ids))
    mapped = {item["card_id"] for item in json.loads(HF.read_text(encoding="utf-8"))["queries"]}
    assert NEW_CARD_IDS <= mapped


def test_corrected_power_and_usb_self_test_boundaries() -> None:
    cards = load_cards()
    assert "没有外接适配器" in cards["dot_matrix_outdoor_power_800w"]["reply_template"]
    assert "USB单一连接版本没有本机自检功能" in cards["dot_matrix_blank_pages_spool_document_usb"]["reply_template"]
    assert "USB单一连接版本没有本机自检功能" in cards["dot_matrix_loud_noise_printhead_stuck"]["reply_template"]
    assert "包装费用不由店铺承担" in cards["tmall_invoice_return_dot_matrix"]["reply_template"]


def test_all_28_workbook_queries_resolve() -> None:
    index = json.loads(INDEX.read_text(encoding="utf-8"))
    for query, card_id in EXAMPLES.items():
        assert search(index, query, top_k=1)[0]["id"] == card_id
