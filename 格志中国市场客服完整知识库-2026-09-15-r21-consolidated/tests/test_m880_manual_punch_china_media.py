from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARDS = ROOT / "rag_cards" / "customer_service_rag_cards.jsonl"


def load_card(card_id: str) -> dict:
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        card = json.loads(line)
        if card.get("id") == card_id:
            return card
    raise AssertionError(f"missing card: {card_id}")


def test_m880_tmall_manual_punch_has_video_and_two_chinese_screenshots() -> None:
    card = load_card("attendance_m880_manual_punch_tmall_media")

    assert card["models"] == ["M880"]
    assert card["platforms"] == ["Tmall"]
    assert card["video_url"].startswith("http://cloud.video.taobao.com/")
    assert card["full_operation_range"] == "00:03–00:49"
    assert "第02组设置为00" in card["reply_template"]
    assert len(card["screenshots"]) == 2
    for screenshot in card["screenshots"]:
        assert (ROOT / screenshot["path"]).is_file()
        assert any("\u4e00" <= character <= "\u9fff" for character in screenshot["description"])
    assert card["send_order"] == ["简短说明", "天猫视频", "截图1", "截图1说明", "截图2", "截图2说明"]
