from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SEARCH = ROOT / "scripts" / "search_rag.py"


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


def test_td630g_mac_is_usb_only() -> None:
    result = search("TD630G Mac无线打印")

    assert result["id"] == "dot_matrix_td630g_mac_usb_only"
    assert "USB" in result["reply_template"]
    assert "不支持Mac无线打印" in result["reply_template"]


def test_td630g_windows_multi_pc_uses_standard_ip_port() -> None:
    result = search("TD630G多台Windows电脑共享")

    assert result["id"] == "dot_matrix_td630g_windows_multi_pc_wifi"
    assert "2.4G" in result["reply_template"]
    assert "Standard TCP/IP Port" in result["reply_template"]


def test_td630g_iphone_uses_app_wifi_not_system_bluetooth_pairing() -> None:
    result = search("TD630G iPhone怎么连接")

    assert result["id"] == "dot_matrix_td630g_iphone_wifi_app"
    assert "Grozziie App" in result["reply_template"]
    assert "系统蓝牙页面" in result["reply_template"]

