import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "attendance_machine_m880_after_sales_issues_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
IMAGE = ROOT / "sources/user_uploads/attendance_machine/attendance_card_rack_20_slot.jpg"


def load_cards() -> dict[str, dict]:
    cards = {}
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            card = json.loads(line)
            cards[card["id"]] = card
    return cards


def test_card_rack_image_is_preserved() -> None:
    assert IMAGE.is_file()
    assert IMAGE.stat().st_size > 0


def test_kb_records_20_slot_card_rack_dimensions() -> None:
    text = KB.read_text(encoding="utf-8")
    assert "20栏位考勤卡架" in text
    assert "41.5 × 21 × 3.2 厘米" in text
    assert "入卡宽度约 8.6 厘米" in text
    assert "入卡深度约 14.5 厘米" in text
    assert "attendance_card_rack_20_slot.jpg" in text


def test_structured_card_rack_card_has_exact_dimensions_and_reply() -> None:
    card = load_cards()["attendance_card_rack_20_slot_dimensions"]
    assert card["slot_count"] == 20
    assert card["dimensions_cm"] == {
        "height": 41.5,
        "width": 21.0,
        "depth": 3.2,
    }
    assert card["card_slot_cm"] == {
        "insertion_width": 8.6,
        "insertion_depth": 14.5,
    }
    assert card["visual_evidence"] == "sources/user_uploads/attendance_machine/attendance_card_rack_20_slot.jpg"
    assert "20栏位" in card["reply_template"]
    assert "高41.5×宽21×厚3.2厘米" in card["reply_template"]
