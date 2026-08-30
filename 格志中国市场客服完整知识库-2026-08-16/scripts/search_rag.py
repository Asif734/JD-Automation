#!/usr/bin/env python3
"""Search local客服 RAG cards with keyword + high-risk + vector fallback."""

from __future__ import annotations

import argparse
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path


DEFAULT_INDEX = Path("rag_index/customer_service_rag_index.json")
HIGH_RISK_TERMS = [
    "退款",
    "退货",
    "换货",
    "补发",
    "赔偿",
    "差价",
    "优惠券",
    "发票",
    "投诉",
    "差评",
    "平台介入",
    "小二",
    "维修费",
    "维修",
    "过保",
    "保修",
    "质保",
    "免费修",
    "保多久",
    "保多长",
    "保多长时间",
    "售后多久",
    "地址",
    "骚扰",
    "恶意骚扰",
    "辱骂",
    "威胁",
]

GENERIC_QUERY_TERMS = {
    "可以",
    "这个",
    "这款",
    "机器",
    "问题",
    "怎么",
    "什么",
    "多少",
    "多久",
    "多长",
    "一下",
    "帮我",
    "亲",
}

PRODUCT_CONTEXT_TERMS = {
    "考勤机",
    "考勤",
    "打卡",
    "m880",
    "纸卡",
    "针打",
    "针式",
    "热敏",
    "标签",
    "蓝牙",
    "wifi",
    "wi-fi",
}

BROAD_KEYWORD_MAX_DOCS = 24


def normalize(text: str) -> str:
    return re.sub(r"\s+", "", text.lower())


def char_ngrams(text: str, min_n: int = 2, max_n: int = 4) -> Counter[str]:
    text = normalize(text)
    grams: Counter[str] = Counter()
    for n in range(min_n, max_n + 1):
        if len(text) < n:
            continue
        for i in range(len(text) - n + 1):
            grams[text[i : i + n]] += 1
    return grams


def cosine_query(query: str, vectors: dict[str, dict[str, float]]) -> dict[str, float]:
    q = char_ngrams(query)
    if not q:
        return {}
    norm = math.sqrt(sum(v * v for v in q.values())) or 1.0
    qv = {k: v / norm for k, v in q.items()}
    scores: dict[str, float] = {}
    for card_id, vec in vectors.items():
        score = 0.0
        for gram, q_value in qv.items():
            score += q_value * vec.get(gram, 0.0)
        if score:
            scores[card_id] = score
    return scores


def detect_product_line(query: str) -> str | None:
    q = normalize(query)
    if any(t in q for t in ["考勤", "打卡", "m880", "日期", "班次", "响铃"]):
        return "attendance_machine"
    if any(t in q for t in ["热敏", "标签", "电子面单", "tp518", "白纸"]):
        return "thermal_printer"
    if any(t in q for t in ["针打", "针式", "td630", "th880", "票据"]):
        return "dot_matrix_printer"
    if any(t in q for t in ["wifi", "wi-fi", "蓝牙", "app", "ip"]):
        return "wifi_bluetooth_printer"
    return None


def keyword_weight(term: str, doc_count: int) -> tuple[float, str]:
    if not term:
        return 0, "ignore"
    if term in GENERIC_QUERY_TERMS:
        return 0, "ignore"
    if term in PRODUCT_CONTEXT_TERMS:
        return 5, "product_term"
    if doc_count > BROAD_KEYWORD_MAX_DOCS:
        return 4, "broad_keyword"
    if len(term) >= 4:
        return 42, "keyword"
    if len(term) >= 3:
        return 30, "keyword"
    if len(term) >= 2:
        return 16, "keyword"
    return 0, "ignore"


def has_intent_reason(items: list[str]) -> bool:
    return any(
        reason == "high_frequency_exact"
        or reason.startswith("keyword:")
        or reason.startswith("high_risk:")
        for reason in items
    )


def search(index: dict, query: str, top_k: int = 3, include_source_chunks: bool = False) -> list[dict]:
    q = normalize(query)
    cards_by_id = {card["id"]: card for card in index["cards"]}
    if include_source_chunks:
        cards_by_id.update({chunk["id"]: chunk for chunk in index.get("source_chunks", [])})
    scores: defaultdict[str, float] = defaultdict(float)
    reasons: defaultdict[str, list[str]] = defaultdict(list)

    hf = index.get("high_frequency", {})
    if q in hf and hf[q] in cards_by_id:
        scores[hf[q]] += 120
        reasons[hf[q]].append("high_frequency_exact")

    product_line = detect_product_line(query)

    for term, card_ids in index.get("keyword_index", {}).items():
        if term and term in q:
            weight, reason_type = keyword_weight(term, len(card_ids))
            if weight <= 0:
                continue
            for card_id in card_ids:
                if card_id not in cards_by_id:
                    continue
                scores[card_id] += weight
                reasons[card_id].append(f"{reason_type}:{term}")

    for risk_term in HIGH_RISK_TERMS:
        if normalize(risk_term) in q:
            for card in index["cards"]:
                if card.get("risk_level") == "high":
                    card_text = normalize(
                        " ".join(card.get("keywords", []) + card.get("synonyms", [])) + card.get("issue", "")
                    )
                    if normalize(risk_term) in card_text:
                        scores[card["id"]] += 80
                        reasons[card["id"]].append(f"high_risk:{risk_term}")

    vector_scores = cosine_query(query, index.get("vectors", {}))
    for card_id, vector_score in vector_scores.items():
        if card_id not in cards_by_id:
            continue
        scores[card_id] += vector_score * 30
        if vector_score > 0.15:
            reasons[card_id].append(f"vector:{vector_score:.3f}")

    for card in index["cards"]:
        card_id = card["id"]
        if product_line and card.get("product_line") == product_line and has_intent_reason(reasons.get(card_id, [])):
            scores[card_id] += 25
            reasons[card_id].append(f"product:{product_line}")
        elif (
            product_line
            and scores.get(card_id, 0) > 0
            and card.get("product_line") not in {product_line, "all", None}
        ):
            scores[card_id] -= 35
            reasons[card_id].append(f"product_mismatch:{product_line}")
        if card.get("product_line") == "all" and scores.get(card_id, 0) > 0:
            scores[card_id] += 2
        if scores.get(card_id, 0) > 0 and has_intent_reason(reasons.get(card_id, [])):
            scores[card_id] += 45
            reasons[card_id].append("curated_card_boost")
            scores[card_id] += card.get("priority", 0) * 0.2

    if include_source_chunks:
        for chunk in index.get("source_chunks", []):
            chunk_id = chunk["id"]
            if product_line and chunk.get("product_line") == product_line and scores.get(chunk_id, 0) > 0:
                scores[chunk_id] += 6
                reasons[chunk_id].append(f"source_product:{product_line}")
            scores[chunk_id] -= 45

    ranked = sorted(scores.items(), key=lambda item: item[1], reverse=True)
    results = []
    for card_id, score in ranked[:top_k]:
        card = cards_by_id[card_id]
        is_chunk = card.get("type") == "source_chunk"
        results.append(
            {
                "score": round(score, 3),
                "reasons": reasons[card_id][:8],
                "id": card_id,
                "type": "source_chunk" if is_chunk else "card",
                "risk_level": card.get("risk_level"),
                "auto_reply_allowed": card.get("auto_reply_allowed", False),
                "issue": card.get("issue", card.get("title")),
                "reply_template": card.get("reply_template", card.get("content", "")[:500]),
                "actions": card.get("actions", []),
                "source_file": card.get("source_file"),
            }
        )
    return results


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("query")
    parser.add_argument("--index", type=Path, default=DEFAULT_INDEX)
    parser.add_argument("--top-k", type=int, default=3)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--include-source-chunks", action="store_true")
    args = parser.parse_args()

    index = json.loads(args.index.read_text(encoding="utf-8"))
    results = search(index, args.query, args.top_k, include_source_chunks=args.include_source_chunks)
    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
        return
    print(f"query: {args.query}")
    for idx, result in enumerate(results, 1):
        print(f"\n#{idx} {result['id']} score={result['score']} risk={result['risk_level']}")
        if result.get("type") == "source_chunk":
            print(f"type: source_chunk source={result.get('source_file')}")
        print(f"issue: {result['issue']}")
        print(f"reasons: {', '.join(result['reasons'])}")
        print(f"reply: {result['reply_template']}")
        for action in result["actions"]:
            location = action.get("location")
            if location:
                print(f"action: {action.get('type')} -> {location}")
            else:
                print(f"action: {action.get('type')}")


if __name__ == "__main__":
    main()
