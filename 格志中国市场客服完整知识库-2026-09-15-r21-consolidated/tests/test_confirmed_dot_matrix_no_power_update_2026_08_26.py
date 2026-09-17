from __future__ import annotations

import json
from pathlib import Path

from scripts.search_rag import search


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "confirmed_dot_matrix_no_power_update_2026_08_26_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
INDEX = ROOT / "rag_index/customer_service_rag_index.json"


def _card() -> dict:
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        item = json.loads(line)
        if item["id"] == "dot_matrix_no_power_top_button":
            return item
    raise AssertionError("missing no-power card")


def test_confirmed_source_contains_three_concise_actions() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    assert "更换一个确认正常工作的电源插座" in text
    assert "长按电源按钮尝试开机" in text
    assert "转人工客服申请维修" in text
    assert "不要求客户关机静置、检查多条线缆" in text


def test_no_power_card_uses_confirmed_concise_reply() -> None:
    card = _card()
    assert card["reply_template"] == "请先更换一个正常工作的电源插座测试，然后长按电源按钮尝试开机。如果仍然无法开机，请联系人工客服申请维修。"
    assert card["reply_template_en"] == "Try a different working power outlet. Long-press the power button and try turning it on. If the printer still does not turn on, contact human customer service to request maintenance."
    assert len(card["actions"]) == 3
    assert "静置" not in card["reply_template"] and "长按电源按钮" in card["reply_template"]


def test_chinese_and_english_queries_route_to_no_power_card() -> None:
    index = json.loads(INDEX.read_text(encoding="utf-8"))
    for query in [
        "打印机无法开机",
        "打印机昨天还能用今天不开机",
        "my printer is not turning on what do i do it was still working yesterday",
    ]:
        assert search(index, query, top_k=1)[0]["id"] == "dot_matrix_no_power_top_button"
