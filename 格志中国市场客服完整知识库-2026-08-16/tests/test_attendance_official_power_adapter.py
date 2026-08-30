import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "attendance_machine_m880_after_sales_issues_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
POWER_DIR = ROOT / "sources/user_uploads/attendance_machine/official_power_adapter"


def load_cards() -> dict[str, dict]:
    cards = {}
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            card = json.loads(line)
            cards[card["id"]] = card
    return cards


def test_original_and_beautified_power_images_are_preserved() -> None:
    expected = [
        "original_label_view.jpg",
        "original_side_view.jpg",
        "beautified_label_view.png",
        "beautified_side_view.png",
    ]
    for filename in expected:
        path = POWER_DIR / filename
        assert path.is_file()
        assert path.stat().st_size > 0


def test_kb_records_universal_official_attendance_power_adapter() -> None:
    text = KB.read_text(encoding="utf-8")
    assert "所有考勤机统一使用同款原装电源" in text
    assert "WT23-250130-BF" in text
    assert "100–240V，50/60Hz，0.5A Max" in text
    assert "12.0V DC 2A" in text
    assert "THT-Space Electrical Company Ltd" in text
    assert "beautified_label_view.png" in text
    assert "beautified_side_view.png" in text


def test_structured_official_power_card_has_exact_specs_and_images() -> None:
    card = load_cards()["attendance_official_power_adapter_universal"]
    assert card["models"] == ["所有考勤机"]
    assert card["universal_for_all_attendance_machines"] is True
    assert card["adapter_model"] == "WT23-250130-BF"
    assert card["input"] == "100-240V~ 50/60Hz 0.5A Max"
    assert card["output"] == "12.0V DC 2A"
    assert card["manufacturer"] == "THT-Space Electrical Company Ltd"
    assert set(card["visual_evidence"]) == {
        "original_label",
        "original_side",
        "customer_label",
        "customer_side",
    }
    for relative_path in card["visual_evidence"].values():
        assert (ROOT / relative_path).is_file()
    assert "所有考勤机" in card["reply_template"]
    assert "12V 2A" in card["reply_template"]


def test_card_rack_card_remains_active() -> None:
    card = load_cards()["attendance_card_rack_20_slot_dimensions"]
    assert card["status"] == "active"
    assert card["slot_count"] == 20

