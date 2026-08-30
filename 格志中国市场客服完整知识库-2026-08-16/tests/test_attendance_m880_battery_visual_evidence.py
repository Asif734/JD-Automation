import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "attendance_machine_m880_after_sales_issues_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
M880D_IMAGE = ROOT / "sources/user_uploads/attendance_machine/m880d_rear_cover_removed_with_battery.jpg"
M880_IMAGE = ROOT / "sources/user_uploads/attendance_machine/m880_rear_cover_removed_without_battery.png"


def load_cards() -> dict[str, dict]:
    cards = {}
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            card = json.loads(line)
            cards[card["id"]] = card
    return cards


def test_battery_visual_evidence_images_are_preserved() -> None:
    assert M880D_IMAGE.is_file() and M880D_IMAGE.stat().st_size > 0
    assert M880_IMAGE.is_file() and M880_IMAGE.stat().st_size > 0


def test_attendance_kb_distinguishes_m880d_and_m880_battery_layouts() -> None:
    text = KB.read_text(encoding="utf-8")
    assert "M880D：去除后盖后可见内置电池包" in text
    assert "M880：去除后盖后未安装电池包" in text
    assert "m880d_rear_cover_removed_with_battery.jpg" in text
    assert "m880_rear_cover_removed_without_battery.png" in text
    assert "不要指导客户自行拆机" in text


def test_structured_battery_visual_card_is_model_specific_and_safe() -> None:
    card = load_cards()["attendance_m880_m880d_battery_visual_identification"]
    assert card["models"] == ["M880", "M880D"]
    assert card["auto_reply_allowed"] is False
    assert card["model_facts"]["M880D"] == "带内置电池包"
    assert card["model_facts"]["M880"] == "无内置电池包"
    assert card["requires_model_confirmation_before_guidance"] is True
    assert "不要指导客户自行拆机" in card["do_not_say"]
