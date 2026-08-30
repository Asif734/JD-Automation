from __future__ import annotations

import json
import zipfile
from pathlib import Path

from scripts.package_grozziie_china_kb import build_package, collect_package_files


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_ROOT = "格志中国市场客服完整知识库-2026-08-16"


def test_collect_package_files_includes_required_content_and_excludes_runtime_files() -> None:
    relative = {path.relative_to(ROOT).as_posix() for path in collect_package_files(ROOT)}

    assert "rag_cards/customer_service_rag_cards.jsonl" in relative
    assert "rag_index/customer_service_rag_index.json" in relative
    assert any(name.startswith("assets/qianniu_video_materials/") for name in relative)
    assert any(name.startswith("sources/") for name in relative)
    assert "scripts/search_rag.py" in relative
    assert not any("/.venv" in f"/{name}" for name in relative)
    assert not any("/__pycache__/" in f"/{name}/" for name in relative)
    assert not any(name.startswith("outputs/") for name in relative)


def test_package_contains_media_sources_rag_readme_and_valid_manifest(tmp_path: Path) -> None:
    output = tmp_path / "kb.zip"
    report = build_package(ROOT, output)

    with zipfile.ZipFile(output) as archive:
        names = set(archive.namelist())
        assert f"{PACKAGE_ROOT}/README.md" in names
        assert f"{PACKAGE_ROOT}/PACKAGE_MANIFEST.json" in names
        assert any(name.startswith(f"{PACKAGE_ROOT}/assets/qianniu_video_materials/") for name in names)
        assert any(name.startswith(f"{PACKAGE_ROOT}/sources/") for name in names)
        assert f"{PACKAGE_ROOT}/rag_index/customer_service_rag_index.json" in names
        assert archive.testzip() is None
        manifest = json.loads(archive.read(f"{PACKAGE_ROOT}/PACKAGE_MANIFEST.json"))

    assert manifest["file_count"] == report["file_count"]
    assert report["asset_file_count"] > 0
    assert report["source_file_count"] > 0
    assert report["file_count"] == len(manifest["files"])
    assert all(len(item["sha256"]) == 64 for item in manifest["files"])
