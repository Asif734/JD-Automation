from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARDS = ROOT / "rag_cards" / "customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards" / "high_frequency_queries.json"
SEARCH = ROOT / "scripts" / "search_rag.py"


NEW_CARD_IDS = {
    "dot_matrix_top_panel_controls",
    "dot_matrix_connection_status_led_by_version",
    "dot_matrix_paper_ejection_hole_baselines",
    "dot_matrix_front_rear_normal_paper_positions",
}


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


def test_cards_capture_confirmed_panel_and_led_behavior() -> None:
    cards = load_cards()
    assert NEW_CARD_IDS <= cards.keys()

    panel = cards["dot_matrix_top_panel_controls"]["reply_template"]
    for phrase in ("按一下开机", "红灯闪烁后松开", "断开电源供应", "进纸/退纸", "暂停/微退", "缺纸红灯"):
        assert phrase in panel

    led = cards["dot_matrix_connection_status_led_by_version"]["reply_template"]
    for phrase in ("2–4秒", "持续闪烁", "未连接", "纯USB", "暂停"):
        assert phrase in led
    assert "闪烁就需要重新设置Wi-Fi" not in led


def test_cards_distinguish_physical_width_driver_width_and_hole_math() -> None:
    cards = load_cards()
    sizes = cards["dot_matrix_continuous_paper_standard_sizes"]["reply_template"]
    assert "实际纸宽约241mm" in sizes
    assert "驱动预设宽度为240mm" in sizes
    assert "22除以3" in sizes
    assert "不是22或23孔" in sizes

    baseline = cards["dot_matrix_paper_ejection_hole_baselines"]["reply_template"]
    for phrase in ("7⅓", "14–15", "三页约22", "二等分一页约11"):
        assert phrase in baseline


def test_cards_define_normal_front_and_rear_paper_positions() -> None:
    cards = load_cards()
    position = cards["dot_matrix_front_rear_normal_paper_positions"]["reply_template"]
    for phrase in ("后进连续纸", "一小段窄纸边", "内部钢杆", "约5厘米"):
        assert phrase in position


def test_qr_card_requires_scanning_inside_suyintong() -> None:
    card = load_cards()["dot_matrix_qr_code_types_china"]
    reply = card["reply_template"]
    assert "速印通App内" in reply
    assert "手机系统相机" in reply


def test_key_queries_retrieve_confirmed_panel_and_paper_cards() -> None:
    expected = {
        "TD630G开机后最右绿灯闪2到4秒正常吗": "dot_matrix_connection_status_led_by_version",
        "纯USB针式打印机右边绿灯一直亮是什么意思": "dot_matrix_connection_status_led_by_version",
        "TD630面板进纸退纸暂停微退怎么用": "dot_matrix_top_panel_controls",
        "三等分连续纸打印三页出来22个孔正常吗": "dot_matrix_paper_ejection_hole_baselines",
        "后进纸待机前面露出一小段纸正常吗": "dot_matrix_front_rear_normal_paper_positions",
        "前进单页纸吸进去5厘米到钢杆正常吗": "dot_matrix_front_rear_normal_paper_positions",
    }
    for query, card_id in expected.items():
        assert top(query)["id"] == card_id


def test_every_new_card_has_a_high_frequency_mapping() -> None:
    mappings = json.loads(HF.read_text(encoding="utf-8"))["queries"]
    mapped_ids = {item["card_id"] for item in mappings}
    assert NEW_CARD_IDS <= mapped_ids
