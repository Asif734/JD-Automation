#!/usr/bin/env python3
"""Fixed-window QianNiu客服 helper.

This is the first automation layer for a fixed QianNiu customer-service
window. It watches small configured screen regions, OCRs only when a region
changes, queries the local RAG index, then optionally fills/sends the reply.

The script uses macOS screencapture and prefers the project-local RapidOCR
environment for Chinese OCR, falling back to the Swift/Vision helper only when
RapidOCR is unavailable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "qianniu_ui_regions.json"
INDEX_PATH = ROOT / "rag_index/customer_service_rag_index.json"
OCR_SWIFT = ROOT / "scripts/ocr_image.swift"
OCR_BIN = ROOT / "bin/ocr_image"
OCR_RAPID = ROOT / "scripts/ocr_rapid.py"
OCR_VENV_PYTHON = ROOT / ".venv-ocr/bin/python"
QIANNIU_AX = ROOT / "bin/qianniu_ax"
QIANNIU_APP = Path("/Applications/Aliworkbench.app")

_RAPID_OCR_ENGINE: Any | None = None
_QIANNIU_AX_AVAILABLE: bool | None = None

try:
    from PIL import Image
except Exception:  # pragma: no cover - fallback for system Python without PIL
    Image = None  # type: ignore[assignment]

warnings.filterwarnings("ignore", category=DeprecationWarning)

sys.path.insert(0, str(ROOT))
from app import build_reply, quick_answer as app_quick_answer  # noqa: E402


HIGH_RISK_HINTS = [
    "退款",
    "退货",
    "换货",
    "赔偿",
    "差价",
    "发票",
    "投诉",
    "差评",
    "平台介入",
    "小二",
    "维修费",
    "地址",
    "电话",
]

ORDER_HINTS = [
    "订单",
    "下单",
    "付款",
    "支付",
    "发货",
    "物流",
    "快递",
    "单号",
    "多久到",
    "有没有买",
]

NOISE_PATTERNS = [
    r"AI咨询摘要.*",
    r"当前消息较多.*",
    r"7天内自动总结.*",
    r"AI一键总结.*",
    r"商家在售后服务过程中.*",
    r"风险预测.*",
    r"影响人工响应率.*",
    r"当前消费者需人工介入回复.*",
    r"已为你停止托管.*",
    r"消极接待.*",
    r"平台将依据.*管理规范.*",
    r"争议.*义务.*",
    r"最终解决义务.*",
    r"\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}:\d{2}",
    r"已读",
    r"收起",
    r"客服",
    r"智能客服.*",
]

INVALID_CUSTOMER_MESSAGE_PATTERNS = [
    r"run_qianniu_rag_bot",
    r"qianniu_fixed_window_bot",
    r"query_context",
    r"top_match",
    r"auto_reply_allowed",
    r"src_[a-z0-9_]+",
    r"\.command",
    r"\.py\b",
    r"^\{.*\}$",
    r"风险预测",
    r"人工响应率",
    r"人工介入回复",
    r"停止托管",
    r"消极接待",
    r"管理规范",
]

SYSTEM_NOTICE_HINTS = [
    "风险预测",
    "人工响应率",
    "人工介入回复",
    "停止托管",
    "售后服务过程中",
    "争议清义务",
    "纠纷主导义务",
    "最终解决义务",
    "消极接待",
    "管理规范",
]


@dataclass(frozen=True)
class Box:
    x: int
    y: int
    width: int
    height: int

    @property
    def center(self) -> tuple[int, int]:
        return self.x + self.width // 2, self.y + self.height // 2


@dataclass(frozen=True)
class WindowMetrics:
    x: int
    y: int
    width: int
    height: int


def run(args: list[str], *, check: bool = True, text: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=check, text=text, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def qianniu_process_running() -> bool:
    result = subprocess.run(
        ["pgrep", "-x", "Aliworkbench"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def open_qianniu_in_background() -> bool:
    """Open QianNiu without activating the main screen.

    The bot still waits for a window whose title contains 接待中心 before it
    captures, fills, or sends anything. Opening the app is only a background
    launch convenience; it is not permission to operate the workbench window.
    """
    if qianniu_process_running():
        return True
    command = ["open", "-g", str(QIANNIU_APP)] if QIANNIU_APP.exists() else ["open", "-g", "-a", "Aliworkbench"]
    result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or "").strip()
        print(f"[hold] cannot open QianNiu in background: {detail}", file=sys.stderr)
        return False
    print("[open] QianNiu opened in background; waiting only for 接待中心 on the secondary display", flush=True)
    return True


def load_config() -> dict[str, Any]:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def ensure_ocr_helper() -> bool:
    if OCR_BIN.exists():
        return True
    OCR_BIN.parent.mkdir(parents=True, exist_ok=True)
    try:
        run(["swiftc", str(OCR_SWIFT), "-o", str(OCR_BIN)])
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"[warn] OCR helper unavailable: {exc}", file=sys.stderr)
        return False
    return True


def full_screenshot_size() -> tuple[int, int]:
    tmp_dir = ROOT / "outputs/qianniu_bot"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".png", dir=tmp_dir, delete=False) as tmp:
        path = Path(tmp.name)
    try:
        try:
            run(["screencapture", "-x", str(path)])
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            config = load_config()["reference_screenshot"]
            print(f"[warn] full screenshot failed, using reference size: {exc}", file=sys.stderr)
            return int(config["width_px"]), int(config["height_px"])
        if Image is None:
            config = load_config()["reference_screenshot"]
            return int(config["width_px"]), int(config["height_px"])
        with Image.open(path) as image:
            return image.size
    finally:
        path.unlink(missing_ok=True)


def region_box(region: dict[str, Any], screen_size: tuple[int, int]) -> Box:
    width, height = screen_size
    normalized = region["normalized_box"]
    x1 = round(normalized["x1"] * width)
    y1 = round(normalized["y1"] * height)
    x2 = round(normalized["x2"] * width)
    y2 = round(normalized["y2"] * height)
    return Box(x=x1, y=y1, width=max(1, x2 - x1), height=max(1, y2 - y1))


QIANNIU_UI_PROCESS_NAMES = ["千牛", "Aliworkbench"]


def qianniu_window_metrics() -> WindowMetrics | None:
    for process_name in QIANNIU_UI_PROCESS_NAMES:
        try:
            count_result = run([
                "osascript",
                "-e",
                f'tell application "System Events" to tell process "{process_name}" to get count of windows',
            ])
            window_count = int(count_result.stdout.strip())
            names_result = run([
                "osascript",
                "-e",
                f'tell application "System Events" to tell process "{process_name}" to get name of every window',
            ])
            positions_result = run([
                "osascript",
                "-e",
                f'tell application "System Events" to tell process "{process_name}" to get position of every window',
            ])
            sizes_result = run([
                "osascript",
                "-e",
                f'tell application "System Events" to tell process "{process_name}" to get size of every window',
            ])
        except Exception:
            continue
        if window_count <= 0:
            continue
        candidates: list[tuple[str, WindowMetrics]] = []
        names = [part.strip() for part in names_result.stdout.strip().split(", ")]
        positions = [part.strip() for part in positions_result.stdout.strip().split(", ")]
        sizes = [part.strip() for part in sizes_result.stdout.strip().split(", ")]
        if len(names) < window_count or len(positions) < window_count * 2 or len(sizes) < window_count * 2:
            # Fallback: query each window independently. This is slower, but avoids
            # AppleScript list-format edge cases in QianNiu/CEF windows.
            names = []
            positions = []
            sizes = []
            for index in range(1, window_count + 1):
                try:
                    name = run([
                        "osascript",
                        "-e",
                        f'tell application "System Events" to tell process "{process_name}" to get name of window {index}',
                    ]).stdout.strip()
                    position = run([
                        "osascript",
                        "-e",
                        f'tell application "System Events" to tell process "{process_name}" to get position of window {index}',
                    ]).stdout.strip()
                    size = run([
                        "osascript",
                        "-e",
                        f'tell application "System Events" to tell process "{process_name}" to get size of window {index}',
                    ]).stdout.strip()
                except Exception:
                    continue
                names.append(name)
                positions.extend(part.strip() for part in position.split(", "))
                sizes.extend(part.strip() for part in size.split(", "))
            if len(names) < window_count or len(positions) < window_count * 2 or len(sizes) < window_count * 2:
                continue
        for index, name in enumerate(names):
            position_offset = index * 2
            size_offset = index * 2
            try:
                metrics = WindowMetrics(
                    x=int(positions[position_offset]),
                    y=int(positions[position_offset + 1]),
                    width=int(sizes[size_offset]),
                    height=int(sizes[size_offset + 1]),
                )
            except (ValueError, IndexError):
                continue
            candidates.append((name, metrics))
        for name, metrics in candidates:
            if "接待中心" in name:
                return metrics
    print("[warn] QianNiu reception window not found; will not use main workbench window", file=sys.stderr)
    return None


def configured_window_metrics(config: dict[str, Any]) -> WindowMetrics | None:
    estimate = config.get("window_rule", {}).get("current_window_estimate_px")
    if not estimate:
        return None
    return WindowMetrics(
        x=int(estimate["x"]),
        y=int(estimate["y"]),
        width=int(estimate["width"]),
        height=int(estimate["height"]),
    )


def region_box_in_window(region: dict[str, Any], config: dict[str, Any], window: WindowMetrics) -> Box:
    reference = config["reference_screenshot"]
    ref_w = float(reference["width_px"])
    ref_h = float(reference["height_px"])
    annotated = region["annotated_box_px"]
    x1 = round(window.x + (annotated["x1"] / ref_w) * window.width)
    y1 = round(window.y + (annotated["y1"] / ref_h) * window.height)
    x2 = round(window.x + (annotated["x2"] / ref_w) * window.width)
    y2 = round(window.y + (annotated["y2"] / ref_h) * window.height)
    return Box(x=x1, y=y1, width=max(1, x2 - x1), height=max(1, y2 - y1))


def pin_qianniu_reception_window(config: dict[str, Any], *, raise_window: bool = False) -> bool:
    """Keep only the reception window on the configured secondary-display box.

    This deliberately avoids clicking or navigating the QianNiu main workbench.
    If the reception window is not already open, the bot waits instead of
    operating another window.
    """
    window = configured_window_metrics(config)
    if window is None:
        return False
    raise_line = 'perform action "AXRaise" of w' if raise_window else "-- keep background"
    saw_process = False
    last_error = ""
    for process_name in QIANNIU_UI_PROCESS_NAMES:
        script = (
            'tell application "System Events"\n'
            f'  if not (exists process "{process_name}") then return "missing_process"\n'
            f'  tell process "{process_name}"\n'
            '    repeat with w in windows\n'
            '      try\n'
            '        if (name of w as text) contains "接待中心" then\n'
            f'          set position of w to {{{window.x}, {window.y}}}\n'
            f'          set size of w to {{{window.width}, {window.height}}}\n'
            f'          {raise_line}\n'
            '          return "ok"\n'
            '        end if\n'
            '      end try\n'
            '    end repeat\n'
            '  end tell\n'
            'end tell\n'
            'return "missing_reception"'
        )
        try:
            status = osa_text(script)
        except Exception as exc:
            last_error = str(exc)
            continue
        if status == "missing_process":
            continue
        saw_process = True
        if status == "ok":
            return True
        last_error = status
    status = last_error or ("missing_reception" if saw_process else "missing_process")
    print(f"[hold] QianNiu reception window unavailable: {status}", file=sys.stderr)
    return False


def capture_box(box: Box, out_path: Path) -> bool:
    rect = f"{box.x},{box.y},{box.width},{box.height}"
    try:
        run(["screencapture", "-x", "-R", rect, str(out_path)])
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        detail = exc.stderr.strip() if isinstance(exc, subprocess.CalledProcessError) and exc.stderr else str(exc)
        print(f"[warn] region screenshot failed rect={rect}: {detail}", file=sys.stderr)
        if Image is None:
            return False
        with tempfile.NamedTemporaryFile(suffix=".png", dir=out_path.parent, delete=False) as tmp:
            full_path = Path(tmp.name)
        try:
            run(["screencapture", "-x", str(full_path)])
            with Image.open(full_path) as image:
                cropped = image.crop((box.x, box.y, box.x + box.width, box.y + box.height))
                cropped.save(out_path)
            print(f"[capture] used full-screen crop fallback rect={rect}", flush=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError, OSError) as fallback_exc:
            fallback_detail = (
                fallback_exc.stderr.strip()
                if isinstance(fallback_exc, subprocess.CalledProcessError) and fallback_exc.stderr
                else str(fallback_exc)
            )
            print(f"[warn] full screenshot fallback failed: {fallback_detail}", file=sys.stderr)
            return False
        finally:
            full_path.unlink(missing_ok=True)
    return True


def image_hash(path: Path) -> str:
    # Keep this exact. The chat area can change by only a few Chinese
    # characters, and a perceptual hash may miss that small-but-important
    # difference.
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _sort_rapid_ocr_item(item: Any) -> tuple[float, float]:
    box = item[0]
    xs = [float(point[0]) for point in box]
    ys = [float(point[1]) for point in box]
    return (sum(ys) / len(ys), sum(xs) / len(xs))


def ocr_image_rapid_in_process(path: Path, min_confidence: float = 0.45) -> str:
    global _RAPID_OCR_ENGINE
    try:
        from rapidocr_onnxruntime import RapidOCR
    except Exception:
        return ""
    try:
        if _RAPID_OCR_ENGINE is None:
            _RAPID_OCR_ENGINE = RapidOCR()
        result, _elapsed = _RAPID_OCR_ENGINE(str(path))
    except Exception as exc:
        print(f"[warn] RapidOCR failed: {exc}", file=sys.stderr)
        return ""
    if not result:
        return ""
    lines: list[str] = []
    for item in sorted(result, key=_sort_rapid_ocr_item):
        _box, text, confidence = item
        if float(confidence) < min_confidence:
            continue
        line = str(text).strip()
        if line:
            lines.append(line)
    return "\n".join(lines)


def ocr_image_rapid_subprocess(path: Path) -> str:
    if not (OCR_VENV_PYTHON.exists() and OCR_RAPID.exists()):
        return ""
    try:
        result = run([str(OCR_VENV_PYTHON), str(OCR_RAPID), str(path)], check=False)
    except Exception as exc:
        print(f"[warn] RapidOCR subprocess failed: {exc}", file=sys.stderr)
        return ""
    if result.returncode != 0:
        print(result.stderr.strip(), file=sys.stderr)
        return ""
    return result.stdout.strip()


def ocr_image_vision(path: Path) -> str:
    if not ensure_ocr_helper():
        return ""
    try:
        result = run([str(OCR_BIN), str(path)], check=False)
    except Exception as exc:
        print(f"[warn] OCR failed: {exc}", file=sys.stderr)
        return ""
    if result.returncode != 0:
        print(result.stderr.strip(), file=sys.stderr)
        return ""
    return result.stdout.strip()


def ocr_image(path: Path) -> str:
    text = ocr_image_rapid_in_process(path)
    if text:
        return text
    text = ocr_image_rapid_subprocess(path)
    if text:
        return text
    return ocr_image_vision(path)


def clean_ocr_lines(text: str) -> list[str]:
    lines: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if any(hint in line for hint in SYSTEM_NOTICE_HINTS):
            continue
        for pattern in NOISE_PATTERNS:
            line = re.sub(pattern, "", line).strip()
        if not line:
            continue
        if any(hint in line for hint in SYSTEM_NOTICE_HINTS):
            continue
        if len(line) <= 1 and not line.isdigit():
            continue
        lines.append(line)
    return lines


def extract_latest_customer_message(ocr_text: str) -> str:
    messages = extract_customer_messages(ocr_text)
    return messages[-1] if messages else ""


def extract_customer_messages(ocr_text: str) -> list[str]:
    return [turn["message"] for turn in extract_customer_turns(ocr_text)]


def extract_customer_turns(ocr_text: str) -> list[dict[str, str]]:
    return [event for event in extract_message_events(ocr_text) if event["speaker"] == "customer"]


def clean_customer_turns(turns: list[dict[str, str]]) -> list[dict[str, str]]:
    cleaned: list[dict[str, str]] = []
    for turn in turns:
        message = str(turn.get("message") or "").strip()
        if not is_valid_customer_message(message):
            continue
        if any(hint in message for hint in SYSTEM_NOTICE_HINTS):
            continue
        cleaned.append(turn)
    return cleaned


def extract_message_events(ocr_text: str) -> list[dict[str, str]]:
    lines = clean_ocr_lines(ocr_text)
    speaker = "unknown"
    buyer_id = ""
    events: list[dict[str, str]] = []
    # Shop replies can follow customer questions, so parse speaker markers in
    # order. The sender of the last visible message matters: if the latest
    # visible message is ours, there is no new customer question to answer.
    for line in lines:
        buyer_match = re.search(r"\btb\d{5,}\b", line)
        if buyer_match:
            speaker = "customer"
            buyer_id = buyer_match.group(0)
            continue
        if "grozziie" in line.lower() or "格志旗舰店" in line:
            speaker = "shop"
            continue
        if re.search(r"\d{4}-\d{1,2}-\d{1,2}", line) or re.search(r"^\d{1,2}:\d{2}", line):
            continue
        if line in {"OKOK", "OK", "好的"}:
            continue
        if speaker in {"customer", "shop"}:
            events.append({"speaker": speaker, "buyer_id": buyer_id if speaker == "customer" else "", "message": line})
    return events


def message_key(buyer_id: str, message: str) -> str:
    compact = re.sub(r"\s+", "", message).lower()
    compact = re.sub(r"[，。,.!?！？、:：`'\"“”‘’（）()]", "", compact)
    compact = compact[:180]
    return f"{buyer_id}|{compact}" if buyer_id else compact


def is_probable_own_reply(message: str, last_reply: str) -> bool:
    if not message or not last_reply:
        return False
    msg = message_key("", message)
    reply = message_key("", last_reply)
    if not msg or not reply:
        return False
    return msg == reply or msg in reply or reply in msg


def append_unique_recent(values: list[str], additions: list[str], limit: int = 500) -> list[str]:
    seen: set[str] = set()
    merged: list[str] = []
    for value in [*values, *additions]:
        if not value or value in seen:
            continue
        seen.add(value)
        merged.append(value)
    return merged[-limit:]


def is_order_query(message: str) -> bool:
    return any(hint in message for hint in ORDER_HINTS)


def has_high_risk_hint(message: str) -> bool:
    return any(hint in message for hint in HIGH_RISK_HINTS)


def detect_context_product(message: str) -> str:
    compact = re.sub(r"\s+", "", message.lower())
    if any(term in compact for term in ["考勤", "打卡", "m880", "纸卡", "上下班", "班次", "响铃"]):
        return "考勤机 M880"
    if any(term in compact for term in ["针打", "针式", "td630", "ak890", "票据打印"]):
        return "针式打印机"
    if any(term in compact for term in ["热敏", "标签", "面单"]):
        return "热敏打印机"
    return ""


def is_valid_customer_message(message: str) -> bool:
    compact = re.sub(r"\s+", "", message)
    if len(compact) < 2:
        return False
    for pattern in INVALID_CUSTOMER_MESSAGE_PATTERNS:
        if re.search(pattern, message, re.I):
            return False
    if len(compact) > 80 and re.search(r"[{}\"_=]{2,}", compact):
        return False
    return True


def build_safe_reply(
    message: str,
    order_text: str = "",
    product_context: str = "",
    rag_query_context: str = "",
) -> dict[str, Any]:
    context_compact = re.sub(r"\s+", "", rag_query_context.lower())
    message_compact = re.sub(r"\s+", "", message.lower())
    if (
        "色带" in context_compact
        and any(term in context_compact for term in ["多少次", "打卡多少", "能打"])
        and re.search(r"\d+.*员工.*\d+.*次", message_compact)
    ):
        numbers = [int(value) for value in re.findall(r"\d+", message_compact)]
        employees, times = numbers[0], numbers[1]
        daily_count = employees * times
        return {
            "reply": f"亲，按 {employees} 个员工每天打 {times} 次算，一天大概 {daily_count} 次。色带没有固定打卡次数，正常用到字迹变淡、断线时更换就可以哈。",
            "risk_level": "low",
            "auto_reply_allowed": True,
            "confidence": "high",
            "score": 999,
            "actions": [],
            "sources": ["quick_answer"],
            "matches": [{"id": "quick_answer_attendance_ribbon_count_followup", "type": "quick_answer"}],
        }
    base_query = rag_query_context or message
    if order_text:
        augmented = f"{base_query}\n订单区域可见信息：{order_text}"
    else:
        augmented = base_query
    result = build_reply(
        message,
        product=product_context or None,
        context=augmented,
        platform="Tmall",
    )
    reply = (result.get("reply") or "").strip()
    if not reply:
        reply = "亲，您这个问题我帮您确认一下哈。"
    if has_high_risk_hint(message):
        result["auto_reply_allowed"] = False
        result["risk_level"] = "high"
    result["reply"] = shorten_reply(reply)
    return result


def quick_answer(message: str, product_context: str = "") -> dict[str, Any] | None:
    return app_quick_answer(message, product=product_context or None)


def shorten_reply(reply: str, max_len: int = 90) -> str:
    reply = re.sub(r"\s+", " ", reply).strip()
    if len(reply) <= max_len:
        return reply
    cut = reply[:max_len].rstrip("，。,. ")
    return cut + "哈"


def osa(script: str) -> None:
    run(["osascript", "-e", script])


def osa_text(script: str) -> str:
    return run(["osascript", "-e", script]).stdout.strip()


def click_point(x: int, y: int) -> None:
    osa(f'tell application "System Events" to click at {{{x}, {y}}}')


def set_clipboard(text: str) -> None:
    proc = subprocess.run(["pbcopy"], input=text, text=True, check=True)
    if proc.returncode != 0:
        raise RuntimeError("pbcopy failed")


def activate_qianniu() -> bool:
    config = load_config()
    return pin_qianniu_reception_window(config, raise_window=True)


def focus_qianniu_input() -> bool:
    for process_name in QIANNIU_UI_PROCESS_NAMES:
        script = (
            'tell application "System Events"\n'
            f'  if not (exists process "{process_name}") then return "missing_process"\n'
            f'  tell process "{process_name}"\n'
            '    repeat with w in windows\n'
            '      try\n'
            '        if (name of w as text) contains "接待中心" then\n'
            '          set frontmost to true\n'
            '          perform action "AXRaise" of w\n'
            '          try\n'
            '            set focused of text area 1 of splitter group 1 of w to true\n'
            '          end try\n'
            '          try\n'
            '            click text area 1 of splitter group 1 of w\n'
            '          end try\n'
            '          return "ok"\n'
            '        end if\n'
            '      end try\n'
            '    end repeat\n'
            '  end tell\n'
            'end tell\n'
            'return "miss"'
        )
        try:
            status = osa_text(script)
        except Exception as exc:
            print(f"[warn] cannot focus QianNiu input by accessibility via {process_name}: {exc}", file=sys.stderr)
            continue
        if status == "ok":
            return True
    return False


def qianniu_ax(command: str, *values: str) -> bool:
    global _QIANNIU_AX_AVAILABLE
    if _QIANNIU_AX_AVAILABLE is False:
        return False
    if not QIANNIU_AX.exists():
        _QIANNIU_AX_AVAILABLE = False
        return False
    try:
        result = run([str(QIANNIU_AX), command, *values], check=False)
    except Exception as exc:
        print(f"[warn] QianNiu AX helper failed: {exc}", file=sys.stderr)
        _QIANNIU_AX_AVAILABLE = False
        return False
    if result.stdout.strip():
        print(f"[ax] {result.stdout.strip()}", flush=True)
    if result.returncode == 0:
        _QIANNIU_AX_AVAILABLE = True
        return True
    if result.stderr.strip():
        print(f"[warn] QianNiu AX helper {command} failed: {result.stderr.strip()}", file=sys.stderr)
    else:
        print(f"[warn] QianNiu AX helper {command} failed: code={result.returncode}", file=sys.stderr)
    if result.returncode in {3, 4, 5, 7}:
        _QIANNIU_AX_AVAILABLE = False
    return False


def paste_reply(input_box: Box, reply: str) -> None:
    if qianniu_ax("fill", reply):
        return
    if not activate_qianniu():
        print("[hold] not filling because reception window is unavailable", file=sys.stderr)
        return
    x, y = input_box.center
    try:
        if not focus_qianniu_input():
            click_point(x, y)
        set_clipboard(reply)
        osa('tell application "System Events" to keystroke "a" using command down')
        osa('tell application "System Events" to keystroke "v" using command down')
        print("[paste] reply filled", flush=True)
    except Exception as exc:
        print(f"[hold] cannot paste reply; check Accessibility permission: {exc}", file=sys.stderr)


def send_reply(send_box: Box) -> None:
    if qianniu_ax("send"):
        return
    if not activate_qianniu():
        print("[hold] not sending because reception window is unavailable", file=sys.stderr)
        return
    x, y = send_box.center
    try:
        if focus_qianniu_input():
            osa('tell application "System Events" to key code 36')
            print("[send] pressed Return in QianNiu input", flush=True)
            return
        click_point(x, y)
        print("[send] clicked send button", flush=True)
    except Exception as exc:
        print(f"[hold] cannot click send; check Accessibility permission: {exc}", file=sys.stderr)


def fill_and_send_reply(input_box: Box, send_box: Box, reply: str) -> None:
    if qianniu_ax("fill-send", reply):
        return
    paste_reply(input_box, reply)
    send_reply(send_box)


def send_image_message(input_box: Box, image_path: str) -> bool:
    """Paste one validated PNG into QianNiu and send it as an image message."""
    path = Path(image_path).resolve()
    asset_root = (ROOT / "assets/qianniu_video_materials").resolve()
    if asset_root not in path.parents or path.suffix.lower() != ".png" or not path.is_file():
        print(f"[media-fail] invalid image asset: {path}", file=sys.stderr)
        return False
    if not activate_qianniu():
        print("[media-fail] reception window unavailable", file=sys.stderr)
        return False
    try:
        if not focus_qianniu_input():
            click_point(*input_box.center)
        clipboard_script = (
            "on run argv\n"
            "set imageFile to POSIX file (item 1 of argv)\n"
            "set the clipboard to (read imageFile as «class PNGf»)\n"
            "end run"
        )
        result = run(["osascript", "-e", clipboard_script, str(path)], check=False)
        if result.returncode != 0:
            print(f"[media-fail] clipboard rejected PNG: {result.stderr.strip()}", file=sys.stderr)
            return False
        osa('tell application "System Events" to keystroke "v" using command down')
        time.sleep(0.6)
        osa('tell application "System Events" to key code 36')
        print(f"[media-send] {path.name}", flush=True)
        return True
    except Exception as exc:
        print(f"[media-fail] cannot send image: {exc}", file=sys.stderr)
        return False


def execute_reply_actions(
    actions: list[dict[str, Any]],
    *,
    send_image: Callable[[str], bool],
    send_text: Callable[[str], bool],
    log_event: Callable[[dict[str, Any]], None] | None = None,
) -> bool:
    """Execute ordered media actions, stopping immediately on any failure."""
    for index, action in enumerate(actions):
        action_type = str(action.get("type") or "")
        try:
            if action_type == "send_image":
                ok = send_image(str(action.get("path") or ""))
            elif action_type == "send_text":
                ok = send_text(str(action.get("text") or ""))
            else:
                ok = False
        except Exception as exc:
            ok = False
            error = repr(exc)
        else:
            error = "callback returned false" if not ok else ""
        if not ok:
            event = {
                "event": "media_send_failed",
                "action_index": index,
                "action_type": action_type,
                "error": error,
                "stopped_remaining_actions": len(actions) - index - 1,
                "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            }
            if log_event:
                log_event(event)
            print(f"[media-stop] {json.dumps(event, ensure_ascii=False)}", file=sys.stderr)
            return False
    return True


def load_state(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(path: Path, state: dict[str, Any]) -> None:
    try:
        path.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError as exc:
        print(f"[warn] cannot save bot state: {exc}", file=sys.stderr)


def append_jsonl(path: Path, payload: dict[str, Any]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(payload, ensure_ascii=False) + "\n")
    except OSError as exc:
        print(f"[warn] cannot write media log: {exc}", file=sys.stderr)


def resolve_reception_window(config: dict[str, Any], args: argparse.Namespace) -> WindowMetrics | None:
    if args.pin_reception_window:
        pin_qianniu_reception_window(config, raise_window=args.activate_before_scan)
    window = qianniu_window_metrics()
    if window is None and args.allow_configured_window_fallback:
        window = configured_window_metrics(config)
        if window is not None:
            print("[warn] using configured reception-window fallback coordinates", file=sys.stderr)
    return window


def monitor(args: argparse.Namespace) -> None:
    config = load_config()
    regions = config["regions"]
    screen_size = full_screenshot_size()
    window = None
    if args.window_relative:
        opened_missing_app = False
        while True:
            if args.open_qianniu_if_missing and not qianniu_process_running() and not opened_missing_app:
                opened_missing_app = open_qianniu_in_background()
                time.sleep(args.qianniu_open_wait)
            window = resolve_reception_window(config, args)
            if window is not None:
                break
            print("[hold] waiting for QianNiu reception window on the secondary display", flush=True)
            if args.once:
                return
            time.sleep(args.interval)

    if window:
        box_for = lambda region: region_box_in_window(region, config, window)
    else:
        box_for = lambda region: region_box(region, screen_size)

    chat_box = box_for(regions["current_chat_message_watch_area"])
    list_box = box_for(regions["conversation_list_watch_area"])
    input_box = box_for(regions["message_input_area"])
    send_box = box_for(regions["send_button"])
    order_box = box_for(regions["customer_order_status_area"])

    print(f"[start] screen={screen_size} interval={args.interval}s auto_send={args.auto_send}")
    if window:
        print(f"[window] {window}")
    print(f"[regions] chat={chat_box} list={list_box} input={input_box} send={send_box} order={order_box}")

    scan_count = 0
    work_dir = Path(args.output_dir)
    work_dir.mkdir(parents=True, exist_ok=True)
    state_path = work_dir / "state.json"
    state = load_state(state_path)
    last_chat_hash = ""
    last_list_hash = ""
    last_message = str(state.get("last_message") or "")
    last_message_key = str(state.get("last_message_key") or "")
    last_buyer_id = str(state.get("last_buyer_id") or "")
    product_context = str(state.get("product_context") or "")
    handled_message_keys = [
        str(value)
        for value in state.get("handled_message_keys", [])
        if isinstance(value, str) and value
    ]
    if last_message_key:
        handled_message_keys = append_unique_recent(handled_message_keys, [last_message_key])
    last_reply = str(state.get("last_reply") or "")
    baseline_ready = False

    while True:
        scan_count += 1
        if args.open_qianniu_if_missing and not qianniu_process_running():
            open_qianniu_in_background()
            time.sleep(args.qianniu_open_wait)
            if args.window_relative:
                window = resolve_reception_window(config, args)
                if window is None:
                    print("[hold] QianNiu reopened, but 接待中心 is not available yet", flush=True)
                    time.sleep(args.interval)
                    continue
        if args.pin_reception_window:
            pin_qianniu_reception_window(config, raise_window=args.activate_before_scan)
        if args.activate_before_scan:
            activate_qianniu()
            time.sleep(args.activate_delay)
        chat_img = work_dir / "current_chat.png"
        if not capture_box(chat_box, chat_img):
            if args.once:
                print("[stop] one-shot scan could not capture the chat region")
                return
            time.sleep(args.interval)
            continue
        current_chat_hash = image_hash(chat_img)

        force_ocr = args.force_ocr_every > 0 and scan_count % args.force_ocr_every == 0
        changed = current_chat_hash != last_chat_hash
        if not changed and args.watch_list:
            list_img = work_dir / "conversation_list.png"
            if capture_box(list_box, list_img):
                current_list_hash = image_hash(list_img)
                changed = current_list_hash != last_list_hash
                last_list_hash = current_list_hash

        if changed or force_ocr:
            ocr_text = ocr_image(chat_img)
            message_events = extract_message_events(ocr_text)
            customer_turns = clean_customer_turns([event for event in message_events if event["speaker"] == "customer"])
            visible_customer_keys = [message_key(turn.get("buyer_id", ""), turn.get("message", "")) for turn in customer_turns]
            latest_event = message_events[-1] if message_events else {}
            if not baseline_ready:
                known_before_baseline = set(handled_message_keys)
                handled_message_keys = append_unique_recent(handled_message_keys, visible_customer_keys)
                latest_customer_turn = customer_turns[-1] if customer_turns else {}
                latest_customer_key = ""
                if latest_event.get("speaker") == "customer":
                    latest_customer_key = message_key(latest_event.get("buyer_id", ""), latest_event.get("message", ""))
                if latest_customer_turn:
                    last_message = latest_customer_turn.get("message", "")
                    last_message_key = message_key(latest_customer_turn.get("buyer_id", ""), last_message)
                baseline_ready = True
                should_reply_on_start = (
                    latest_event.get("speaker") == "customer"
                    and latest_customer_key
                    and latest_customer_key not in known_before_baseline
                    and not is_probable_own_reply(latest_event.get("message", ""), last_reply)
                )
                if should_reply_on_start:
                    handled_message_keys = [key for key in handled_message_keys if key != latest_customer_key]
                    if args.verbose:
                        print("[baseline] latest visible customer message is new; replying on startup", flush=True)
                else:
                    save_state(state_path, {
                        "last_buyer_id": latest_customer_turn.get("buyer_id", "") if latest_customer_turn else "",
                        "last_message": last_message,
                        "last_message_key": last_message_key,
                        "last_reply": last_reply,
                        "handled_message_keys": handled_message_keys,
                        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                    })
                    if args.verbose:
                        print(f"[baseline] visible_customer_messages={len(visible_customer_keys)}; no reply sent", flush=True)
                    last_chat_hash = current_chat_hash
                    if args.once:
                        return
                    time.sleep(args.interval)
                    continue

            if latest_event.get("speaker") != "customer":
                if args.verbose:
                    print("[skip] latest visible message is not from customer", flush=True)
                last_chat_hash = current_chat_hash
                if args.once:
                    return
                time.sleep(args.interval)
                continue

            buyer_id = latest_event.get("buyer_id", "")
            message = latest_event.get("message", "")
            current_message_key = message_key(buyer_id, message)
            if message and current_message_key not in handled_message_keys:
                if is_probable_own_reply(message, last_reply):
                    handled_message_keys = append_unique_recent(handled_message_keys, [current_message_key])
                    print(f"[skip] latest OCR line looks like our previous reply: {message}", flush=True)
                    last_chat_hash = current_chat_hash
                    if args.once:
                        return
                    time.sleep(args.interval)
                    continue
                if buyer_id and buyer_id != last_buyer_id:
                    product_context = ""
                recent_customer_messages = [
                    turn.get("message", "")
                    for turn in customer_turns[-max(1, args.context_messages):]
                    if turn.get("message")
                ]
                query_context = "\n".join(dict.fromkeys(recent_customer_messages)) or message
                order_text = ""
                needs_product_context = (
                    not product_context
                    and any(term in query_context for term in ["色带", "纸卡", "卡纸", "考勤", "打卡", "机器", "这个"])
                )
                if is_order_query(query_context) or needs_product_context:
                    order_img = work_dir / "customer_order_status.png"
                    if capture_box(order_box, order_img):
                        order_text = ocr_image(order_img)
                detected_product = detect_context_product("\n".join([query_context, order_text]))
                if detected_product:
                    product_context = detected_product
                if not is_valid_customer_message(message):
                    handled_message_keys = append_unique_recent(handled_message_keys, [current_message_key])
                    print(f"[skip] invalid OCR/customer message: {message}", flush=True)
                    last_chat_hash = current_chat_hash
                    if args.once:
                        return
                    time.sleep(args.interval)
                    continue
                result = build_safe_reply(message, order_text, product_context, query_context)
                reply = result["reply"]
                print(json.dumps({
                    "buyer_id": buyer_id,
                    "message": message,
                    "query_context": query_context,
                    "reply": reply,
                    "risk_level": result.get("risk_level"),
                    "confidence": result.get("confidence"),
                    "score": result.get("score"),
                    "auto_reply_allowed": result.get("auto_reply_allowed"),
                    "top_match": (result.get("matches") or [{}])[0].get("id"),
                }, ensure_ascii=False), flush=True)
                if args.auto_send:
                    confident = result.get("confidence") != "low" and float(result.get("score") or 0) >= 60
                    should_send = bool(result.get("auto_reply_allowed", False) or (args.send_all_risk_levels and confident))
                    if should_send:
                        fill_and_send_reply(input_box, send_box, reply)
                        actions = result.get("actions") or []
                        if actions:
                            media_log = work_dir / "media_send_log.jsonl"
                            execute_reply_actions(
                                actions,
                                send_image=lambda path: send_image_message(input_box, path),
                                send_text=lambda text: (fill_and_send_reply(input_box, send_box, text) or True),
                                log_event=lambda event: append_jsonl(media_log, {
                                    **event,
                                    "buyer_id": buyer_id,
                                    "message_key": current_message_key,
                                    "top_match": (result.get("matches") or [{}])[0].get("id"),
                                }),
                            )
                        last_message = message
                        last_message_key = current_message_key
                        last_buyer_id = buyer_id
                        last_reply = reply
                        handled_message_keys = append_unique_recent(handled_message_keys, [current_message_key])
                        save_state(state_path, {
                            "last_buyer_id": buyer_id,
                            "last_message": last_message,
                            "last_message_key": last_message_key,
                            "last_reply": last_reply,
                            "product_context": product_context,
                            "handled_message_keys": handled_message_keys,
                            "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                        })
                    else:
                        print("[hold] not auto-send allowed; reply was not filled")
                        last_message = message
                        last_message_key = current_message_key
                        last_buyer_id = buyer_id
                        last_reply = reply
                        handled_message_keys = append_unique_recent(handled_message_keys, [current_message_key])
                        save_state(state_path, {
                            "last_buyer_id": buyer_id,
                            "last_message": last_message,
                            "last_message_key": last_message_key,
                            "last_reply": last_reply,
                            "product_context": product_context,
                            "handled_message_keys": handled_message_keys,
                            "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                        })
                elif args.fill:
                    paste_reply(input_box, reply)
                    last_message = message
                    last_message_key = current_message_key
                    last_buyer_id = buyer_id
                    last_reply = reply
                    handled_message_keys = append_unique_recent(handled_message_keys, [current_message_key])
                    save_state(state_path, {
                        "last_buyer_id": buyer_id,
                        "last_message": last_message,
                        "last_message_key": last_message_key,
                        "last_reply": last_reply,
                        "product_context": product_context,
                        "handled_message_keys": handled_message_keys,
                        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                    })
            elif args.verbose:
                print("[skip] customer message already handled")

        last_chat_hash = current_chat_hash
        if args.once:
            if args.verbose and last_reply:
                print(f"[last_reply] {last_reply}")
            return
        time.sleep(args.interval)


def main() -> None:
    parser = argparse.ArgumentParser(description="QianNiu fixed-window客服 auto-reply MVP")
    parser.add_argument("--interval", type=float, default=5.0, help="scan interval in seconds")
    parser.add_argument("--once", action="store_true", help="run one scan and exit")
    parser.add_argument("--fill", action="store_true", help="paste reply into the input box")
    parser.add_argument("--auto-send", action="store_true", help="paste and click send for allowed low-risk replies")
    parser.add_argument("--send-all-risk-levels", action="store_true", help="auto-send generated safe replies even when risk_level is medium/high")
    parser.add_argument("--watch-list", action="store_true", help="also watch the left conversation list")
    parser.add_argument("--context-messages", type=int, default=3, help="recent customer messages to include in RAG query")
    parser.add_argument("--force-ocr-every", type=int, default=2, help="force OCR every N scans even if the screenshot hash is unchanged")
    parser.add_argument("--activate-before-scan", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--activate-delay", type=float, default=0.25)
    parser.add_argument("--window-relative", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--pin-reception-window", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--open-qianniu-if-missing", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--qianniu-open-wait", type=float, default=5.0)
    parser.add_argument("--allow-configured-window-fallback", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--build-ocr-helper", action="store_true")
    parser.add_argument("--output-dir", default=str(ROOT / "outputs/qianniu_bot"))
    args = parser.parse_args()

    if args.build_ocr_helper:
        ok = ensure_ocr_helper()
        print(f"ocr_helper={'ok' if ok else 'failed'} path={OCR_BIN}")
        return
    monitor(args)


if __name__ == "__main__":
    main()
