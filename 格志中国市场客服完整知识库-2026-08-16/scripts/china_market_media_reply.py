#!/usr/bin/env python3
"""Build a validated China-market customer-service media reply sequence."""

from __future__ import annotations

import argparse
import json
import re
from urllib.parse import urlparse


PLATFORM_HOSTS = {
    "Tmall": ("taobao.com",),
    "JD": ("300hu.com",),
    "Pinduoduo": ("pddpic.com",),
}
BLOCKED_HOST_PARTS = ("youtube.com", "youtube-nocookie.com", "youtu.be")
CHINESE = re.compile(r"[\u4e00-\u9fff]")


def validate_video(platform: str, video_url: str) -> None:
    if platform not in PLATFORM_HOSTS:
        raise ValueError("平台必须是 Tmall、JD 或 Pinduoduo")
    lowered = video_url.lower()
    if any(domain in lowered for domain in BLOCKED_HOST_PARTS):
        raise ValueError("中国市场禁止发送境外视频链接")
    if lowered.endswith(".pdf") or "manual.pdf" in lowered or "english-manual" in lowered:
        raise ValueError("中国市场禁止发送英文说明书")
    host = (urlparse(video_url).hostname or "").lower()
    if not any(host == allowed or host.endswith(f".{allowed}") for allowed in PLATFORM_HOSTS[platform]):
        raise ValueError("视频链接与当前平台不匹配")


def build_media_reply(
    intro: str,
    platform: str,
    video_url: str,
    screenshots: list[dict[str, str]],
) -> list[dict[str, str]]:
    if not intro.strip():
        raise ValueError("必须先提供简短客服说明")
    validate_video(platform, video_url)
    if len(screenshots) > 2:
        raise ValueError("中国市场回复最多发送两张关键截图")

    items: list[dict[str, str]] = [
        {"type": "text", "content": intro.strip()},
        {"type": "video", "content": video_url, "platform": platform},
    ]
    for screenshot in screenshots:
        path = str(screenshot.get("path", "")).strip()
        description = str(screenshot.get("description", "")).strip()
        if not path or path.lower().endswith(".pdf"):
            raise ValueError("截图必须是有效图片，不能发送说明书PDF")
        if not CHINESE.search(description):
            raise ValueError("每张截图必须附中文操作说明")
        items.append({"type": "image", "content": path})
        items.append({"type": "text", "content": description})
    return items


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--intro", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--video-url", required=True)
    parser.add_argument("--screenshots-json", required=True)
    args = parser.parse_args()

    try:
        screenshots = json.loads(args.screenshots_json)
        if not isinstance(screenshots, list):
            raise ValueError("截图参数必须是列表")
        items = build_media_reply(args.intro, args.platform, args.video_url, screenshots)
    except (ValueError, json.JSONDecodeError) as error:
        print(str(error))
        return 2
    print(json.dumps(items, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
