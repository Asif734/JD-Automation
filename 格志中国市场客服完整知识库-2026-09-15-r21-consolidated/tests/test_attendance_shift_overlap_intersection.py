import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _load_card(card_id: str) -> dict:
    path = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
    for line in path.read_text(encoding="utf-8").splitlines():
        card = json.loads(line)
        if card.get("id") == card_id:
            return card
    raise AssertionError(f"missing card: {card_id}")


def test_overlap_card_calculates_shared_shift_intersection():
    card = _load_card("attendance_shift_overlap_intersection")
    calculation = card["calculation"]

    assert card["intersection_sharing_rule"] == "active"
    assert calculation["shared_start"] == "max(各重叠班次上班时间)"
    assert calculation["shared_end"] == "min(各重叠班次下班时间)"
    assert calculation["shared_shift"] == "重叠开始时间-重叠结束时间"
    assert calculation["exists_when"] == "shared_start < shared_end"


def test_final_machine_shifts_keep_30_minute_rule():
    card = _load_card("attendance_shift_overlap_intersection")
    validation = card["validation"]

    assert validation["maximum_shifts"] == 3
    assert validation["maximum_punch_points"] == 6
    assert validation["employee_schedule_overlap_allowed"] is True
    assert validation["final_machine_shift_overlap_allowed"] is False
    assert validation["duplicate_points_allowed"] is False
    assert validation["minimum_adjacent_gap_minutes"] == 30


def test_overlap_reply_explains_machine_limit_and_manual_fallback():
    card = _load_card("attendance_shift_overlap_intersection")
    action_types = [action["type"] for action in card["actions"]]

    assert "机器不能直接输入重叠自动班次" in card["reply_template"]
    assert "相邻至少间隔30分钟" in card["reply_template"]
    assert action_types[0] == "calculate_shared_shift_intersection"
    assert "offer_manual_mode_if_invalid" in action_types


def test_shared_shift_kb_contains_calculation_and_boundaries():
    text = (ROOT / "attendance_shift_overlap_calculation_kb.md").read_text(encoding="utf-8")

    assert "共同班次开始 = max" in text
    assert "共同班次结束 = min" in text
    assert "共享班次 = 09:00–17:00" in text
    assert "机器不能直接输入互相重叠的自动班次" in text
    assert "相邻两个自动班次之间必须至少间隔30分钟" in text
    assert "共同班次只用于机器自动定位" in text


def test_employee_group_card_calculates_then_validates():
    card = _load_card("attendance_shift_employee_group_first")

    assert card["workflow"][0] == "识别员工组"
    assert "按交集计算共享班次" in card["core_principle"]
    assert "共同班次不取代真实排班" in card["merge_rule"]
    assert "检查最终不重叠不重复且至少间隔30分钟" in card["workflow"]
