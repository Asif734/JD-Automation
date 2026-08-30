import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "customer_service_global_clarification_policy_kb.md"
TRAINING = ROOT / "qianniu_customer_service_training_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
SOURCE_CHUNKS = ROOT / "rag_cards/source_chunks.jsonl"
INDEX = ROOT / "rag_index/customer_service_rag_index.json"


def test_global_policy_source_contains_all_approved_rules() -> None:
    text = POLICY.read_text(encoding="utf-8")
    required = [
        "证据不足",
        "每轮只问一个",
        "客户无需了解机器内部原理就能直接观察并回答",
        "不得要求客户判断打印头、马达、传感器等内部部件",
        "已确认的特征证据能够唯一确定故障类型时，不触发本原则",
        "简短复述客户关注点",
        "客户确认前，不发送具体参数、操作教程、视频或截图",
        "再核对机器型号与当前平台",
        "安全提醒",
        "不连续猜测",
    ]
    for phrase in required:
        assert phrase in text


def test_training_principles_reference_single_clarification_policy() -> None:
    text = TRAINING.read_text(encoding="utf-8")
    assert "单一关键问题确认原则" in text
    assert "客户确认前，不发送具体参数、操作教程、视频或截图" in text


def load_cards() -> dict[str, dict]:
    cards = {}
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            card = json.loads(line)
            cards[card["id"]] = card
    return cards


def test_structured_global_policy_is_safe_and_cross_platform() -> None:
    card = load_cards()["global_single_decisive_clarification_policy"]
    assert card["product_line"] == "all"
    assert card["models"] == ["all"]
    assert card["auto_reply_allowed"] is False
    assert card["ask_limit_per_turn"] == 1
    assert card["question_must_be_customer_observable"] is True
    assert card["skip_clarification_when_confirmed_signature_is_sufficient"] is True
    assert "打印头" in card["technical_judgments_not_for_customer"]
    assert card["block_branch_guidance_before_confirmation"] is True
    assert card["safety_warning_before_question_allowed"] is True
    assert card["after_one_unresolved_clarification"] == "collect_next_necessary_evidence_or_handoff"


def test_generated_source_chunks_include_global_policy() -> None:
    chunks = [
        json.loads(line)
        for line in SOURCE_CHUNKS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert any(
        chunk.get("source_file") == "customer_service_global_clarification_policy_kb.md"
        for chunk in chunks
    )


def test_rag_index_contains_global_policy_card() -> None:
    index = json.loads(INDEX.read_text(encoding="utf-8"))
    assert any(
        card.get("id") == "global_single_decisive_clarification_policy"
        for card in index["cards"]
    )
