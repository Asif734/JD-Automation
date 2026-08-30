from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "china_market_media_reply.py"


def run_builder(
    *,
    intro: str = "亲，请按下面教程操作",
    platform: str = "Tmall",
    video_url: str = "http://cloud.video.taobao.com/tutorial.mp4",
    screenshots: list[dict[str, str]] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--intro",
            intro,
            "--platform",
            platform,
            "--video-url",
            video_url,
            "--screenshots-json",
            json.dumps(screenshots or [], ensure_ascii=False),
        ],
        text=True,
        capture_output=True,
        check=False,
    )


def test_reply_order_is_intro_video_and_two_explained_images() -> None:
    result = run_builder(
        screenshots=[
            {"path": "one.png", "description": "长按设置键进入FF。"},
            {"path": "two.png", "description": "把第02组设置为00。"},
        ]
    )

    assert result.returncode == 0, result.stdout + result.stderr
    items = json.loads(result.stdout)
    assert [item["type"] for item in items] == [
        "text",
        "video",
        "image",
        "text",
        "image",
        "text",
    ]
    assert items[3]["content"] == "长按设置键进入FF。"
    assert items[5]["content"] == "把第02组设置为00。"


def test_overseas_video_is_rejected() -> None:
    result = run_builder(video_url="https://www.youtube.com/watch?v=example")

    assert result.returncode == 2
    assert "境外视频" in result.stdout


def test_english_manual_and_non_chinese_screenshot_are_rejected() -> None:
    manual = run_builder(video_url="https://example.com/TD630-English-Manual.pdf")
    english_image = run_builder(
        screenshots=[{"path": "manual-step.png", "description": "Open settings and click next."}]
    )

    assert manual.returncode == 2
    assert english_image.returncode == 2


def test_more_than_two_screenshots_are_rejected() -> None:
    result = run_builder(
        screenshots=[
            {"path": "1.png", "description": "步骤一。"},
            {"path": "2.png", "description": "步骤二。"},
            {"path": "3.png", "description": "步骤三。"},
        ]
    )

    assert result.returncode == 2
