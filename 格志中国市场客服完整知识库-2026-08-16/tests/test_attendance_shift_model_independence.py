import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _load_card(card_id: str) -> dict:
    cards_path = ROOT / "rag_cards" / "customer_service_rag_cards.jsonl"
    for line in cards_path.read_text(encoding="utf-8").splitlines():
        card = json.loads(line)
        if card.get("id") == card_id:
            return card
    raise AssertionError(f"missing card: {card_id}")


def test_shift_setup_is_model_independent():
    card = _load_card("attendance_manual_shift_setup")

    assert card["models"] == ["all_attendance_machines"]
    assert card["model_confirmation_required"] is False
    assert "与机器型号无关" in card["uniform_rule"]
    assert "先识别员工组" in card["uniform_rule"]
    assert "员工组数量" in card["required_slots"]
    assert card["actions"][0]["type"] == "identify_employee_groups_first"
    assert "是否重叠" in card["required_slots"]
    assert "班次设置前先确认机器型号" in card["do_not_say"]


def test_manual_kb_states_shift_model_exception():
    text = (ROOT / "attendance_machine_manual_customer_reply_kb.md").read_text(
        encoding="utf-8"
    )

    assert "班次设置是统一例外" in text
    assert "处理班次问题不需要先确认机器型号" in text
