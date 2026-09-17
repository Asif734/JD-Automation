#!/usr/bin/env python3
"""Audit release integrity and every confirmed resolved-conflict invariant."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

try:
    from scripts.package_version import PACKAGE_ROOT, PACKAGE_VERSION
except ModuleNotFoundError:  # Direct execution from scripts/.
    from package_version import PACKAGE_ROOT, PACKAGE_VERSION


EXPECTED_RESOLUTIONS = (
    {f"C{number:02d}" for number in range(1, 21)}
    | {"U01", "U02"}
    | {f"S13-C{number:02d}" for number in range(1, 16)}
    | {f"S14AM-C{number:02d}" for number in range(1, 30)}
)


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", value.lower())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def audit(root: Path) -> dict[str, object]:
    root = root.resolve()
    checks: dict[str, object] = {}
    conflicts: list[dict[str, str]] = []

    def conflict(code: str, message: str, path: str) -> None:
        conflicts.append({"code": code, "message": message, "path": path})

    cards = load_jsonl(root / "rag_cards/customer_service_rag_cards.jsonl")
    active_cards = {item["id"]: item for item in cards if item.get("status") == "active"}
    card_ids = [item["id"] for item in cards]
    checks["cards_total"] = len(cards)
    checks["cards_active"] = len(active_cards)
    checks["card_ids_unique"] = len(card_ids) == len(set(card_ids))
    if not checks["card_ids_unique"]:
        conflict("DUPLICATE_CARD_ID", "RAG card IDs are not unique", "rag_cards/customer_service_rag_cards.jsonl")

    resolution_counts: Counter[str] = Counter()
    for item in active_cards.values():
        if item.get("resolution_id"):
            resolution_counts[item["resolution_id"]] += 1
        resolution_counts.update(item.get("resolution_ids", []))
    checks["resolution_cards"] = dict(sorted(resolution_counts.items()))
    for resolution in EXPECTED_RESOLUTIONS:
        if resolution_counts[resolution] != 1:
            conflict("RESOLUTION_CARD_COUNT", f"{resolution} has {resolution_counts[resolution]} active resolution cards; expected 1", "rag_cards/customer_service_rag_cards.jsonl")

    forbidden_roots = ("outputs/", "work/", "tmp/", "logs/")
    dangling_sources: list[str] = []
    runtime_sources: list[str] = []
    for item in active_cards.values():
        for source in item.get("source_files", []):
            if source.startswith(forbidden_roots):
                runtime_sources.append(f"{item['id']}:{source}")
            elif ":" not in source and not source.startswith(("http://", "https://")) and not (root / source).exists():
                dangling_sources.append(f"{item['id']}:{source}")
    checks["active_card_runtime_source_refs"] = runtime_sources
    checks["active_card_dangling_source_refs"] = dangling_sources
    for value in runtime_sources:
        conflict("EXCLUDED_RUNTIME_REFERENCE", value, "rag_cards/customer_service_rag_cards.jsonl")
    for value in dangling_sources:
        conflict("DANGLING_SOURCE_REFERENCE", value, "rag_cards/customer_service_rag_cards.jsonl")

    hf = json.loads((root / "rag_cards/high_frequency_queries.json").read_text(encoding="utf-8"))
    queries = hf["queries"]
    normalized_queries = [normalize(item["query"]) for item in queries]
    dangling_hf = sorted({item["card_id"] for item in queries if item["card_id"] not in active_cards})
    checks["high_frequency_queries"] = len(queries)
    checks["high_frequency_unique"] = len(normalized_queries) == len(set(normalized_queries))
    checks["high_frequency_dangling_card_ids"] = dangling_hf
    if not checks["high_frequency_unique"]:
        conflict("DUPLICATE_HIGH_FREQUENCY_QUERY", "Normalized high-frequency queries are not unique", "rag_cards/high_frequency_queries.json")
    for card_id in dangling_hf:
        conflict("DANGLING_HIGH_FREQUENCY_CARD", card_id, "rag_cards/high_frequency_queries.json")

    superseded_reply_phrases = (
        "该网站服务已关闭",
        "删除所有重复的在线/离线驱动",
        "删除所有重复驱动",
        "色带购买前核对打印机和色带型号",
        "更换同型号色带",
    )
    superseded_reply_hits: list[str] = []
    for card_id, item in active_cards.items():
        reply = item.get("reply_template", "")
        for phrase in superseded_reply_phrases:
            if phrase in reply:
                superseded_reply_hits.append(f"{card_id}:{phrase}")
    checks["active_card_superseded_reply_hits"] = superseded_reply_hits
    for value in superseded_reply_hits:
        conflict("SUPERSEDED_ACTIVE_REPLY", value, "rag_cards/customer_service_rag_cards.jsonl")

    chunks = load_jsonl(root / "rag_cards/source_chunks.jsonl")
    chunk_ids = [item["id"] for item in chunks]
    checks["source_chunks"] = len(chunks)
    checks["source_chunk_ids_unique"] = len(chunk_ids) == len(set(chunk_ids))
    if not checks["source_chunk_ids_unique"]:
        conflict("DUPLICATE_SOURCE_CHUNK_ID", "Source chunk IDs are not unique", "rag_cards/source_chunks.jsonl")

    index = json.loads((root / "rag_index/customer_service_rag_index.json").read_text(encoding="utf-8"))
    index_card_ids = {item["id"] for item in index["cards"]}
    index_chunk_ids = {item["id"] for item in index["source_chunks"]}
    expected_vector_ids = index_card_ids | index_chunk_ids
    checks["index_version"] = index["version"]
    checks["index_cards_match_active_cards"] = index_card_ids == set(active_cards)
    checks["index_chunks_match_source_chunks"] = index_chunk_ids == set(chunk_ids)
    checks["index_vectors_cover_documents"] = set(index["vectors"]) == expected_vector_ids
    checks["index_high_frequency_count"] = len(index["high_frequency"])
    if index["version"] != PACKAGE_VERSION:
        conflict("INDEX_VERSION", f"{index['version']} != {PACKAGE_VERSION}", "rag_index/customer_service_rag_index.json")
    if not checks["index_cards_match_active_cards"]:
        conflict("INDEX_CARD_DRIFT", "Index cards differ from active JSONL cards", "rag_index/customer_service_rag_index.json")
    if not checks["index_chunks_match_source_chunks"]:
        conflict("INDEX_CHUNK_DRIFT", "Index chunks differ from source_chunks.jsonl", "rag_index/customer_service_rag_index.json")
    if not checks["index_vectors_cover_documents"]:
        conflict("INDEX_VECTOR_DRIFT", "Index vector keys do not cover every indexed document exactly", "rag_index/customer_service_rag_index.json")

    catalog = json.loads((root / "rag_cards/china_market_video_catalog.json").read_text(encoding="utf-8"))
    inactive = catalog.get("pending_assignments", []) + catalog.get("quarantined_assignments", [])
    status_counts = Counter(item.get("status") for item in inactive)
    checks["video_catalog_version"] = catalog["version"]
    checks["video_entries"] = len(catalog["entries"])
    checks["inactive_assignment_statuses"] = dict(sorted(status_counts.items()))
    checks["sheet1_e70_quarantined"] = any(item.get("cell") == "Sheet1!E70" and item.get("status") == "quarantined_wrong_topic" for item in inactive)
    if catalog["version"] != PACKAGE_VERSION:
        conflict("CATALOG_VERSION", f"{catalog['version']} != {PACKAGE_VERSION}", "rag_cards/china_market_video_catalog.json")
    if status_counts["needs_reupload"] != 8:
        conflict("NEEDS_REUPLOAD_COUNT", f"Expected 8, found {status_counts['needs_reupload']}", "rag_cards/china_market_video_catalog.json")
    if not checks["sheet1_e70_quarantined"]:
        conflict("QUARANTINE_LOST", "Sheet1!E70 is not quarantined_wrong_topic", "rag_cards/china_market_video_catalog.json")

    checks["high_frequency_version"] = hf["version"]
    if hf["version"] != PACKAGE_VERSION:
        conflict("HF_VERSION", f"{hf['version']} != {PACKAGE_VERSION}", "rag_cards/high_frequency_queries.json")

    stale_rules = {
        "confirmed_dot_matrix_updates_2026_08_30_kb.md": ["标记位置 2", "完整解压安装包", "只走纸且打印头不动时检查驱动、端口和连接", "更换同型号色带架"],
        "confirmed_customer_service_updates_2026_08_18_kb.md": ["不支持顺丰"],
        "confirmed_dot_matrix_updates_2026_08_24_afternoon_kb.md": ["不支持顺丰", "删除所有重复的在线/离线驱动"],
        "confirmed_dot_matrix_panel_paper_position_2026_09_08_kb.md": ["长按关机"],
        "dot_matrix_feed_modes_kb.md": ["TD630 | 支持 | 不支持 | 不支持", "TD630、AK910、AK890：不得发送后进纸或连续打印教程"],
        "dot_matrix_product_selling_points_kb.md": ["TD630：仅前部平推单张进纸，不支持后进纸和连续打印"],
        "confirmed_unified_dot_matrix_driver_settings_2026_09_07_kb.md": ["`TD630`、`AK910`、`AK890` 不支持后进连续纸"],
        "confirmed_dot_matrix_sept5_review_updates_2026_09_07_kb.md": ["批量购买降价或申请优惠券时，转人工", "更换同型号色带架"],
        "all_platform_model_details_2026_09_09_kb.md": ["质量退货运费优先使用平台运费险"],
        "grozziie_china_customer_service_policy_kb.md": ["质量退货运费优先使用平台运费险"],
        "tmall_customer_service_rules.md": ["批量购买要求降价或申请优惠券时转人工", "退货使用平台运费险"],
        "scripts/package_grozziie_china_kb.py": ["运费优先走平台运费险", "Enter IP只用于Windows网络打印排查"],
        "scripts/apply_confirmed_2026_08_24_afternoon_dot_matrix_updates.py": ["针打驱动也适用热敏机或考勤机"],
        "confirmed_tencent_sept13_updates_2026_09_14_kb.md": ["该网站服务已关闭"],
        "dot_matrix_after_sales_issues_kb.md": ["先删除所有重复驱动或 `printdriver`", "更换同型号色带"],
        "confirmed_dot_matrix_updates_2026_08_25_morning_kb.md": ["更换同型号色带"],
        "confirmed_dot_matrix_review_updates_2026_08_31_kb.md": ["更换同型号色带"],
        "scripts/apply_confirmed_2026_09_13_conflict_remediation.py": ["再删除所有重复驱动"],
    }
    stale_hits: list[str] = []
    for relative, forbidden_phrases in stale_rules.items():
        text = (root / relative).read_text(encoding="utf-8")
        for phrase in forbidden_phrases:
            if phrase in text:
                stale_hits.append(f"{relative}:{phrase}")
    checks["stale_conflict_signatures"] = stale_hits
    for value in stale_hits:
        conflict("STALE_CONFLICT_SIGNATURE", value, value.split(":", 1)[0])

    authoritative_sources = [
        "confirmed_conflict_remediation_2026_09_13_kb.md",
        "confirmed_tencent_sept13_updates_2026_09_14_kb.md",
        "confirmed_tencent_sept14_am_updates_2026_09_14_kb.md",
    ]
    authoritative_text = "\n".join((root / source).read_text(encoding="utf-8") for source in authoritative_sources)
    chunks_for_updates = [item for item in chunks if item.get("source_file") in authoritative_sources]
    checks["authoritative_resolution_headings"] = sum(f"## {resolution}" in authoritative_text for resolution in EXPECTED_RESOLUTIONS)
    checks["authoritative_update_chunks"] = len(chunks_for_updates)
    if checks["authoritative_resolution_headings"] != len(EXPECTED_RESOLUTIONS) or not all(
        any(item.get("source_file") == source for item in chunks_for_updates) for source in authoritative_sources
    ):
        conflict("AUTHORITATIVE_UPDATE_INCOMPLETE", "Approved source headings/chunks are incomplete", ",".join(authoritative_sources))

    manifest_path = root / "PACKAGE_MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest_errors: list[str] = []
    for item in manifest["files"]:
        path = root / item["path"]
        if not path.is_file():
            manifest_errors.append(f"missing:{item['path']}")
        elif path.stat().st_size != item["size"]:
            manifest_errors.append(f"size:{item['path']}")
        elif sha256(path) != item["sha256"]:
            manifest_errors.append(f"sha256:{item['path']}")
    checks["manifest_package_name"] = manifest["package_name"]
    checks["manifest_file_count"] = manifest["file_count"]
    checks["manifest_integrity_errors"] = manifest_errors
    if manifest["package_name"] != PACKAGE_ROOT:
        conflict("MANIFEST_VERSION", f"{manifest['package_name']} != {PACKAGE_ROOT}", "PACKAGE_MANIFEST.json")
    for value in manifest_errors:
        conflict("MANIFEST_INTEGRITY", value, "PACKAGE_MANIFEST.json")

    return {
        "package_version": PACKAGE_VERSION,
        "package_root": PACKAGE_ROOT,
        "scope": "authoritative Markdown, active cards, high-frequency routes, source chunks, RAG index, video quarantine states, package manifest",
        "checks": checks,
        "unresolved_conflicts": conflicts,
        "unresolved_conflict_count": len(conflicts),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    result = audit(args.root)
    rendered = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 1 if result["unresolved_conflict_count"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
