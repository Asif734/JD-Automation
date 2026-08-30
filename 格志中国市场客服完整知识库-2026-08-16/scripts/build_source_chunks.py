#!/usr/bin/env python3
"""Convert existing Markdown knowledge bases into fallback RAG source chunks.

Curated cards remain the fast path. These chunks preserve broad coverage from
the original knowledge base and are used when no curated card is enough.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


DEFAULT_OUT = Path("rag_cards/source_chunks.jsonl")
DEFAULT_MAX_CHARS = 1800
EXCLUDED = {
    "customer_service_rag_optimization_plan.md",
}


def slugify(value: str) -> str:
    value = value.lower()
    value = re.sub(r"[^a-z0-9\u4e00-\u9fff]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_")
    return value[:80] or "chunk"


def classify_product_line(filename: str, text: str) -> str:
    combined = f"{filename} {text[:500]}"
    if "考勤" in combined or "m880" in combined.lower() or "attendance" in combined.lower():
        return "attendance_machine"
    if "热敏" in combined or "thermal" in combined.lower():
        return "thermal_printer"
    if "针" in combined or "dot_matrix" in combined.lower() or "td630" in combined.lower():
        return "dot_matrix_printer"
    if "wifi" in combined.lower() or "蓝牙" in combined:
        return "wifi_bluetooth_printer"
    if "天猫" in combined or "规则" in combined or "tmall" in combined.lower():
        return "tmall_rule"
    return "general"


def classify_intent(text: str) -> str:
    if any(term in text for term in ["退款", "退货", "换货", "补发", "赔偿", "投诉", "差评", "发票"]):
        return "after_sales"
    if any(term in text for term in ["视频", "教程", "安装", "设置", "驱动"]):
        return "tutorial"
    if any(term in text for term in ["不打印", "白纸", "端口", "自检", "故障", "异常", "排查"]):
        return "troubleshooting"
    if any(term in text for term in ["售前", "适配", "推荐", "链接"]):
        return "presale"
    return "reference"


def risk_level(text: str) -> str:
    high_terms = ["退款", "退货", "换货", "补发", "赔偿", "差价", "优惠券", "发票", "投诉", "差评", "平台介入", "小二", "维修收费", "过保", "骚扰", "辱骂", "威胁"]
    if any(term in text for term in high_terms):
        return "high"
    medium_terms = ["故障", "不打印", "白纸", "端口", "自检", "维修", "质量问题", "异常"]
    if any(term in text for term in medium_terms):
        return "medium"
    return "low"


def split_markdown(path: Path, max_chars: int) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    chunks: list[dict] = []
    heading_stack: list[str] = []
    current_heading = "frontmatter"
    current: list[str] = []
    ordinal = 0

    def flush() -> None:
        nonlocal current, ordinal
        body = "\n".join(current).strip()
        if not body:
            current = []
            return
        ordinal += 1
        title = " > ".join(heading_stack) if heading_stack else current_heading
        chunks.append(
            {
                "id": f"src_{path.stem}_{ordinal:04d}_{slugify(title)}",
                "type": "source_chunk",
                "source_file": path.name,
                "title": title,
                "product_line": classify_product_line(path.name, body),
                "intent": classify_intent(body),
                "risk_level": risk_level(body),
                "content": body[:max_chars],
            }
        )
        current = []

    for line in lines:
        match = re.match(r"^(#{1,4})\s+(.+?)\s*$", line)
        if match:
            flush()
            level = len(match.group(1))
            heading = match.group(2)
            heading_stack = heading_stack[: level - 1]
            heading_stack.append(heading)
            current_heading = heading
            continue
        current.append(line)
        if sum(len(part) + 1 for part in current) >= max_chars:
            flush()
    flush()
    return chunks


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--max-chars", type=int, default=DEFAULT_MAX_CHARS)
    args = parser.parse_args()

    markdown_files = [
        path
        for path in sorted(args.root.glob("*.md"))
        if path.name not in EXCLUDED and not path.name.startswith(".")
    ]
    all_chunks: list[dict] = []
    for path in markdown_files:
        all_chunks.extend(split_markdown(path, args.max_chars))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8") as f:
        for chunk in all_chunks:
            f.write(json.dumps(chunk, ensure_ascii=False) + "\n")

    print(f"source_files={len(markdown_files)}")
    print(f"source_chunks={len(all_chunks)}")
    print(f"out={args.out}")


if __name__ == "__main__":
    main()
