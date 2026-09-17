from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARDS = ROOT / "rag_cards" / "customer_service_rag_cards.jsonl"
SEARCH = ROOT / "scripts" / "search_rag.py"


def cards_by_id() -> dict[str, dict]:
    return {
        item["id"]: item
        for item in (
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


def test_confirmed_source_records_all_review_boundaries() -> None:
    source = ROOT / "confirmed_dot_matrix_tencent_review_updates_2026_09_07_kb.md"
    text = source.read_text(encoding="utf-8")
    for phrase in (
        "200W",
        "正确设置纸张规格并正确进纸",
        "D-label",
        "TH880仅支持USB",
        "13%",
        "一般纳税人",
        "完全关闭并重新打开",
        "前后两个感应器",
    ):
        assert phrase in text


def test_power_tear_and_dlabel_cards_use_confirmed_rules() -> None:
    cards = cards_by_id()
    power = cards["dot_matrix_outdoor_power_800w"]
    assert "200W" in power["reply_template"]
    assert "800W" not in power["reply_template"]
    assert "300Wh" not in power["reply_template"]

    tear = cards["dot_matrix_tear_position_correct_setup"]
    assert "纸张规格" in tear["reply_template"]
    assert "正确进纸" in tear["reply_template"]
    assert "自动" in tear["reply_template"]

    dlabel = cards["dot_matrix_dlabel_thermal_boundary"]
    assert "热敏标签打印机" in dlabel["reply_template"]
    assert "通常不用于针式打印机" in dlabel["reply_template"]


def test_invoice_th880_wifi_and_multi_pc_are_corrected() -> None:
    cards = cards_by_id()
    invoice = cards["global_invoice_high_risk"]["reply_template"]
    assert "13%" in invoice and "一般纳税人" in invoice
    for field in ("公司名称", "税号", "开户银行", "银行账号", "公司地址", "电话"):
        assert field in invoice

    th880 = cards["th880_driver_install_error_details"]["reply_template"]
    assert "仅支持USB" in th880
    assert "USB/Wi-Fi" not in th880

    multi = cards["dot_matrix_td630g_windows_multi_pc_wifi"]["reply_template"]
    assert "Automatic" in multi and "自动识别IP端口" in multi
    assert "Standard TCP/IP" not in multi


def test_templates_freight_driver_and_package_damage_are_complete() -> None:
    cards = cards_by_id()
    templates = cards["suyintong_multiple_phones_templates"]["reply_template"]
    assert "客服后台" in templates
    assert "申请过模板" in templates and "订单编号" in templates

    freight = cards["approved_freight_reimbursement_handoff"]["reply_template"]
    for phrase in ("经济型快递", "到付", "顺丰", "凭证", "上限", "人工客服"):
        assert phrase in freight

    assert "光盘" in cards["dot_matrix_driver_no_disc_usb"]["reply_template"]
    assert "U盘" in cards["dot_matrix_driver_no_disc_usb"]["reply_template"]
    assert "外包装" in cards["dot_matrix_package_damage_inspect_test"]["reply_template"]


def test_layout_feed_blank_print_and_mobile_state_rules() -> None:
    cards = cards_by_id()
    layout = cards["dot_matrix_print_offset"]["reply_template"]
    for phrase in ("左右0.3", "上下0.5", "页眉页脚为0", "水平居中", "垂直居中"):
        assert phrase in layout

    front = cards["dot_matrix_feed_sensor"]["reply_template"]
    assert "不需要按进纸键" in front and "取下色带" in front
    tg690 = cards["dot_matrix_tg690_dual_sensor_cleaning"]["reply_template"]
    assert "前后两个感应器" in tg690

    blank = cards["dot_matrix_blank_pages_spool_document_usb"]["reply_template"]
    assert "Windows测试页" in blank and "取下色带" in blank

    state = cards["suyintong_connection_state_switching"]["reply_template"]
    assert "自动重新连接" in state and "切换设备" in state
    paths = cards["suyintong_saved_file_template_paths"]["reply_template"]
    assert "文档打印" in paths and "模板" in paths


def test_key_queries_retrieve_new_cards() -> None:
    expected = {
        "车里使用针式打印机逆变器要多大功率": "dot_matrix_outdoor_power_800w",
        "连续纸怎么自动到撕纸位置": "dot_matrix_tear_position_correct_setup",
        "D-label能给针式打印机打多联标签吗": "dot_matrix_dlabel_thermal_boundary",
        "TG690后进纸反复退出又吸入": "dot_matrix_tg690_dual_sensor_cleaning",
        "手机重启后速印通还要重新选择打印机吗": "suyintong_connection_state_switching",
        "速印通保存的文件和模板在哪里": "suyintong_saved_file_template_paths",
        "外包装有点破是不是打印机也坏了": "dot_matrix_package_damage_inspect_test",
    }
    for query, card_id in expected.items():
        assert top(query)["id"] == card_id
