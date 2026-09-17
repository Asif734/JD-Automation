#!/usr/bin/env python3
"""Tiny regression test for客服 RAG search."""

from __future__ import annotations

import json
from pathlib import Path

from search_rag import search


INDEX = Path("rag_index/customer_service_rag_index.json")
TESTS = Path("rag_cards/customer_service_rag_test_queries.txt")


def load_tests(path: Path) -> list[tuple[str, str]]:
    cases: list[tuple[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        query, expected = line.split("->", 1)
        cases.append((query.strip(), expected.strip()))
    return cases


def main() -> None:
    index = json.loads(INDEX.read_text(encoding="utf-8"))
    cases = load_tests(TESTS)
    passed = 0
    failures = []
    for query, expected in cases:
        results = search(index, query, top_k=3)
        actual = results[0]["id"] if results else None
        if actual == expected:
            passed += 1
        else:
            failures.append((query, expected, actual, [r["id"] for r in results]))
    print(f"passed={passed}/{len(cases)}")
    if failures:
        print("failures:")
        for query, expected, actual, top_ids in failures:
            print(f"- query={query} expected={expected} actual={actual} top={top_ids}")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
