#!/usr/bin/env python3
"""OCR an image with RapidOCR and print recognized text lines.

This helper is intentionally small so it can be used both as a standalone
diagnostic command and as a subprocess fallback when the main bot is not run
inside the OCR virtual environment.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def _line_sort_key(item: list[Any]) -> tuple[float, float]:
    box = item[0]
    xs = [float(point[0]) for point in box]
    ys = [float(point[1]) for point in box]
    return (sum(ys) / len(ys), sum(xs) / len(xs))


def run_ocr(image_path: Path, min_confidence: float = 0.45) -> list[dict[str, Any]]:
    from rapidocr_onnxruntime import RapidOCR

    engine = RapidOCR()
    result, _elapsed = engine(str(image_path))
    if not result:
        return []

    rows: list[dict[str, Any]] = []
    for item in sorted(result, key=_line_sort_key):
        box, text, confidence = item
        confidence_value = float(confidence)
        text_value = str(text).strip()
        if not text_value or confidence_value < min_confidence:
            continue
        rows.append(
            {
                "text": text_value,
                "confidence": confidence_value,
                "box": box,
            }
        )
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description="OCR an image with RapidOCR")
    parser.add_argument("image_path")
    parser.add_argument("--json", action="store_true", help="emit JSON rows")
    parser.add_argument("--min-confidence", type=float, default=0.45)
    args = parser.parse_args()

    image_path = Path(args.image_path)
    if not image_path.exists():
        print(f"image not found: {image_path}", file=sys.stderr)
        raise SystemExit(2)

    rows = run_ocr(image_path, min_confidence=args.min_confidence)
    if args.json:
        print(json.dumps(rows, ensure_ascii=False))
    else:
        for row in rows:
            print(row["text"])


if __name__ == "__main__":
    main()
