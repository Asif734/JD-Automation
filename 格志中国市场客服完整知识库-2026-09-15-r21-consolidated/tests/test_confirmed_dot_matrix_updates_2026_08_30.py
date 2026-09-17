from __future__ import annotations

import json
from pathlib import Path

from scripts.search_rag import search


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "confirmed_dot_matrix_updates_2026_08_30_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards/high_frequency_queries.json"
INDEX = ROOT / "rag_index/customer_service_rag_index.json"


NEW_CARD_IDS = {
    "dot_matrix_faint_second_copy_carbon_side",
    "dot_matrix_table_small_margins_header_footer",
    "suyintong_third_party_order_app_template",
    "wifi_special_invoice_order_request",
    "suyintong_mobile_logo_document_quality",
    "dot_matrix_n_up_pages_per_sheet",
    "suyintong_mobile_dark_thick_contrast_lever",
    "th880_driver_install_error_details",
    "dot_matrix_front_feed_restart_auto_eject",
    "dot_matrix_faint_after_jam_restore_lever",
    "dot_matrix_carbonless_copy_blue_normal",
    "dot_matrix_qr_code_template_size",
    "dot_matrix_horizontal_ghosting_black_line",
    "dot_matrix_standard_bisection_fixed_page_height",
}


EXAMPLES = {
    "第二张复写颜色不够深怎么判断连续纸正反面": "dot_matrix_faint_second_copy_carbon_side",
    "打印出来的表格很小四周留白很大": "dot_matrix_table_small_margins_header_footer",
    "打印机突然没电换了正常电源还是不开机": "dot_matrix_no_power_top_button",
    "速印通登录页面怎么样快速操作": "suyintong_account_password_guest",
    "别的开单app能不能用手机打印": "suyintong_third_party_order_app_template",
    "电脑打印颜色深度能不能调": "dot_matrix_density_dpi_location",
    "二维码连接wifi并申请订单增值税专票": "wifi_special_invoice_order_request",
    "打印不完整右侧表格被截断": "dot_matrix_print_offset",
    "手机打印单据文字发糊二维码黑块logo不清楚": "suyintong_mobile_logo_document_quality",
    "四个页面被缩小打印在同一张纸上": "dot_matrix_n_up_pages_per_sheet",
    "手机打印文字和表格太厚太黑": "suyintong_mobile_dark_thick_contrast_lever",
    "TH880无法安装打印机驱动程序安装器报错": "th880_driver_install_error_details",
    "手机打印文字表格线过粗发黑字符粘连": "suyintong_mobile_dark_thick_contrast_lever",
    "前进纸装着纸开机自动吐纸不能退纸": "dot_matrix_front_feed_restart_auto_eject",
    "手机打印时纸张卡住歪斜撕裂": "dot_matrix_paper_jam_lever_position_6",
    "处理卡纸后整页字迹很浅点阵断续": "dot_matrix_faint_after_jam_restore_lever",
    "原文件灰色背景打印成黑块": "dot_matrix_page_too_black_reduce_density",
    "多联复写纸下联字迹呈蓝色": "dot_matrix_carbonless_copy_blue_normal",
    "前进连续纸打印时出现空白页": "dot_matrix_blank_pages_spool_document_usb",
    "AK910JMS任务显示打印错误不打印": "dot_matrix_no_print_offline_queue",
    "打印时出现贯穿页面的多条连续横线": "dot_matrix_continuous_black_line_stuck_pin_repair",
    "打印机连续送出很长的空白连续纸": "dot_matrix_feed_sensor",
    "发票预览偏右打印位置不对": "dot_matrix_print_offset",
    "打印内容严重压缩错位重叠而且横向不直": "dot_matrix_printhead_lost_sync_alignment_maintenance",
    "打印的二维码太小只有二维码需要放大": "dot_matrix_qr_code_template_size",
    "打印文字表格竖线横向重影并有连续黑线": "dot_matrix_horizontal_ghosting_black_line",
    "色带松脱扭曲堆积在打印头旁": "dot_matrix_ribbon_install",
    "按进纸键后大量走纸随后整张退回": "dot_matrix_feed_sensor",
    "二等分连续纸打印位置不对页面高度不匹配": "dot_matrix_standard_bisection_fixed_page_height",
    "色带收紧后打印几行又变松": "dot_matrix_ribbon_install",
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


def test_aug_30_cards_are_active_unique_and_mapped() -> None:
    cards = load_cards()
    assert NEW_CARD_IDS <= cards.keys()
    assert all(cards[card_id]["status"] == "active" for card_id in NEW_CARD_IDS)
    ids = [json.loads(line)["id"] for line in CARDS.read_text(encoding="utf-8").splitlines() if line.strip()]
    assert len(ids) == len(set(ids))
    mapped = {item["card_id"] for item in json.loads(HF.read_text(encoding="utf-8"))["queries"]}
    assert NEW_CARD_IDS <= mapped


def test_aug_30_mobile_invoice_feed_and_ribbon_boundaries() -> None:
    cards = load_cards()

    mobile = cards["suyintong_mobile_dark_thick_contrast_lever"]["reply_template"]
    assert "对比度" in mobile and "第 6 档" in mobile
    assert "按实际打印效果" in mobile
    assert "位置2" not in mobile
    assert all(term not in mobile for term in ["灰度阈值", "DPI", "浓度"])
    assert "彩色" in mobile and "黑色" in mobile

    logo = cards["suyintong_mobile_logo_document_quality"]["reply_template"]
    assert "清晰" in logo and "高质量" in logo and "模糊" in logo
    assert "没有直接照片打印功能" not in logo

    invoice = cards["wifi_special_invoice_order_request"]["reply_template"]
    assert all(term in invoice for term in ["公司名称", "税号", "开户银行", "银行账号", "公司地址", "电话", "人工"])

    feed = cards["dot_matrix_front_feed_restart_auto_eject"]["reply_template"]
    assert "前进纸" in feed and "重新进纸" in feed and "后进纸" in feed

    ribbon = cards["dot_matrix_ribbon_install"]["reply_template"]
    assert "收带齿轮打滑" in ribbon and "更换" in ribbon

    no_power = cards["dot_matrix_no_power_top_button"]["reply_template"]
    assert "长按电源按钮" in no_power


def test_aug_30_blank_no_print_and_hardware_diagnosis_boundaries() -> None:
    cards = load_cards()
    blank = cards["dot_matrix_blank_pages_spool_document_usb"]["reply_template"]
    assert "前进纸感应器" in blank and "打印头" in blank and "色带" in blank

    no_print = cards["dot_matrix_no_print_offline_queue"]["reply_template"]
    assert all(term in no_print for term in ["services.msc", "Print Spooler", "端口"])

    ghosting = cards["dot_matrix_horizontal_ghosting_black_line"]["reply_template"]
    assert "双向打印" in ghosting and "连续横向黑线" in ghosting and "打印头" in ghosting

    sensor = cards["dot_matrix_feed_sensor"]
    assert "清洁" in sensor["reply_template"] and "感应器" in sensor["reply_template"]
    assert any("进纸来源选择杆" in text for text in sensor.get("do_not_say", []))


def test_aug_30_source_records_confirmed_customer_service_rules() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    for value in [
        "蓝色复写痕迹可见 = 正面",
        "页眉和页脚设为 0",
        "公司名称、税号和邮箱",
        "最高第 6 档",
        "按实际打印效果",
        "139.7 mm",
        "收带齿轮",
    ]:
        assert value in text
    assert "位置 2" not in text


def test_all_30_aug_30_workbook_scenarios_resolve() -> None:
    index = json.loads(INDEX.read_text(encoding="utf-8"))
    for query, card_id in EXAMPLES.items():
        assert search(index, query, top_k=1)[0]["id"] == card_id
