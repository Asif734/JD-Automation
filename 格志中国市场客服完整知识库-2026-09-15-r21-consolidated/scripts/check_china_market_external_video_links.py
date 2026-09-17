#!/usr/bin/env python3
"""Reject YouTube domains from the China-market customer-service knowledge base."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


TEXT_SUFFIXES = {".csv", ".htm", ".html", ".json", ".jsonl", ".md", ".txt", ".yaml", ".yml"}
EXCLUDED_DIRS = {".git", "node_modules", "tests", "__pycache__"}
BLOCKED_DOMAIN = re.compile(
    r"(?:youtube(?:-nocookie)?" + r"\.com|youtu" + r"\.be)",
    re.IGNORECASE,
)


def should_scan(path: Path, root: Path) -> bool:
    relative_parts = path.relative_to(root).parts
    if any(part in EXCLUDED_DIRS or part.startswith(".venv") for part in relative_parts):
        return False
    return path.is_file() and path.suffix.lower() in TEXT_SUFFIXES


def find_blocked_links(root: Path) -> list[str]:
    findings: list[str] = []
    for path in sorted(root.rglob("*")):
        if not should_scan(path, root):
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(lines, 1):
            if BLOCKED_DOMAIN.search(line):
                findings.append(f"{path.relative_to(root)}:{line_number}")
    return findings


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("."))
    args = parser.parse_args()

    findings = find_blocked_links(args.root.resolve())
    if findings:
        print("检测到中国市场知识库禁止使用的境外视频链接：")
        print("\n".join(findings))
        return 1
    print("中国市场知识库未检测到 YouTube 域名。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
