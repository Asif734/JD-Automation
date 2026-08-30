from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SEARCH = ROOT / "scripts" / "search_rag.py"


def search(query: str) -> list[dict]:
    result = subprocess.run(
        [sys.executable, str(SEARCH), query, "--json", "--top-k", "3"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout)


def test_td630_long_term_noise_with_normal_output_is_normal_characteristic() -> None:
    result = search("TD630一直打印慢声音大但是进纸和打印正常")

    assert result[0]["id"] == "dot_matrix_td630_normal_speed_noise"
    assert "针式击打" in result[0]["reply_template"]
    assert "热敏打印机慢" in result[0]["reply_template"]


def test_td630_recent_change_does_not_use_normal_characteristic_reply() -> None:
    result = search("TD630最近突然打印变慢声音刺耳还卡纸")

    assert result[0]["id"] != "dot_matrix_td630_normal_speed_noise"

