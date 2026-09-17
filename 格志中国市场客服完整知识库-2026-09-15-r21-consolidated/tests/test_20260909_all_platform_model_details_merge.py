from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "all_platform_model_details_2026_09_09_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
QUERIES = ROOT / "rag_cards/high_frequency_queries.json"
SOURCE_CHUNKS = ROOT / "rag_cards/source_chunks.jsonl"
SEARCH = ROOT / "scripts/search_rag.py"


def load_cards() -> dict[str, dict]:
    rows = [
        json.loads(line)
        for line in CARDS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert len(rows) == len({row["id"] for row in rows})
    return {row["id"]: row for row in rows}


def search(query: str) -> dict:
    completed = subprocess.run(
        [sys.executable, str(SEARCH), query, "--json", "--top-k", "1"],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    results = json.loads(completed.stdout)
    assert results, query
    return results[0]


def test_governed_source_records_provenance_and_import_filter() -> None:
    text = MASTER.read_text(encoding="utf-8")
    assert "D4990BF156EFA5A0374AF45BEC9F6AFC35F1B07A78740F6BAE73066E2F40015F" in text
    assert "Approved 或 Corrected" in text
    assert "Needs confirmation 和 Unreviewed 不得用于对客回答" in text
    assert "92" in text and "Current 38" in text and "Legacy 42" in text


def test_td630_and_td630g_customer_connection_boundary() -> None:
    cards = load_cards()
    reply = cards["dot_matrix_connectivity_os_support"]["reply_template"]
    assert "TD630售前按蓝牙+USB" in reply
    assert "手机速印通可用蓝牙或Wi-Fi" in reply
    assert "Windows/Mac电脑都只用USB" in reply
    assert "TD630G售前按蓝牙+Wi-Fi+USB" in reply
    assert "TD630与TD630G内部硬件" not in reply
    assert "披露TD630与TD630G内部硬件关系" in cards[
        "dot_matrix_connectivity_os_support"
    ]["do_not_say"]


def test_internal_shared_hardware_wording_is_not_customer_replyable() -> None:
    cards = load_cards()
    for card in cards.values():
        reply = card.get("reply_template", "")
        assert "采用相同硬件" not in reply
        assert "使用相同硬件" not in reply


def test_thermal_printhead_warranty_is_three_months_only() -> None:
    cards = load_cards()
    for card_id in ("thermal_warranty_policy", "thermal_warranty_selling_point"):
        reply = cards[card_id]["reply_template"]
        assert "3个月" in reply
        assert "30公里" not in reply
        assert "公里" not in reply


def test_thermal_width_macos_and_mobile_platform_rules() -> None:
    cards = load_cards()
    paper = cards["thermal_paper_label_size_selling_point"]["reply_template"]
    assert "30-80mm" in paper and "30-100mm" in paper and "TP876PLUS" in paper
    mac = cards["thermal_macos_model_boundary_20260909"]["reply_template"]
    assert "TP870和TP876不支持macOS" in mac
    for model in ("TP870PLUS", "TP876PLUS", "TP874", "TP874S"):
        assert model in mac
    mobile = cards["thermal_mobile_platform_direct_print_boundary"]["reply_template"]
    for phrase in ("千牛", "抖音/抖店", "PID", "拼多多", "1688", "快手", "风火递", "速印通"):
        assert phrase in mobile


def test_lifecycle_package_repair_and_return_policies() -> None:
    cards = load_cards()
    lifecycle = cards["global_model_lifecycle_presales_guard_20260909"]
    for model in ("GD550", "JPW560", "M880T", "TH680", "TH850", "TJYD810"):
        assert model in lifecycle["models"]
    package = cards["family_default_package_contents_20260909"]["reply_template"]
    for phrase in ("10张", "2张", "USB-A转USB-D", "50张", "2颗挂墙螺丝"):
        assert phrase in package
    repair = cards["repair_warranty_fee_high_risk"]["reply_template"]
    for phrase in ("50元", "80元", "150元", "单程运费", "寄回运费"):
        assert phrase in repair
    returns = cards["global_refund_return_high_risk"]["reply_template"]
    assert "7天无理由" in returns and "30天" in returns and "运费" in returns and "人工" in returns
    assert "运费险" not in returns
    assert cards["global_refund_return_high_risk"]["customer_shipping_protection_policy"] == (
        "do_not_instruct_customer_to_select_shipping_insurance_or_return_protection"
    )


def test_confirmed_queries_route_to_updated_cards() -> None:
    expected = {
        "TD630手机可以用WiFi打印吗": "dot_matrix_phone_document_print_bluetooth_first",
        "TD630电脑可以连接WiFi打印吗": "dot_matrix_connectivity_os_support",
        "TP870普通版支持Mac吗": "thermal_macos_model_boundary_20260909",
        "TP874能打多宽的纸": "thermal_paper_label_size_selling_point",
        "拼多多手机App可以直接打印热敏单吗": "thermal_mobile_platform_direct_print_boundary",
        "M880T现在还在卖吗": "global_model_lifecycle_presales_guard_20260909",
        "热敏机针式机考勤机维修分别多少钱": "repair_warranty_fee_high_risk",
        "热敏机默认送几张测试纸": "family_default_package_contents_20260909",
        "质量问题30天可以退换吗": "global_refund_return_high_risk",
        "热敏打印头保修是不是3个月或30公里": "thermal_warranty_policy",
    }
    query_map = {
        row["query"]: row["card_id"]
        for row in json.loads(QUERIES.read_text(encoding="utf-8"))["queries"]
    }
    for query, card_id in expected.items():
        assert query_map[query] == card_id
        assert search(query)["id"] == card_id


def test_governed_source_is_in_rebuilt_source_chunks() -> None:
    chunks = [
        json.loads(line)
        for line in SOURCE_CHUNKS.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    matching = [
        row for row in chunks
        if row["source_file"] == "all_platform_model_details_2026_09_09_kb.md"
    ]
    assert matching
    assert any("TD630 / TD630G 对客连接规则" in row["title"] for row in matching)


def run_all() -> None:
    module = sys.modules[__name__]
    tests = [getattr(module, name) for name in sorted(dir(module)) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"{len(tests)} tests passed")


if __name__ == "__main__":
    run_all()
