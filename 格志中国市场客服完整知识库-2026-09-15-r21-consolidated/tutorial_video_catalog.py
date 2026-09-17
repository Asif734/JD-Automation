"""Exact, platform-safe tutorial selection for China-market customer replies."""

from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent
CATALOG_PATH = ROOT / "rag_cards/china_market_video_catalog.json"
PLATFORM_ALIASES = {
    "jd": "JD",
    "京东": "JD",
    "tmall": "Tmall",
    "天猫": "Tmall",
    "qianniu": "Tmall",
    "千牛": "Tmall",
    "pinduoduo": "Pinduoduo",
    "拼多多": "Pinduoduo",
    "pdd": "Pinduoduo",
}
PLATFORM_LABELS = {"JD": "京东", "Tmall": "天猫", "Pinduoduo": "拼多多"}
ALLOWED_HOSTS = {
    "JD": {"vod.300hu.com", "jvod.300hu.com"},
    "Tmall": {"cloud.video.taobao.com"},
    "Pinduoduo": {"video5.pddpic.com"},
}
PRODUCT_ALIASES = {
    "smart_attendance_machine": "smart_attendance_machine",
    "智能考勤机": "smart_attendance_machine",
    "dot_matrix_printer": "dot_matrix_printer",
    "needle_printer": "dot_matrix_printer",
    "针式打印机": "dot_matrix_printer",
    "wifi_bluetooth_dot_matrix_printer": "wifi_bluetooth_dot_matrix_printer",
    "wifi_bluetooth_printer": "wifi_bluetooth_dot_matrix_printer",
    "wifi蓝牙针式打印机": "wifi_bluetooth_dot_matrix_printer",
    "thermal_printer": "thermal_printer",
    "热敏打印机": "thermal_printer",
    "bluetooth_attendance_machine": "bluetooth_attendance_machine",
    "蓝牙考勤机": "bluetooth_attendance_machine",
}


class TutorialCatalogError(RuntimeError):
    pass


def normalize_text(value: str) -> str:
    value = value.lower().replace("windows", "win")
    return re.sub(r"[^a-z0-9\u4e00-\u9fff]+", "", value)


def normalize_platform(value: str) -> str:
    platform = PLATFORM_ALIASES.get(normalize_text(value))
    if not platform:
        raise TutorialCatalogError(f"unsupported platform: {value}")
    return platform


def normalize_product_line(value: str | None) -> str | None:
    if not value:
        return None
    return PRODUCT_ALIASES.get(normalize_text(value), value if value in PRODUCT_ALIASES.values() else None)


def detect_product_line(message: str) -> str | None:
    compact = normalize_text(message)
    if any(term in compact for term in ["wifi针式", "wi-fi针式", "蓝牙针式", "手机针式"]):
        return "wifi_bluetooth_dot_matrix_printer"
    if "智能考勤机" in compact:
        return "smart_attendance_machine"
    if "蓝牙考勤机" in compact:
        return "bluetooth_attendance_machine"
    if "热敏" in compact:
        return "thermal_printer"
    if any(term in compact for term in ["针式", "针打"]):
        return "dot_matrix_printer"
    return None


def detect_operating_system(message: str) -> str | None:
    compact = normalize_text(message)
    if "win10" in compact:
        return "Windows 10"
    if "win11" in compact:
        return "Windows 11"
    return None


def load_catalog(path: Path = CATALOG_PATH) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _validate_url(platform: str, url: str) -> None:
    host = (urlparse(url).hostname or "").lower()
    if host not in ALLOWED_HOSTS[platform]:
        raise TutorialCatalogError(f"unexpected {platform} host: {host}")


def validate_catalog(catalog: dict | None = None) -> dict[str, int]:
    catalog = catalog or load_catalog()
    content_ids: set[str] = set()
    primary = 0
    alternates = 0
    for entry in catalog.get("entries", []):
        content_id = entry["content_id"]
        if content_id in content_ids:
            raise TutorialCatalogError(f"duplicate content_id: {content_id}")
        content_ids.add(content_id)
        for platform, url in entry.get("platform_urls", {}).items():
            _validate_url(platform, url)
            primary += 1
        for platform, urls in entry.get("alternate_platform_urls", {}).items():
            for url in urls:
                _validate_url(platform, url)
                alternates += 1
    return {
        "topics": len(catalog.get("entries", [])),
        "active_primary_links": primary,
        "active_alternate_links": alternates,
        "pending_assignments": len(catalog.get("pending_assignments", [])),
        "quarantined_assignments": len(catalog.get("quarantined_assignments", [])),
    }


def _phrase_score(message: str, phrase: str) -> int:
    compact = normalize_text(message)
    candidate = normalize_text(phrase)
    for context_term in ["针式打印机", "热敏打印机", "智能考勤机", "蓝牙考勤机", "打印机"]:
        candidate = candidate.replace(context_term, "")
    if len(candidate) < 2:
        return 0
    grams = {candidate[index:index + 2] for index in range(len(candidate) - 1)}
    hits = sum(gram in compact for gram in grams)
    coverage = hits / max(len(grams), 1)
    if hits < 2 or coverage < 0.48:
        return 0
    exact_bonus = 50 if candidate in compact else 0
    return hits * 20 + round(coverage * 100) + exact_bonus


def _compatible_product(entry_line: str, requested_line: str | None) -> bool:
    if requested_line is None:
        return True
    if entry_line == requested_line:
        return True
    return requested_line == "dot_matrix_printer" and entry_line == "wifi_bluetooth_dot_matrix_printer"


def match_tutorial(
    message: str,
    platform: str,
    *,
    product_line: str | None = None,
    operating_system: str | None = None,
) -> dict | None:
    """Return one exact approved tutorial; never fall back across platforms."""
    selected_platform = normalize_platform(platform)
    inferred_line = detect_product_line(message)
    requested_line = inferred_line or normalize_product_line(product_line)
    requested_os = detect_operating_system(message) or operating_system

    candidates: list[tuple[int, int, dict]] = []
    for entry in load_catalog()["entries"]:
        if not _compatible_product(entry["product_line"], requested_line):
            continue
        entry_os = entry.get("operating_system")
        if requested_os and entry_os and requested_os != entry_os:
            continue
        if entry["product_line"] == "thermal_printer" and not requested_os:
            # All thermal tutorials in this catalog are OS-specific.
            continue
        phrases = [entry["title_zh"], *entry.get("keywords", [])]
        score = max((_phrase_score(message, phrase) for phrase in phrases), default=0)
        if score:
            longest = max(len(normalize_text(phrase)) for phrase in phrases if _phrase_score(message, phrase) == score)
            candidates.append((score, longest, entry))

    if not candidates:
        return None
    candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)
    top_score, _, top = candidates[0]
    if len(candidates) > 1 and candidates[1][0] == top_score and candidates[1][2]["content_id"] != top["content_id"]:
        return None

    # Select the topic before checking platform availability. This prevents a
    # nearby but wrong tutorial from replacing a pending/quarantined link.
    if selected_platform not in top.get("platform_urls", {}):
        return None

    video_url = top["platform_urls"][selected_platform]
    _validate_url(selected_platform, video_url)
    return {
        "content_id": top["content_id"],
        "title_zh": top["title_zh"],
        "title_en": top["title_en"],
        "product_line": top["product_line"],
        "operating_system": top.get("operating_system"),
        "platform": selected_platform,
        "video_url": video_url,
        "alternate_video_urls": top.get("alternate_platform_urls", {}).get(selected_platform, []),
        "source_cells": top.get("platform_source_cells", {}).get(selected_platform, []),
        "analysis_status": top.get("analysis_status", "link_verified_only"),
        "score": top_score,
    }


def enrich_reply_with_tutorial(
    reply: str,
    message: str,
    platform: str | None,
    *,
    product_line: str | None = None,
    operating_system: str | None = None,
) -> dict:
    """Keep the written answer first and append at most one approved tutorial."""
    base = reply.strip()
    if not platform:
        return {"reply": base, "actions": [], "tutorial": None}
    tutorial = match_tutorial(
        message,
        platform,
        product_line=product_line,
        operating_system=operating_system,
    )
    if not tutorial:
        return {"reply": base, "actions": [], "tutorial": None}
    label = PLATFORM_LABELS[tutorial["platform"]]
    enriched = f"{base}\n操作视频（{label}）：{tutorial['video_url']}"
    return {
        "reply": enriched,
        "actions": [{
            "type": "send_video",
            "platform": tutorial["platform"],
            "url": tutorial["video_url"],
            "content_id": tutorial["content_id"],
            "title": tutorial["title_zh"],
        }],
        "tutorial": tutorial,
    }
