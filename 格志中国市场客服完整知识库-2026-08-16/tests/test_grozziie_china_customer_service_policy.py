from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "grozziie_china_policy.py"


def run_policy(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        text=True,
        capture_output=True,
        check=False,
    )


def route(message: str, *, knowledge_found: bool = True, exhausted: bool = False) -> dict:
    args = ["route", "--message", message]
    if knowledge_found:
        args.append("--knowledge-found")
    if exhausted:
        args.append("--troubleshooting-exhausted")
    result = run_policy(*args)
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout)


def test_refund_address_change_missing_knowledge_and_exhausted_route_to_human() -> None:
    assert route("我要退款")["reply"] == "转人工"
    assert route("请把收货地址改一下")["reply"] == "转人工"
    assert route("资料库没有的问题", knowledge_found=False)["reply"] == "转人工"
    assert route("已经全部排查过了", exhausted=True)["reply"] == "转人工"


def test_fire_warning_precedes_handoff() -> None:
    result = route("打印机着火冒烟了")

    assert result["handoff"] is True
    assert "立即停止使用" in result["reply"]
    assert "断电" in result["reply"]
    assert result["reply"].endswith("转人工")


def test_record_is_created_and_appended_chronologically(tmp_path: Path) -> None:
    first = run_policy(
        "append-record",
        "--root",
        str(tmp_path),
        "--user-id",
        "u100",
        "--customer",
        "第一次",
        "--service",
        "答复一",
    )
    second = run_policy(
        "append-record",
        "--root",
        str(tmp_path),
        "--user-id",
        "u100",
        "--customer",
        "第二次",
        "--service",
        "答复二",
    )

    assert first.returncode == 0, first.stdout + first.stderr
    assert second.returncode == 0, second.stdout + second.stderr
    assert (tmp_path / "u100.txt").read_text(encoding="utf-8") == (
        "客户：第一次\n客服：答复一\n客户：第二次\n客服：答复二\n"
    )


def test_missing_or_unsafe_user_id_is_rejected(tmp_path: Path) -> None:
    missing = run_policy(
        "append-record",
        "--root",
        str(tmp_path),
        "--user-id",
        "",
        "--customer",
        "问题",
        "--service",
        "回复",
    )
    traversal = run_policy(
        "append-record",
        "--root",
        str(tmp_path),
        "--user-id",
        "../other",
        "--customer",
        "问题",
        "--service",
        "回复",
    )

    assert missing.returncode == 2
    assert traversal.returncode == 2
    assert list(tmp_path.iterdir()) == []
