#!/usr/bin/env python3
"""Apply the user-confirmed U01-U02 Tencent Sept 08 corrections."""

from __future__ import annotations

import json
import re
from pathlib import Path

try:
    from scripts.package_version import PACKAGE_VERSION
except ModuleNotFoundError:
    from package_version import PACKAGE_VERSION


ROOT = Path(__file__).resolve().parents[1]
CARDS_PATH = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF_PATH = ROOT / "rag_cards/high_frequency_queries.json"
CATALOG_PATH = ROOT / "rag_cards/china_market_video_catalog.json"
SOURCE = "confirmed_conflict_remediation_2026_09_13_kb.md"


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", value.lower())


def ensure_source(card: dict) -> None:
    sources = card.setdefault("source_files", [])
    if SOURCE not in sources:
        sources.append(SOURCE)


def main() -> None:
    cards = [
        json.loads(line)
        for line in CARDS_PATH.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    by_id = {card["id"]: card for card in cards}

    u01 = by_id["dot_matrix_loud_noise_printhead_stuck"]
    u01.update(
        version=PACKAGE_VERSION,
        package_version=PACKAGE_VERSION,
        resolution_id="U01",
        issue="纸张走动但打印头停在中间、不移动或固定位置重复字符",
        reply_template=(
            "如果纸张正常走动但打印头停在中间不动，或同一位置连续打印圆圈/‘8’字符，"
            "请先关机断电并取下色带，清理打印头下方、周围和导轨上的可见异物；"
            "再开机只从外部观察打印头能否自动左右移动一次。仍不移动时，按字车电机或打印头机械故障转人工维修。"
            "只有打印任务没有到达机器、没有走纸动作时，才检查驱动、端口和连接。"
            "USB单一连接版本没有本机自检功能，不要求执行不存在的自检。"
        ),
        actions=[
            {"type": "power_off_remove_ribbon_check_under_head_and_rail"},
            {"type": "power_on_observe_left_right_motion_only"},
            {"type": "handoff_carriage_or_printhead_mechanical_fault_if_stationary"},
            {"type": "software_branch_only_when_job_does_not_reach_printer"},
        ],
        do_not_say=[
            "纸张已走动但打印头不动时只检查驱动、端口或连接",
            "通电时触摸或强推打印头",
            "要求USB单一连接版本执行不存在的本机自检",
        ],
    )
    ensure_source(u01)

    u02 = by_id["dot_matrix_model_feed_modes"]
    u02.update(
        version=PACKAGE_VERSION,
        package_version=PACKAGE_VERSION,
        resolution_id="U02",
        reply_template=(
            "先按型号确认进纸方式。TD630、TD630G和AK915支持前进纸与后进连续纸；TG890使用后进连续纸。"
            "使用连续纸时，把左右两侧各三个孔对称套在拖纸器/进纸夹上，锁紧并拉直，再按中间走纸键自动吸纸；"
            "固定页面高度要等于实际撕线间距。AK910、AK890不使用后进纸教程。"
        ),
        do_not_say=[
            "AK910支持连续打印",
            "AK890支持链轮后进纸",
            "编造机器上不存在的进纸选择器或进纸切换开关",
        ],
    )
    u02["quick_replies"]["TD630"] = "亲，TD630支持前进纸和后进纸，也支持后进连续纸。连续纸左右各三个孔对称套入拖纸器并锁紧后，按中间走纸键吸纸。"
    u02["actions"][1]["note"] = "不得向AK910、AK890发送后进纸或连续打印教程；TD630可使用后进连续纸教程。"
    ensure_source(u02)

    affected = {
        "dot_matrix_fixed_page_height_refeed",
        "dot_matrix_fixed_page_height_exact_path",
        "dot_matrix_tear_position_correct_setup",
        "dot_matrix_top_panel_controls",
    }
    for card_id in affected:
        card = by_id[card_id]
        card["version"] = PACKAGE_VERSION
        card["package_version"] = PACKAGE_VERSION
        ensure_source(card)
        models = card.get("models", [])
        if card_id != "dot_matrix_top_panel_controls" and "TD630" not in models:
            models.insert(0, "TD630")

    exact = by_id["dot_matrix_fixed_page_height_exact_path"]
    exact["reply_template"] = exact["reply_template"].replace(
        "仅用于TD630G、AK915、TG890等支持后进连续纸的型号。",
        "仅用于TD630、TD630G、AK915、TG890等支持后进连续纸的型号。",
    )
    exact["do_not_say"] = [
        item.replace("向TD630或AK910发送后进纸步骤", "向AK910发送后进纸步骤")
        for item in exact.get("do_not_say", [])
    ]

    panel = by_id["dot_matrix_top_panel_controls"]
    panel["reply_template"] = (
        "TD630和TD630G均支持前进纸和后进连续纸。电源键按一下开机；关机时先取纸，按住电源键到红灯闪烁后松开，"
        "仍不关机则断开电源供应。后进连续纸正确装好后再使用进纸/退纸和暂停/微退键；缺纸红灯表示当前未检测到纸张。"
    )
    panel["reply_template_en"] = (
        "TD630 and TD630G both support front feed and rear continuous paper. Press Power once to turn on. "
        "To shut down, remove paper, hold Power until the red light flashes, then release; disconnect power if it remains on. "
        "After rear tractor paper is loaded, use Feed/Eject and Pause/Micro Reverse as required."
    )

    CARDS_PATH.write_text(
        "".join(json.dumps(card, ensure_ascii=False, separators=(",", ":")) + "\n" for card in cards),
        encoding="utf-8",
    )

    hf = json.loads(HF_PATH.read_text(encoding="utf-8"))
    hf["version"] = PACKAGE_VERSION
    by_query = {normalize(item["query"]): item for item in hf["queries"]}
    additions = {
        "纸张正常走但打印头在中间不动": "dot_matrix_loud_noise_printhead_stuck",
        "TD630支持后进连续纸吗": "dot_matrix_model_feed_modes",
    }
    for query, card_id in additions.items():
        key = normalize(query)
        if key in by_query:
            by_query[key]["card_id"] = card_id
        else:
            item = {"query": query, "card_id": card_id}
            hf["queries"].append(item)
            by_query[key] = item
    HF_PATH.write_text(json.dumps(hf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    catalog["version"] = PACKAGE_VERSION
    CATALOG_PATH.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"cards={len(cards)} queries={len(hf['queries'])} version={PACKAGE_VERSION}")


if __name__ == "__main__":
    main()
