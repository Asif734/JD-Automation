#!/usr/bin/env python3
"""Read visible QianNiu buyer conversations for RAG learning.

The script is intentionally read-only: it clicks buyer rows, takes a screenshot
of the chat history area, OCRs it locally, anonymizes the result, and scrolls the
buyer list. It never writes into the chat input and never clicks order actions.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
AX = ROOT / "bin" / "qianniu_ax"
TMP_DIR = Path("/private/tmp/qianniu_front100_learning")
OUT_DIR = ROOT / "outputs" / "qianniu_chat_learning"

# Display 2 currently contains the QianNiu reception window. The region is
# deliberately limited to the central chat-history area.
SCREEN_ID = "2"
CHAT_REGION = "320,100,420,470"


@dataclass(frozen=True)
class BuyerRow:
    title: str
    x: int
    y: int
    width: int
    height: int


def run(args: list[str], timeout: float = 10.0) -> str:
    result = subprocess.run(
        args,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout


def visible_buyers() -> list[BuyerRow]:
    output = run([str(AX), "dump-buyers"])
    rows: list[BuyerRow] = []
    for line in output.splitlines():
        parts = line.split("\t", 5)
        if len(parts) != 6:
            continue
        _index, x, y, width, height, title = parts
        rows.append(BuyerRow(title=title, x=int(x), y=int(y), width=int(width), height=int(height)))
    return rows


def capture_chat(index: int) -> Path:
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    path = TMP_DIR / f"chat_{index:03d}.png"
    run(["screencapture", "-x", "-D", SCREEN_ID, "-R", CHAT_REGION, str(path)], timeout=5.0)
    return path


def sort_key(item: list[object]) -> tuple[float, float]:
    box = item[0]  # type: ignore[index]
    xs = [float(point[0]) for point in box]  # type: ignore[index]
    ys = [float(point[1]) for point in box]  # type: ignore[index]
    return (sum(ys) / len(ys), sum(xs) / len(xs))


def ocr_image(engine: object, image_path: Path, min_confidence: float) -> list[str]:
    result, _elapsed = engine(str(image_path))  # type: ignore[operator]
    if not result:
        return []
    lines: list[str] = []
    for item in sorted(result, key=sort_key):
        _box, text, confidence = item
        if float(confidence) >= min_confidence:
            cleaned = str(text).strip()
            if cleaned:
                lines.append(cleaned)
    return lines


def sanitize_line(line: str, buyer_titles: Iterable[str]) -> str:
    value = line.strip()
    for title in buyer_titles:
        if title:
            value = value.replace(title, "[买家]")
    value = re.sub(r"grozzi[ile]{0,4}格志旗舰店\S*", "[店铺]", value, flags=re.IGNORECASE)
    value = re.sub(r"cntaobao[a-zA-Z0-9_\-\u4e00-\u9fff]+", "[账号]", value)
    value = re.sub(r"\btb[0-9A-Za-z_]{4,}\b", "[买家ID]", value)
    value = re.sub(r"\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[A-Za-z]{2,}\b", "[邮箱]", value)
    value = re.sub(r"https?://\S+", "[链接]", value)
    value = re.sub(r"\b1[3-9]\d{9}\b", "[手机号]", value)
    value = re.sub(r"20\d{2}[-/年]\d{1,2}[-/月]\d{1,2}\S*", "[日期]", value)
    value = re.sub(r"\b\d{1,2}:\d{2}(?::\d{2})?\b", "[时间]", value)
    value = re.sub(r"(?<!\d)\d{6,}(?!\d)", "[编号]", value)
    return value.strip()


def useful_lines(lines: list[str], buyer_titles: Iterable[str]) -> list[str]:
    ignored = {
        "已读",
        "未读",
        "未接收",
        "请选择表情",
        "发送",
        "关闭",
        "足迹",
        "推荐",
        "知识库",
        "展开",
        "离线",
        "今日接待",
        "未下单",
        "未付款",
        "已付款",
        "无法",
        "服接",
        "联系人",
        "咨询",
        "近3",
        "全部",
        "客朋",
        "未查收",
        "高消费用户",
    }
    sanitized: list[str] = []
    seen = set()
    for line in lines:
        value = sanitize_line(line, buyer_titles)
        if not value or value in ignored:
            continue
        if len(value) <= 1:
            continue
        if re.fullmatch(r"\d{2}-\d{2}", value):
            continue
        if re.fullmatch(r"[A-Za-z0-9:：·.\-, ]{1,24}", value):
            continue
        if value in seen:
            continue
        seen.add(value)
        sanitized.append(value)
    return sanitized


def append_markdown(path: Path, blocks: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("# 千牛前100个客户对话学习 OCR 摘要（匿名化）\n\n")
        handle.write(f"- 采集时间：{datetime.now().isoformat(timespec='seconds')}\n")
        handle.write("- 范围：千牛接待中心左侧“全部买家”列表，从顶部开始向下采集。\n")
        handle.write("- 隐私处理：客户昵称、长编号、手机号、链接等已替换；不保存截图。\n")
        handle.write("- 用途：只用于归纳高频问题、回复策略和 RAG 卡片，不作为订单/售后凭证。\n\n")
        for block in blocks:
            handle.write(f"## 买家样本 {block['sample_id']}\n\n")
            handle.write(f"- 列表序号：{block['position']}\n")
            handle.write(f"- OCR行数：{block['line_count']}\n\n")
            for line in block["lines"]:  # type: ignore[index]
                handle.write(f"- {line}\n")
            handle.write("\n")


def sanitize_collected(raw_dir: Path, buyers_file: Path, out_path: Path) -> None:
    buyer_titles: list[str] = []
    title_by_sample: dict[str, str] = {}
    if buyers_file.exists():
        for line in buyers_file.read_text(encoding="utf-8", errors="ignore").splitlines():
            parts = line.split("\t", 1)
            if len(parts) != 2:
                continue
            sample, title = parts
            title_by_sample[sample.zfill(3)] = title
            buyer_titles.append(title)

    blocks: list[dict[str, object]] = []
    for json_path in sorted(raw_dir.glob("chat_*.json")):
        sample_id = json_path.stem.removeprefix("chat_").zfill(3)
        try:
            rows = json.loads(json_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            rows = []
        raw_lines = [str(row.get("text", "")).strip() for row in rows if isinstance(row, dict)]
        local_titles = buyer_titles + [title_by_sample.get(sample_id, "")]
        lines = useful_lines(raw_lines, local_titles)
        blocks.append(
            {
                "sample_id": sample_id,
                "position": int(sample_id),
                "line_count": len(lines),
                "lines": lines[:32],
            }
        )
    append_markdown(out_path, blocks)
    print(json.dumps({"output": str(out_path), "samples": len(blocks)}, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser(description="Learn QianNiu buyer chats by OCR")
    parser.add_argument("--max-customers", type=int, default=100)
    parser.add_argument("--scroll-amount", type=int, default=-420)
    parser.add_argument("--min-confidence", type=float, default=0.35)
    parser.add_argument("--delay", type=float, default=0.9)
    parser.add_argument("--out", default="")
    parser.add_argument("--sanitize-collected-dir", default="")
    parser.add_argument("--buyers-file", default="")
    args = parser.parse_args()

    if args.sanitize_collected_dir:
        out_path = Path(args.out) if args.out else OUT_DIR / datetime.now().strftime("%Y-%m-%d_front100_sanitized_ocr.md")
        sanitize_collected(Path(args.sanitize_collected_dir), Path(args.buyers_file), out_path)
        return

    from rapidocr_onnxruntime import RapidOCR

    engine = RapidOCR()
    all_titles: list[str] = []
    blocks: list[dict[str, object]] = []
    seen_titles: set[str] = set()
    stale_scrolls = 0

    while len(blocks) < args.max_customers and stale_scrolls < 4:
        rows = visible_buyers()
        new_rows = [row for row in rows if row.title not in seen_titles]
        if not new_rows:
            stale_scrolls += 1
        else:
            stale_scrolls = 0

        for row in new_rows:
            if len(blocks) >= args.max_customers:
                break
            seen_titles.add(row.title)
            all_titles.append(row.title)
            position = len(blocks) + 1
            run([str(AX), "click-buyer", row.title])
            time.sleep(args.delay)
            image_path = capture_chat(position)
            raw_lines = ocr_image(engine, image_path, args.min_confidence)
            lines = useful_lines(raw_lines, all_titles)
            try:
                image_path.unlink()
            except OSError:
                pass
            blocks.append(
                {
                    "sample_id": f"{position:03d}",
                    "position": position,
                    "line_count": len(lines),
                    "lines": lines[:32],
                }
            )
            print(json.dumps({"sample": position, "lines": len(lines)}, ensure_ascii=False), flush=True)

        if len(blocks) >= args.max_customers:
            break
        run([str(AX), "scroll-buyers", str(args.scroll_amount)])
        time.sleep(0.4)

    out_path = Path(args.out) if args.out else OUT_DIR / datetime.now().strftime("%Y-%m-%d_front100_sanitized_ocr.md")
    append_markdown(out_path, blocks)
    print(json.dumps({"output": str(out_path), "samples": len(blocks)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
