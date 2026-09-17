from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts" / "check_china_market_external_video_links.py"


def run_checker(root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKER), "--root", str(root)],
        text=True,
        capture_output=True,
        check=False,
    )


def test_checker_rejects_youtube_domains(tmp_path: Path) -> None:
    (tmp_path / "knowledge.md").write_text(
        "海外视频：https://www.youtube.com/watch?v=example\n",
        encoding="utf-8",
    )

    result = run_checker(tmp_path)

    assert result.returncode == 1
    assert "knowledge.md" in result.stdout


def test_china_market_knowledge_contains_no_youtube_domains() -> None:
    result = run_checker(ROOT)

    assert result.returncode == 0, result.stdout + result.stderr

