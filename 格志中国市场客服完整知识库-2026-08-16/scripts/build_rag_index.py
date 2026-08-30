#!/usr/bin/env python3
"""Build a lightweight local RAG index from JSONL cards.

This intentionally uses only Python stdlib so the客服 RAG can run without
network setup. It creates:
  - keyword -> card ids
  - high-frequency query -> card id
  - character n-gram vectors for vector-like fallback
"""

from __future__ import annotations

import argparse
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path


DEFAULT_CARDS = Path("rag_cards/customer_service_rag_cards.jsonl")
DEFAULT_HF = Path("rag_cards/high_frequency_queries.json")
DEFAULT_CHUNKS = Path("rag_cards/source_chunks.jsonl")
DEFAULT_OUT = Path("rag_index/customer_service_rag_index.json")


def normalize(text: str) -> str:
    return re.sub(r"\s+", "", text.lower())


def char_ngrams(text: str, min_n: int = 2, max_n: int = 4) -> Counter[str]:
    text = normalize(text)
    grams: Counter[str] = Counter()
    if not text:
        return grams
    for n in range(min_n, max_n + 1):
        if len(text) < n:
            continue
        for i in range(len(text) - n + 1):
            grams[text[i : i + n]] += 1
    return grams


def load_cards(path: Path) -> list[dict]:
    cards: list[dict] = []
    with path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            card = json.loads(line)
            if card.get("status") == "active":
                cards.append(card)
            else:
                print(f"skip inactive card at line {line_no}: {card.get('id')}")
    return cards


def load_chunks(path: Path) -> list[dict]:
    if not path.exists():
        return []
    chunks: list[dict] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                chunks.append(json.loads(line))
    return chunks


def card_text(card: dict) -> str:
    if card.get("type") == "source_chunk":
        return " ".join(
            [
                card.get("id", ""),
                card.get("source_file", ""),
                card.get("title", ""),
                card.get("product_line", ""),
                card.get("intent", ""),
                card.get("risk_level", ""),
                card.get("content", ""),
            ]
        )
    parts = [
        card.get("id", ""),
        card.get("product_line", ""),
        card.get("intent", ""),
        card.get("issue", ""),
        " ".join(card.get("models", [])),
        " ".join(card.get("keywords", [])),
        " ".join(card.get("synonyms", [])),
        card.get("reply_template", ""),
        card.get("escalation", ""),
    ]
    for action in card.get("actions", []):
        parts.append(action.get("type", ""))
        parts.append(action.get("location", ""))
        parts.append(action.get("note", ""))
    return " ".join(parts)


def build_index(cards: list[dict], chunks: list[dict], hf_path: Path | None) -> dict:
    keyword_index: dict[str, list[str]] = defaultdict(list)
    card_vectors: dict[str, dict[str, float]] = {}
    document_frequency: Counter[str] = Counter()
    raw_vectors: dict[str, Counter[str]] = {}
    docs = cards + chunks

    for card in docs:
        card_id = card["id"]
        terms = set()
        if card.get("type") == "source_chunk":
            for value in [card.get("source_file", ""), card.get("title", ""), card.get("product_line", ""), card.get("intent", "")]:
                term = normalize(value)
                if term:
                    terms.add(term)
            for token in re.findall(r"[\u4e00-\u9fff]{2,}|[a-zA-Z0-9_\\-]{2,}", card.get("content", "")):
                terms.add(normalize(token))
        else:
            for field in ("keywords", "synonyms", "models"):
                for value in card.get(field, []):
                    term = normalize(value)
                    if term:
                        terms.add(term)
            terms.update(
                normalize(v)
                for v in [card.get("issue", ""), card.get("product_line", ""), card.get("intent", "")]
                if v
            )
        for term in terms:
            if card_id not in keyword_index[term]:
                keyword_index[term].append(card_id)

        vec = char_ngrams(card_text(card))
        raw_vectors[card_id] = vec
        for gram in vec:
            document_frequency[gram] += 1

    total_docs = max(len(docs), 1)
    for card_id, vec in raw_vectors.items():
        weighted: dict[str, float] = {}
        norm_sq = 0.0
        for gram, count in vec.items():
            idf = math.log((1 + total_docs) / (1 + document_frequency[gram])) + 1.0
            value = count * idf
            weighted[gram] = value
            norm_sq += value * value
        norm = math.sqrt(norm_sq) or 1.0
        card_vectors[card_id] = {gram: value / norm for gram, value in weighted.items()}

    high_frequency: dict[str, str] = {}
    if hf_path and hf_path.exists():
        hf = json.loads(hf_path.read_text(encoding="utf-8"))
        for item in hf.get("queries", []):
            high_frequency[normalize(item["query"])] = item["card_id"]

    return {
        "version": "2026-05-16",
        "cards": cards,
        "source_chunks": chunks,
        "keyword_index": dict(sorted(keyword_index.items())),
        "high_frequency": high_frequency,
        "vectors": card_vectors,
        "vectorizer": {
            "type": "char_ngram_tfidf",
            "min_n": 2,
            "max_n": 4,
            "note": "Local vector-like fallback. Replace with production embeddings when available.",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cards", type=Path, default=DEFAULT_CARDS)
    parser.add_argument("--chunks", type=Path, default=DEFAULT_CHUNKS)
    parser.add_argument("--high-frequency", type=Path, default=DEFAULT_HF)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()

    cards = load_cards(args.cards)
    chunks = load_chunks(args.chunks)
    index = build_index(cards, chunks, args.high_frequency)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"indexed_cards={len(cards)}")
    print(f"indexed_source_chunks={len(chunks)}")
    print(f"keywords={len(index['keyword_index'])}")
    print(f"high_frequency={len(index['high_frequency'])}")
    print(f"out={args.out}")


if __name__ == "__main__":
    main()
