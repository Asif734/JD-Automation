from __future__ import annotations

import json
import zipfile
from pathlib import Path

from scripts.package_grozziie_china_kb import build_package, collect_package_files
from scripts.package_version import PACKAGE_ROOT


ROOT = Path(__file__).resolve().parents[1]


def test_collect_package_files_includes_required_content_and_excludes_runtime_files() -> None:
    relative = {path.relative_to(ROOT).as_posix() for path in collect_package_files(ROOT)}

    assert "rag_cards/customer_service_rag_cards.jsonl" in relative
    assert "rag_index/customer_service_rag_index.json" in relative
    assert any(name.startswith("assets/qianniu_video_materials/") for name in relative)
    assert any(name.startswith("sources/") for name in relative)
    assert "scripts/search_rag.py" in relative
    assert "confirmed_dot_matrix_review_updates_2026_08_31_kb.md" in relative
    assert "confirmed_dot_matrix_tencent_review_updates_2026_09_07_kb.md" in relative
    assert "confirmed_unified_dot_matrix_driver_settings_2026_09_07_kb.md" in relative
    assert "confirmed_dot_matrix_sept5_review_updates_2026_09_07_kb.md" in relative
    assert "confirmed_dot_matrix_panel_paper_position_2026_09_08_kb.md" in relative
    assert "confirmed_dot_matrix_normal_audio_references_2026_09_08_kb.md" in relative
    assert "rag_cards/dot_matrix_audio_reference_profiles.json" in relative
    assert "rag_cards/china_market_video_catalog.json" in relative
    assert "tutorial_video_catalog.py" in relative
    assert "confirmed_china_market_video_catalog_and_response_sop_2026_09_09_kb.md" in relative
    assert "tests/test_china_market_video_catalog.py" in relative
    assert "tests/test_customer_service_video_response.py" in relative
    assert "scripts/dot_matrix_audio_matcher.py" in relative
    assert "tests/test_dot_matrix_audio_references_2026_09_08.py" in relative
    assert "sources/user_uploads/dot_matrix_normal_audio_2026_09_08/audio_reference_manifest.json" in relative
    assert "sources/user_uploads/dot_matrix_normal_audio_2026_09_08/normal_printing.m4a" in relative
    assert "tests/test_confirmed_sept5_dot_matrix_review_2026_09_07.py" in relative
    assert "tests/test_dot_matrix_panel_paper_position_2026_09_08.py" in relative
    assert "tests/test_aug31_reviewer_corrections_2026_09_03.py" in relative
    assert not any("/.venv" in f"/{name}" for name in relative)
    assert not any("/__pycache__/" in f"/{name}/" for name in relative)
    assert not any(name.startswith("outputs/") for name in relative)


def test_package_contains_media_sources_rag_readme_and_valid_manifest(tmp_path: Path) -> None:
    output = tmp_path / "kb.zip"
    manifest_before = (ROOT / "PACKAGE_MANIFEST.json").read_bytes()
    readme_before = (ROOT / "README.md").read_bytes()
    report = build_package(ROOT, output, sync_metadata=False)
    assert (ROOT / "PACKAGE_MANIFEST.json").read_bytes() == manifest_before
    assert (ROOT / "README.md").read_bytes() == readme_before

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
    assert manifest["package_name"] == PACKAGE_ROOT
    assert report["asset_file_count"] > 0
    assert report["source_file_count"] > 0
    assert report["file_count"] == len(manifest["files"])
    assert all(len(item["sha256"]) == 64 for item in manifest["files"])
