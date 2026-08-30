#!/usr/bin/env python3
"""Build and verify the complete Grozziie China-market customer-service KB."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from datetime import date
from pathlib import Path
from typing import Iterable


PACKAGE_ROOT = "格志中国市场客服完整知识库-2026-08-16"
INCLUDE_DIRS = (
    "rag_cards",
    "rag_index",
    "assets/qianniu_video_materials",
    "sources",
    "scripts",
    "tests",
)
ROOT_SUPPORT_SUFFIXES = {".md", ".py", ".json", ".txt"}
EXCLUDED_PARTS = {
    ".git",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    "__pycache__",
    "outputs",
    "work",
    "tmp",
    "logs",
}


def _is_excluded(relative: Path) -> bool:
    return any(part in EXCLUDED_PARTS or part.startswith(".venv") for part in relative.parts)


def collect_package_files(root: Path) -> list[Path]:
    """Return stable, explicit payload files for the formal package."""
    root = root.resolve()
    selected: set[Path] = set()

    for path in root.iterdir():
        if path.is_file() and path.suffix.lower() in ROOT_SUPPORT_SUFFIXES:
            selected.add(path.resolve())

    for directory_name in INCLUDE_DIRS:
        directory = root / directory_name
        if not directory.is_dir():
            continue
        for path in directory.rglob("*"):
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(root)
            if _is_excluded(relative) or path.name in {".DS_Store"}:
                continue
            selected.add(path.resolve())

    return sorted(selected, key=lambda item: item.relative_to(root).as_posix())


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _manifest_entries(root: Path, files: Iterable[Path]) -> list[dict[str, object]]:
    return [
        {
            "path": path.relative_to(root).as_posix(),
            "size": path.stat().st_size,
            "sha256": _sha256_file(path),
        }
        for path in files
    ]


def _readme_text(manifest: dict[str, object]) -> str:
    return f"""# 格志中国市场客服完整知识库

生成日期：{manifest['created_on']}

本包用于格志在天猫、京东和拼多多中国市场的客服检索与售后排障，包含正式知识文档、RAG卡片与索引、国内平台视频截图素材、来源资料、运行脚本和测试。

使用要求：

- 必须严格核对机器型号和当前平台后，再发送唯一对应方案。
- 中国市场不得发送YouTube、海外平台视频或英文说明书。
- 证据不足或有多个处理分支时，每轮只问一个最能区分路径的问题。
- 知识库没有对应信息、安全问题、明确退款、明确改变收货地址或排障完成仍未解决时，按统一规则转人工。
- `PACKAGE_MANIFEST.json` 记录每个有效载荷文件的相对路径、大小和SHA-256，可用于完整性复核。

有效载荷文件数：{manifest['file_count']}
有效载荷未压缩字节数：{manifest['uncompressed_size']}
"""


def build_package(root: Path, output_zip: Path) -> dict[str, object]:
    root = root.resolve()
    output_zip = output_zip.resolve()
    files = collect_package_files(root)
    if not files:
        raise ValueError(f"no package files found under {root}")

    entries = _manifest_entries(root, files)
    manifest: dict[str, object] = {
        "package_name": PACKAGE_ROOT,
        "created_on": date.today().isoformat(),
        "file_count": len(entries),
        "uncompressed_size": sum(int(item["size"]) for item in entries),
        "files": entries,
    }
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    readme_bytes = _readme_text(manifest).encode("utf-8")

    output_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        archive.writestr(f"{PACKAGE_ROOT}/README.md", readme_bytes)
        archive.writestr(f"{PACKAGE_ROOT}/PACKAGE_MANIFEST.json", manifest_bytes)
        for path in files:
            relative = path.relative_to(root).as_posix()
            archive.write(path, f"{PACKAGE_ROOT}/{relative}")

    report: dict[str, object] = {
        "output": str(output_zip),
        "file_count": len(entries),
        "uncompressed_size": manifest["uncompressed_size"],
        "zip_size": output_zip.stat().st_size,
        "zip_sha256": _sha256_file(output_zip),
        "asset_file_count": sum(item["path"].startswith("assets/") for item in entries),
        "source_file_count": sum(item["path"].startswith("sources/") for item in entries),
    }
    return report


def verify_package(package: Path) -> dict[str, object]:
    package = package.resolve()
    with zipfile.ZipFile(package) as archive:
        bad_file = archive.testzip()
        if bad_file is not None:
            raise ValueError(f"corrupt archive member: {bad_file}")
        manifest_name = f"{PACKAGE_ROOT}/PACKAGE_MANIFEST.json"
        manifest = json.loads(archive.read(manifest_name))
        for item in manifest["files"]:
            archive_name = f"{PACKAGE_ROOT}/{item['path']}"
            content = archive.read(archive_name)
            if len(content) != item["size"]:
                raise ValueError(f"size mismatch: {item['path']}")
            if hashlib.sha256(content).hexdigest() != item["sha256"]:
                raise ValueError(f"sha256 mismatch: {item['path']}")

    return {
        "verified": True,
        "file_count": manifest["file_count"],
        "uncompressed_size": manifest["uncompressed_size"],
        "zip_size": package.stat().st_size,
        "zip_sha256": _sha256_file(package),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify", action="store_true", help="verify every manifest hash after building")
    args = parser.parse_args()

    report = build_package(args.root, args.output)
    if args.verify:
        report["verification"] = verify_package(args.output)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
