import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _load_card(card_id: str) -> dict:
    path = ROOT / "rag_cards" / "customer_service_rag_cards.jsonl"
    for line in path.read_text(encoding="utf-8").splitlines():
        card = json.loads(line)
        if card.get("id") == card_id:
            return card
    raise AssertionError(f"missing card: {card_id}")


def test_overlap_card_uses_interval_intersection():
    card = _load_card("attendance_shift_overlap_intersection")
    calculation = card["calculation"]

    assert calculation["overlap_start"] == "max(各班次上班时间)"
    assert calculation["overlap_end"] == "min(各班次下班时间)"
    assert calculation["exists_when"] == "overlap_start < overlap_end"
    assert calculation["no_overlap_when"] == "overlap_start >= overlap_end"
    assert "跨夜" in calculation["normalize"]


def test_overlap_card_preserves_original_shift_for_attendance():
    card = _load_card("attendance_shift_overlap_intersection")

    assert "迟到、早退仍按员工所属原始班次" in card["usage_boundary"]
    assert "用平均时间代替交集" in card["do_not_say"]


def test_overlap_card_defines_automatic_column_positioning():
    card = _load_card("attendance_shift_overlap_intersection")
    positioning = card["column_positioning"]

    assert "共同开始时间及以前" in positioning["in_column"]
    assert "共同结束时间及以后" in positioning["out_column"]
    assert "15:00及以前上班进入第一班上班栏" in positioning["confirmed_example"]
    assert "17:00及以后下班进入第一班下班栏" in positioning["confirmed_example"]


def test_overlap_kb_contains_required_examples():
    text = (ROOT / "attendance_shift_overlap_calculation_kb.md").read_text(
        encoding="utf-8"
    )

    assert "共同班次 = 09:00–17:00" in text
    assert "共同班次 = 11:00–12:00" in text
    assert "20:00–02:00 → 20:00–26:00" in text
    assert "共同班次 = 10:00–16:00" in text
    assert "没有共同时间，应设置为两个独立班次" in text
    assert "15:00` 及以前到岗打卡" in text
    assert "17:00` 及以后离岗打卡" in text


def test_employee_group_first_principle_is_in_kb():
    text = (ROOT / "attendance_shift_overlap_calculation_kb.md").read_text(
        encoding="utf-8"
    )

    assert "第一原则：先识别员工组，再合并设备班次" in text
    assert "每一个时间段不一定代表一组新员工" in text
    assert "尽量共用设备的最多3组班次" in text


def test_employee_group_first_card_workflow():
    card = _load_card("attendance_shift_employee_group_first")

    assert card["workflow"][0] == "优先按约8小时识别员工组"
    assert "每组员工的全部打卡时间" in card["core_principle"]
    assert "max(上班时间)" in card["merge_rule"]
    assert "客户报了几个时间段就是几组员工" in card["do_not_say"]
    heuristic = card["employee_group_heuristic"]
    assert "约8小时" in heuristic["primary_rule"]
    assert heuristic["normal_work_hours"] == "约8小时（最高优先级）"
    assert "次级情况" in heuristic["overtime_work_hours"]
    assert "累计11.5小时" in heuristic["example"]
    assert "不能单独证明同一员工组" in heuristic["boundary"]
