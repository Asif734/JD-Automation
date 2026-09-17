from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GUIDE = ROOT / "dot_matrix_windows_usb_driver_install_kb.md"
CARDS = ROOT / "rag_cards" / "customer_service_rag_cards.jsonl"
SEARCH = ROOT / "scripts" / "search_rag.py"
ASSET_DIR = (
    ROOT
    / "assets"
    / "qianniu_video_materials"
    / "dot_matrix_printer"
    / "windows_usb_driver_installation"
)
SOURCE_VIDEO = (
    ROOT
    / "sources"
    / "user_uploads"
    / "dot_matrix_driver_installation"
    / "nobel_auto_install_windows.mp4"
)


def load_card(card_id: str) -> dict:
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        card = json.loads(line)
        if card.get("id") == card_id:
            return card
    raise AssertionError(f"missing card: {card_id}")


def search(query: str) -> dict:
    result = subprocess.run(
        [sys.executable, str(SEARCH), query, "--json", "--top-k", "1"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout)[0]


def test_visual_guide_contains_verified_end_to_end_sequence() -> None:
    text = GUIDE.read_text(encoding="utf-8")

    assert "逐0.5秒抽帧核验，共检查205帧" in text
    assert "选择 **USB**" in text
    assert "点击 **Search**" in text
    assert "Installation successful" in text
    assert "打印测试页/Print test page" in text
    assert "1 document in queue" in text
    assert "不能仅凭“1 document in queue”断言纸张已经成功打印" in text


def test_all_visual_assets_and_source_video_are_packaged() -> None:
    assert SOURCE_VIDEO.is_file()
    expected = {f"{number:02d}_" for number in range(1, 16)}
    actual = {path.name[:3] for path in ASSET_DIR.glob("*.png")}

    assert actual == expected


def test_rag_card_preserves_detected_model_boundary_and_quick_steps() -> None:
    card = load_card("windows_usb_driver_install_visual_guide")

    assert "选中搜索到的打印机" in card["reply_template"]
    assert "让客户猜打印机型号" in card["do_not_say"]
    assert any(action["type"] == "send_visual_install_guide" for action in card["actions"])


def test_high_frequency_driver_install_query_hits_visual_guide() -> None:
    result = search("Windows USB驱动怎么安装")

    assert result["id"] == "windows_usb_driver_install_visual_guide"
