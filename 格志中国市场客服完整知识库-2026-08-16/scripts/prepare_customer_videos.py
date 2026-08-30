#!/usr/bin/env python3
"""CLI for preparing local customer-video evidence packages."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

try:
    from .customer_video_pipeline import prepare_video
except ImportError:  # Direct script execution.
    from customer_video_pipeline import prepare_video


SUPPORTED_EXTENSIONS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".3gp"}


def collect_video_paths(source: Path, recursive: bool) -> list[Path]:
    if source.is_file():
        return [source] if source.suffix.lower() in SUPPORTED_EXTENSIONS else []
    if not source.is_dir():
        return []
    iterator = source.rglob("*") if recursive else source.glob("*")
    return sorted(
        path
        for path in iterator
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )


def process_paths(
    paths: list[Path], output: Path, **options: Any
) -> dict[str, object]:
    summary: dict[str, Any] = {
        "total": len(paths),
        "succeeded": 0,
        "failed": 0,
        "cached": 0,
        "cases": [],
        "errors": [],
    }
    for path in paths:
        try:
            result = prepare_video(path, output, **options)
            summary["succeeded"] += 1
            summary["cached"] += int(result.cached)
            summary["cases"].append(str(result.case_dir))
        except Exception as error:
            summary["failed"] += 1
            summary["errors"].append({"file": path.name, "error": str(error)})
    return summary


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Prepare local evidence packages from customer videos"
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("--recursive", action="store_true")
    parser.add_argument(
        "--output", type=Path, default=Path("outputs/customer_video_analysis")
    )
    parser.add_argument("--interval", type=float)
    parser.add_argument("--dense", action="store_true")
    parser.add_argument("--no-audio", action="store_true")
    parser.add_argument("--no-ocr", action="store_true")
    parser.add_argument("--force", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if not args.source.exists():
        print(json.dumps({"error": "source does not exist"}, ensure_ascii=False))
        return 2
    paths = collect_video_paths(args.source, args.recursive)
    if not paths:
        print(json.dumps({"error": "no supported videos found"}, ensure_ascii=False))
        return 2
    summary = process_paths(
        paths,
        args.output,
        interval=args.interval,
        dense=args.dense,
        extract_audio=not args.no_audio,
        ocr_enabled=not args.no_ocr,
        force=args.force,
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 1 if summary["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
