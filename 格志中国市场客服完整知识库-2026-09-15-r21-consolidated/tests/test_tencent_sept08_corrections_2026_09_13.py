from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards/high_frequency_queries.json"
SEARCH = ROOT / "scripts/search_rag.py"


def load_cards() -> dict[str, dict]:
    return {
        card["id"]: card
        for card in (
            json.loads(line)
            for line in CARDS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }


def top(query: str) -> dict:
    result = subprocess.run(
        [sys.executable, str(SEARCH), query, "--json", "--top-k", "1"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout)[0]


def test_paper_feeds_but_stationary_head_routes_to_hardware_diagnosis() -> None:
    result = top("纸张正常走但打印头在中间不动")
    assert result["id"] == "dot_matrix_loud_noise_printhead_stuck"
    assert "关机断电并取下色带" in result["reply_template"]
    assert "自动左右移动" in result["reply_template"]
    assert "只走纸且打印头不动时检查驱动、端口和连接" not in result["reply_template"]
    assert "只有打印任务没有到达机器、没有走纸动作时" in result["reply_template"]


def test_td630_rear_continuous_feed_routes_to_supported_model_guidance() -> None:
    result = top("TD630支持后进连续纸吗")
    assert result["id"] == "dot_matrix_model_feed_modes"
    assert "TD630、TD630G和AK915支持前进纸与后进连续纸" in result["reply_template"]
    td630 = load_cards()["dot_matrix_model_feed_modes"]["quick_replies"]["TD630"]
    assert "支持前进纸和后进纸" in td630
    assert "连续纸" in td630
    assert "不支持后进纸" not in td630


def test_all_rear_feed_workflow_cards_include_td630() -> None:
    cards = load_cards()
    for card_id in (
        "dot_matrix_fixed_page_height_refeed",
        "dot_matrix_fixed_page_height_exact_path",
        "dot_matrix_tear_position_correct_setup",
    ):
        assert "TD630" in cards[card_id]["models"], card_id


def test_confirmed_resolutions_are_attached_to_the_controlling_cards() -> None:
    cards = load_cards()
    assert cards["dot_matrix_loud_noise_printhead_stuck"]["resolution_id"] == "U01"
    assert cards["dot_matrix_model_feed_modes"]["resolution_id"] == "U02"


def test_exact_queries_exist_for_both_confirmed_resolutions() -> None:
    mappings = {
        "".join(item["query"].lower().split()): item["card_id"]
        for item in json.loads(HF.read_text(encoding="utf-8"))["queries"]
    }
    assert mappings["纸张正常走但打印头在中间不动"] == "dot_matrix_loud_noise_printhead_stuck"
    assert mappings["td630支持后进连续纸吗"] == "dot_matrix_model_feed_modes"


def test_rebuilt_index_contains_no_rejected_u01_or_u02_rule() -> None:
    chunks = (ROOT / "rag_cards/source_chunks.jsonl").read_text(encoding="utf-8")
    index = (ROOT / "rag_index/customer_service_rag_index.json").read_text(encoding="utf-8")
    rejected = (
        "只走纸且打印头不动时检查驱动、端口和连接",
        "TD630 | 支持 | 不支持 | 不支持",
        "TD630、AK910、AK890：不得发送后进纸或连续打印教程",
        "TD630：仅前部平推单张进纸，不支持后进纸和连续打印",
    )
    for phrase in rejected:
        assert phrase not in chunks
        assert phrase not in index
