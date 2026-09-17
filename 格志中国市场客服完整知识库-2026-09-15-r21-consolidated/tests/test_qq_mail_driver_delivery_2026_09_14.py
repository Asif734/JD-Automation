from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).parents[1]
SOURCE = ROOT / "confirmed_qq_mail_driver_delivery_2026_09_14_kb.md"
CATALOG = ROOT / "rag_cards/driver_delivery_catalog.json"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards/high_frequency_queries.json"
QUERIES = ROOT / "rag_cards/customer_service_rag_test_queries.txt"
INDEX = ROOT / "rag_index/customer_service_rag_index.json"

CARD_ID = "printer_driver_email_reusable_large_attachment"
DRIVER_ID = "noble_universal_windows_driver"


def load_cards() -> list[dict]:
    return [json.loads(line) for line in CARDS.read_text(encoding="utf-8").splitlines() if line]


def test_authoritative_source_records_confirmed_reuse_and_approval_boundaries() -> None:
    text = SOURCE.read_text(encoding="utf-8")

    assert "DotNobleDriver" in text
    assert "ThermalNobleDriver" in text
    assert "同一个" in text
    assert "无需重复上传" in text
    assert "72小时" in text
    assert "收件人、主题、正文、文件名和有效期" in text
    assert "不得复制原邮件的收件人" in text


def test_driver_catalog_uses_one_canonical_entry_for_both_aliases() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    entries = {item["id"]: item for item in catalog["entries"]}
    driver = entries[DRIVER_ID]

    assert catalog["version"] == "2026-09-14-r20"
    assert set(driver["aliases"]) == {"DotNobleDriver", "ThermalNobleDriver"}
    assert driver["delivery_mode"] == "reuse_qq_large_attachment"
    assert driver["source_match"]["filename_contains"] == "DotNobleDriver"
    assert driver["minimum_remaining_hours"] == 72
    assert "source_uid" not in json.dumps(driver)
    assert "download_url" not in json.dumps(driver)


def test_active_card_requires_windows_email_and_explicit_send_approval() -> None:
    cards = {item["id"]: item for item in load_cards() if item.get("status") == "active"}
    card = cards[CARD_ID]

    assert card["driver_catalog_id"] == DRIVER_ID
    assert set(card["required_slots"]) == {"客户邮箱", "电脑系统"}
    assert card["operating_system"] == "Windows"
    assert card["external_action"] is True
    assert card["auto_reply_allowed"] is False
    assert card["approval_required_fields"] == ["收件人", "主题", "正文", "文件名", "有效期"]
    assert any(action["type"] == "list_reusable_large_attachments" for action in card["actions"])
    assert any(action["type"] == "send_reusable_large_attachment" for action in card["actions"])
    assert "Mac" in card["escalation"]


def test_high_frequency_and_regression_queries_route_both_aliases_to_one_card() -> None:
    high_frequency = json.loads(HF.read_text(encoding="utf-8"))
    mappings = {item["query"]: item["card_id"] for item in high_frequency["queries"]}

    assert high_frequency["version"] == "2026-09-14-r20"
    assert mappings["把DotNobleDriver发到客户邮箱"] == CARD_ID
    assert mappings["客户要ThermalNobleDriver邮件附件"] == CARD_ID
    query_text = QUERIES.read_text(encoding="utf-8")
    assert f"把DotNobleDriver发到客户邮箱 -> {CARD_ID}" in query_text
    assert f"客户要ThermalNobleDriver邮件附件 -> {CARD_ID}" in query_text


def test_private_large_attachment_tokens_are_absent_from_kb_text_and_index() -> None:
    inspected = [SOURCE, CATALOG, CARDS, HF, QUERIES, INDEX]
    for path in inspected:
        text = path.read_text(encoding="utf-8")
        assert "wx.mail.qq.com/ftn/download" not in text
        assert "attachment_fingerprint" not in text
        assert "source_uid" not in text


def test_rebuilt_index_contains_driver_delivery_card_and_source_chunk() -> None:
    index = json.loads(INDEX.read_text(encoding="utf-8"))

    assert index["version"] == "2026-09-14-r20"
    assert CARD_ID in {item["id"] for item in index["cards"]}
    assert any(
        item["source_file"] == SOURCE.name for item in index["source_chunks"]
    )


def test_package_version_is_r19() -> None:
    from scripts.package_version import PACKAGE_ROOT, PACKAGE_VERSION

    assert PACKAGE_VERSION == "2026-09-14-r20"
    assert PACKAGE_ROOT == "格志中国市场客服完整知识库-2026-09-14-r20"
