from __future__ import annotations

import json
from pathlib import Path

from scripts.package_grozziie_china_kb import collect_package_files
from scripts.search_rag import search


ROOT = Path(__file__).resolve().parents[1]
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
INDEX = ROOT / "rag_index/customer_service_rag_index.json"


def load_cards() -> dict[str, dict]:
    return {
        item["id"]: item
        for item in (
            json.loads(line)
            for line in CARDS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }


def test_complete_windows_driver_paper_size_workflow_is_retrievable() -> None:
    index = json.loads(INDEX.read_text(encoding="utf-8"))
    for query in [
        "针式打印机驱动里怎么设置纸张尺寸",
        "Configure里怎么设置固定页高",
        "整张二等分三等分连续纸选哪个尺寸",
    ]:
        assert search(index, query, top_k=1)[0]["id"] == "dot_matrix_fixed_page_height_exact_path"

    reply = load_cards()["dot_matrix_fixed_page_height_exact_path"]["reply_template"]
    for required in [
        "高级",
        "纸张/输出",
        "纸张规格",
        "Configure",
        "固定页面高度",
        "删除页面底部空白",
        "删除左边空白页",
        "删除页面顶部空白",
        "将位图图像输出到计算机",
        "纸边孔长计算",
        "单向打印保持原设置",
        "导入",
        "完全关闭并重新打开打印软件",
        "取出纸张",
        "重新装入",
    ]:
        assert required in reply
    assert "只保留第一个选项" not in reply
    assert "Configure-" not in reply


def test_driver_page_heights_use_division_terms_and_confirmed_hole_values() -> None:
    cards = load_cards()
    sizes = cards["dot_matrix_continuous_paper_standard_sizes"]["reply_template"]
    for required in [
        "三等分",
        "93.1mm",
        "holes 22/3",
        "101.6mm",
        "holes 8",
        "127mm",
        "holes 10",
        "二等分",
        "139.7mm",
        "holes 11",
        "整张",
        "279.4mm",
        "holes 22",
    ]:
        assert required in sizes
    assert "二联241" not in sizes
    assert "三联241" not in sizes
    assert "单边7孔" not in sizes


def test_all_paper_setting_replies_require_software_restart_and_paper_reload() -> None:
    cards = load_cards()
    for card_id in [
        "dot_matrix_print_offset",
        "dot_matrix_fixed_page_height_refeed",
        "dot_matrix_fixed_page_height_exact_path",
        "dot_matrix_tear_off_second_title_alignment",
        "dot_matrix_standard_bisection_fixed_page_height",
    ]:
        reply = cards[card_id]["reply_template"]
        assert "完全关闭并重新打开打印软件" in reply
        assert "取出纸张" in reply
        assert "重新装入" in reply


def test_video_source_is_part_of_the_current_database_package() -> None:
    relative_paths = {
        path.relative_to(ROOT).as_posix() for path in collect_package_files(ROOT)
    }
    assert (
        "sources/user_uploads/dot_matrix_paper_size/"
        "windows_driver_continuous_paper_size.mp4"
    ) in relative_paths
