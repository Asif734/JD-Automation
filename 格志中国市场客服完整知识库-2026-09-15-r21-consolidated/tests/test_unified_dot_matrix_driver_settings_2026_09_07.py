from __future__ import annotations

import json
from pathlib import Path

from scripts.build_source_chunks import classify_product_line
from scripts.package_grozziie_china_kb import collect_package_files
from scripts.search_rag import search


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "confirmed_unified_dot_matrix_driver_settings_2026_09_07_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
INDEX = ROOT / "rag_index/customer_service_rag_index.json"


def load_cards() -> dict[str, dict]:
    return {
        item["id"]: item
        for item in (
            json.loads(line)
            for line in CARDS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }


def test_canonical_source_contains_exact_verified_driver_options() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    for required in [
        "控制面板 → 硬件和声音 → 设备和打印机",
        "Layout",
        "Paper/Quality",
        "Configure",
        "A4: 240mm*297.4",
        "S1: 240mm*93.1mm",
        "S2: 240mm*139.7mm",
        "S3: 240mm*101.6mm",
        "S4: 240mm*279.4mm",
        "DPI:720*720",
        "DPI:180*144",
        "Dither",
        "error diffusion",
        "grayscale",
        "93.1mm(holes 22/3)",
        "101.6mm(holes 8)",
        "127mm(holes 10)",
        "139.7mm(holes 11)",
        "279.4mm(holes 22)",
        "-20mm 至 +20mm",
        "+2mm 至 +20mm",
        "-2mm 至 -20mm",
    ]:
        assert required in text


def test_source_preserves_unverified_ui_boundaries() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    assert "不得编造 Paper/Quality" in text
    assert "未展开的下拉选项" in text
    assert "至少 -15mm 至 +20mm" in text
    assert "不能把下限写死" in text


def test_rear_feed_workflow_names_each_checkbox_and_preserves_one_way() -> None:
    cards = load_cards()
    card = cards["dot_matrix_fixed_page_height_exact_path"]
    reply = card["reply_template"]
    for required in [
        "固定页面高度",
        "删除页面底部空白",
        "删除左边空白页",
        "删除页面顶部空白",
        "将位图图像输出到计算机",
        "纸边孔长计算",
        "单向打印保持原设置",
        "完全关闭并重新打开打印软件",
        "取出纸张",
        "重新装入",
    ]:
        assert required in reply
    assert "只保留第一个选项" not in reply
    assert card["models"] == ["TD630", "TD630G", "AK915", "TG890", "支持后进连续纸的针式打印机"]


def test_position_tear_off_and_speed_cards_use_verified_controls() -> None:
    cards = load_cards()
    offset = cards["dot_matrix_unified_driver_offset"]["reply_template"]
    assert "Horizontal adjustment" in offset
    assert "Vertical position adjustment" in offset
    assert "1mm" in offset

    tear = cards["dot_matrix_tear_position_correct_setup"]["reply_template"]
    assert "tear-off position" in tear
    assert "2mm" in tear
    assert "自动撕纸模式" in tear

    speed = cards["dot_matrix_unified_driver_speed"]["reply_template"]
    assert "DPI:180*144" in speed
    assert "取消勾选单向打印" in speed
    assert "完全关闭并重新打开打印软件" in speed
    assert "取出纸张" in speed and "重新装入" in speed

    ghosting = cards["dot_matrix_horizontal_ghosting_black_line"]["reply_template"]
    assert "勾选单向打印" in ghosting
    assert "高速打印" not in ghosting


def test_unified_scope_keeps_hardware_feed_boundaries() -> None:
    cards = load_cards()
    scope = cards["dot_matrix_unified_driver_navigation"]["reply_template"]
    assert "USB、Wi-Fi和蓝牙" in scope
    assert "机型本身的进纸能力" in scope
    rear = cards["dot_matrix_fixed_page_height_refeed"]
    assert rear["models"] == ["TD630", "TD630G", "AK915", "TG890", "支持后进连续纸的针式打印机"]
    assert "AK910" not in rear["models"]


def test_no_invention_card_and_retrieval_queries_are_present() -> None:
    cards = load_cards()
    boundary = cards["dot_matrix_unified_driver_no_invention"]
    assert boundary["auto_reply_allowed"] is False
    assert "Paper/Quality" in boundary["reply_template"]
    assert "未展示" in boundary["reply_template"]

    index = json.loads(INDEX.read_text(encoding="utf-8"))
    expected = {
        "Windows针式打印机驱动设置在哪里": "dot_matrix_unified_driver_navigation",
        "针式打印机整页偏右怎么调": "dot_matrix_unified_driver_offset",
        "连续纸只差几毫米到撕纸线怎么调": "dot_matrix_tear_position_correct_setup",
        "针式打印机怎么降低DPI提高速度": "dot_matrix_unified_driver_speed",
    }
    for query, card_id in expected.items():
        assert search(index, query, top_k=1)[0]["id"] == card_id


def test_dot_matrix_source_classification_beats_incidental_thermal_word() -> None:
    assert classify_product_line(
        "printernoble_td630_dot_matrix_kb.md",
        "针式打印机声音会比热敏打印机大",
    ) == "dot_matrix_printer"


def test_evidence_and_new_source_are_in_package_payload() -> None:
    relative = {path.relative_to(ROOT).as_posix() for path in collect_package_files(ROOT)}
    assert "confirmed_unified_dot_matrix_driver_settings_2026_09_07_kb.md" in relative
    assert "sources/user_uploads/dot_matrix_driver_settings/unified_dot_matrix_driver_settings_2026_09_07.pdf" in relative
    assert "sources/user_uploads/dot_matrix_driver_settings/unified_dot_matrix_driver_settings_screen_recording_2026_09_07.mp4" in relative
