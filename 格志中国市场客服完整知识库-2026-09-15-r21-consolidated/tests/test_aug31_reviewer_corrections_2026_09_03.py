from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SEARCH = ROOT / "scripts" / "search_rag.py"


def search(query: str) -> list[dict]:
    result = subprocess.run(
        [sys.executable, str(SEARCH), query, "--json", "--top-k", "3"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout)


def top(query: str) -> dict:
    return search(query)[0]


def test_handwritten_receipt_routes_to_invoice_policy() -> None:
    card = top("手写收据有吗")
    assert card["id"] == "global_invoice_high_risk"
    assert "不提供手写收据" in card["reply_template"]
    assert "订单页" in card["reply_template"]
    assert "专票" in card["reply_template"]


def test_standard_pharmacy_form_is_confirmed_from_photo_without_remeasurement() -> None:
    card = top("药房这种标准二等分多联连续纸能打吗")
    assert card["id"] == "dot_matrix_standard_paper_photo_compatibility"
    assert "可以打印" in card["reply_template"]
    assert "无需重复测量" in card["reply_template"]


def test_general_paper_compatibility_contains_approved_market_coverage() -> None:
    card = top("用什么样规格的打印纸")
    assert card["id"] == "dot_matrix_package_test_paper_layers"
    text = card["reply_template"]
    for value in ("95%", "100–241mm", "0.45mm", "长度不限", "1–6联"):
        assert value in text


def test_progressive_page_shift_prioritizes_hole_count_and_actual_division() -> None:
    card = top("第一张正常第二张跨页且连续打印逐张偏移")
    assert card["id"] == "dot_matrix_standard_bisection_fixed_page_height"
    text = card["reply_template"]
    assert "数孔" in text
    assert "整张" in text and "二等分" in text


def test_mobile_preview_default_paper_requires_document_reselection() -> None:
    card = top("手机端点击打印预览没有反应")
    assert card["id"] == "suyintong_keep_aspect_default_paper"
    text = card["reply_template"]
    assert "孔数" in text
    assert "返回" in text and "重新选择文档" in text


def test_mobile_thick_smudged_print_uses_real_contrast_control_only() -> None:
    card = top("手机打印字体太粗送货单发花")
    assert card["id"] == "suyintong_mobile_thick_smudged_contrast"
    assert "对比度" in card["reply_template"]
    assert "图像增强" not in card["reply_template"]


def test_bisection_and_full_sheet_use_exact_confirmed_heights() -> None:
    card = top("这种二等分连续纸可以打印吗")
    text = card["reply_template"]
    assert "139.7mm" in text and "11" in text
    assert "279.4mm" in text and "22" in text
    assert "137.5" not in text and "275mm" not in text


def test_normal_noise_does_not_invent_quiet_mode_or_pad() -> None:
    card = top("这个针式打印机也太响了吧")
    assert card["id"] == "dot_matrix_td630_normal_speed_noise"
    text = card["reply_template"]
    assert "没有静音" in text
    assert "防震垫" not in text


def test_tutorial_request_does_not_volunteer_wechat() -> None:
    card = top("这个操作搞不懂有教学视频吗")
    assert card["id"] == "dot_matrix_operation_tutorial_request"
    assert "微信" not in card["reply_template"]


def test_third_party_blank_print_does_not_recommend_cloud_box() -> None:
    card = top("第三方开单App打印空白买云盒可以吗")
    assert card["id"] == "suyintong_third_party_blank_cloud_box"
    text = card["reply_template"]
    assert "不建议购买云盒" in text
    assert "空白" in text and "乱码" in text and "速印通" in text


def test_template_creation_intent_offers_template_service() -> None:
    card = top("帮我把这个送货单版式做成可编辑打印的模板")
    assert card["id"] == "dot_matrix_two_free_templates"
    text = card["reply_template"]
    assert "可以" in text and "制作" in text
    assert "纸张照片" in text and "尺寸" in text


def test_approved_freight_reimbursement_collects_account_then_handoffs() -> None:
    card = top("已经承诺退我14元运费怎么处理")
    assert card["id"] == "approved_freight_reimbursement_handoff"
    text = card["reply_template"]
    assert "经济型快递" in text and "凭证" in text and "人工客服" in text
    assert "到付" in text and "顺丰" in text and "上限" in text


def test_form_size_reply_avoids_unsolicited_copy_allocation() -> None:
    card = top("出库单打印纸买多大尺寸几联")
    text = card["reply_template"]
    assert "按需求选择联数" in text
    assert "仓库" not in text and "财务" not in text


def test_iphone_enter_values_routes_to_builtin_template() -> None:
    card = top("苹果13手机输入内容然后打印这种单子")
    assert card["id"] == "suyintong_template_inventory_records"
    text = card["reply_template"]
    assert "内置模板" in text
    assert "帮您制作" in text


def test_speed_only_reply_uses_bidirectional_without_ghosting_warning() -> None:
    card = top("打印速度怎么调在App里设置吗")
    text = card["reply_template"]
    assert "双向打印" in text
    assert "重影" not in text


def test_shutdown_during_printing_routes_to_firmware_then_factory() -> None:
    card = top("针式打印机打印到一半突然关机")
    assert card["id"] == "dot_matrix_red_light_shutdown_builtin_power"
    text = card["reply_template"]
    assert "自检页" in text and "固件版本" in text
    assert "升级" in text and "返厂维修" in text


def test_head_moves_without_strike_sound_routes_to_printhead_maintenance() -> None:
    card = top("正常走纸打印头也移动但没有针打声也不打印")
    assert card["id"] == "dot_matrix_blank_pages_spool_document_usb"
    text = card["reply_template"]
    assert "USB" in text and "隐藏打印任务" in text
    assert "打印头故障" in text and "申请维修" in text


def test_torn_ribbon_uses_second_copy_printhead_check() -> None:
    card = top("色带磨破起白点并扭转怎么处理")
    assert card["id"] == "dot_matrix_ribbon_install"
    text = card["reply_template"]
    assert "取下色带" in text and "多联纸" in text and "第二联" in text
    assert "没有横线" in text and "更换色带" in text


def test_clear_consistent_white_line_routes_directly_to_factory_repair() -> None:
    card = top("多条竖线在同一高度固定断开有一条水平白线")
    assert card["id"] == "dot_matrix_fixed_white_line_multipart_confirmation"
    text = card["reply_template"]
    assert "打印头针断裂" in text
    assert "直接" in text and "返厂维修" in text


def test_bent_white_cable_is_normal_and_jam_uses_second_copy_check() -> None:
    card = top("打印机内白色宽排线弯曲并且卡纸")
    assert card["id"] == "dot_matrix_paper_jam_lever_position_6"
    text = card["reply_template"]
    assert "白色宽排线弯曲是正常的" in text
    assert "最高" in text and "取下色带" in text and "第二联" in text
    assert "返厂维修" in text


def test_iphone_connection_is_bluetooth_first_unless_wifi_requested() -> None:
    card = top("苹果手机连不上针式打印机怎么连接")
    assert card["id"] == "dot_matrix_td630g_iphone_wifi_app"
    text = card["reply_template"]
    assert "优先使用蓝牙" in text
    assert "iPhone" in text and "Android" in text
    assert "客户明确要求Wi-Fi" in text
