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
    assert "最多3个自动班次" in card["uniform_rule"]
    assert "相邻班次至少间隔30分钟" in card["uniform_rule"]
    assert "每个班次的上班和下班时间" in card["required_slots"]
    assert card["actions"][0]["type"] == "collect_shift_times"
    assert "是否跨天" in card["required_slots"]
    assert "把重叠的真实班次直接输入机器" in card["do_not_say"]


def test_manual_kb_states_shift_model_exception():
    text = (ROOT / "attendance_machine_manual_customer_reply_kb.md").read_text(
        encoding="utf-8"
    )

    assert "班次设置是统一例外" in text
    assert "处理班次问题不需要先确认机器型号" in text
