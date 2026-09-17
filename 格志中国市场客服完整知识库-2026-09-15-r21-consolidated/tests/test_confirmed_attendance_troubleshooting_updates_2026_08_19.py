from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
SOURCE = ROOT / "confirmed_attendance_troubleshooting_updates_2026_08_19_kb.md"


def load_cards() -> dict[str, dict]:
    return {
        card["id"]: card
        for card in (json.loads(line) for line in CARDS.read_text(encoding="utf-8").splitlines() if line.strip())
    }


def test_absorbed_ejected_card_uses_symptom_specific_temporary_settings() -> None:
    card = load_cards()["attendance_card_absorbed_ejected_no_print"]
    assert card["rules"]["normal_original_card_group_15"] == "01"
    assert card["rules"]["symptom_test_group_15"] == "00"
    assert card["rules"]["temporary_group_09"] == "00:00"
    assert card["rules"]["group_09_range"] == "00:00-05:59"
    assert card["rules"]["restore_group_09_after_test"] is True


def test_5004_is_error_code_with_confirmed_safety_boundary() -> None:
    card = load_cards()["attendance_error_5004_printhead_stuck"]
    assert card["diagnosis"] == "printhead_stuck_or_cannot_move"
    assert "不是时间" in card["reply_template"]
    assert "通电时不要触摸" in card["reply_template"]
    assert "清除异物前关机拔电" in card["safety"]


def test_mixed_red_black_is_abnormal_single_imprint() -> None:
    card = load_cards()["attendance_single_imprint_mixed_red_black"]
    assert "同一印迹红黑混色属于异常" in card["reply_template"]
    assert "install_between_printhead_and_stainless_plate" in [item["type"] for item in card["actions"]]


def test_fixed_white_line_routes_to_repair_after_original_card_self_test() -> None:
    card = load_cards()["attendance_print_white_line_fixed_missing_band"]
    assert "原装卡自检" in card["reply_template"]
    assert "完全相同位置" in card["reply_template"]
    assert "维修" in card["escalation"]


def test_card_feed_rule_separates_manual_and_automatic_modes() -> None:
    card = load_cards()["attendance_card_not_inserted_or_auto_feed"]
    action_types = [item["type"] for item in card["actions"]]
    assert "manual_mode_select_column_1_to_6_and_wait_for_cursor" in action_types
    assert "check_groups_02_to_08_in_auto_mode" in action_types
    assert card["self_test_key"] == "1号/+增加键（同一个按键）"
    assert "00:00–05:59" in card["reply_template"]


def test_authoritative_source_contains_all_five_questions() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    for marker in ["## Q1", "## Q2", "## Q3", "## Q4", "## Q5"]:
        assert marker in text
    assert "`5004` 是错误代码，不是时间" in text
    assert "取下透明上盖本身不强制要求断电" in text
    assert "`09组` 只能在 `00:00–05:59` 之间调整" in text
