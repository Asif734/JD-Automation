from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class KnowledgeRecord:
    id: str
    record_type: str
    title: str
    content: str
    search_text: str
    product_line: str
    models: list[str] = field(default_factory=list)
    intent: str = ""
    risk_level: str = "low"
    auto_reply_allowed: bool = False
    keywords: list[str] = field(default_factory=list)
    synonyms: list[str] = field(default_factory=list)
    source_files: list[str] = field(default_factory=list)
    required_slots: list[str] = field(default_factory=list)
    actions: list[dict[str, Any]] = field(default_factory=list)
    media: list["KnowledgeMedia"] = field(default_factory=list)


@dataclass(frozen=True)
class KnowledgeMedia:
    media_id: str
    kind: str
    path: Path
    filename: str
    caption: str
    record_id: str
    product_line: str
    models: list[str]


@dataclass(frozen=True)
class KnowledgeCorpus:
    root: Path
    records: list[KnowledgeRecord]
    warnings: list[str]
    content_hash: str
    media: dict[str, KnowledgeMedia]


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".webm"}


def _media_paths(value: Any) -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    if isinstance(value, str):
        suffix = Path(value).suffix.lower()
        if suffix in IMAGE_EXTENSIONS | VIDEO_EXTENSIONS:
            found.append((value, ""))
    elif isinstance(value, list):
        for item in value:
            found.extend(_media_paths(item))
    elif isinstance(value, dict):
        path = value.get("path")
        if isinstance(path, str) and Path(path).suffix.lower() in IMAGE_EXTENSIONS | VIDEO_EXTENSIONS:
            found.append((path, str(value.get("description") or "")))
        for key, item in value.items():
            if key not in {"path", "description"}:
                found.extend(_media_paths(item))
    return found


def _card_media(root: Path, record_id: str, title: str, row: dict[str, Any]) -> list[KnowledgeMedia]:
    candidates: list[tuple[str, str]] = []
    for key in ("visual_evidence", "screenshots", "source_files"):
        candidates.extend(_media_paths(row.get(key)))
    result: list[KnowledgeMedia] = []
    seen_paths: set[Path] = set()
    for relative, description in candidates:
        path = (root / relative).resolve()
        try:
            path.relative_to(root.resolve())
        except ValueError:
            continue
        if not path.is_file() or path in seen_paths:
            continue
        seen_paths.add(path)
        kind = "image" if path.suffix.lower() in IMAGE_EXTENSIONS else "video"
        digest = hashlib.sha256(f"{record_id}:{relative}".encode()).hexdigest()[:20]
        result.append(KnowledgeMedia(
            media_id=f"kb_{digest}", kind=kind, path=path, filename=path.name,
            caption=description or f"{title} — {path.stem.replace('_', ' ')}",
            record_id=record_id, product_line=str(row.get("product_line") or "general"),
            models=[str(value) for value in row.get("models") or []],
        ))
    return result


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if line.strip():
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError as exc:
                    raise ValueError(f"Invalid JSON at {path}:{line_number}: {exc}") from exc
    return rows


def load_corpus(root: Path) -> KnowledgeCorpus:
    card_path = root / "rag_cards" / "customer_service_rag_cards.jsonl"
    chunk_path = root / "rag_cards" / "source_chunks.jsonl"
    if not card_path.is_file() or not chunk_path.is_file():
        raise FileNotFoundError(f"RAG files not found below {root}")

    warnings: list[str] = []
    records: list[KnowledgeRecord] = []
    seen: set[str] = set()
    media: dict[str, KnowledgeMedia] = {}
    for row in _read_jsonl(card_path):
        record_id = str(row.get("id") or "").strip()
        if not record_id or record_id in seen:
            raise ValueError(f"Missing or duplicate card id: {record_id!r}")
        seen.add(record_id)
        reply = str(row.get("reply_template") or row.get("exact_handoff_text") or "").strip()
        if not reply:
            warnings.append(f"Card {record_id} has no customer reply template")
        risk = str(row.get("risk_level") or "medium")
        if risk not in {"low", "medium", "high", "critical"}:
            warnings.append(f"Card {record_id} has unknown risk level {risk!r}")
            risk = "high"
        keywords = [str(value) for value in row.get("keywords") or []]
        synonyms = [str(value) for value in row.get("synonyms") or []]
        title = str(row.get("issue") or record_id)
        card_media = _card_media(root, record_id, title, row)
        media.update((item.media_id, item) for item in card_media)
        search_parts = [
            title,
            str(row.get("intent") or ""),
            str(row.get("product_line") or "general"),
            " ".join(str(value) for value in row.get("models") or []),
            " ".join(keywords),
            " ".join(synonyms),
            reply,
            " ".join(f"{item.filename} {item.caption}" for item in card_media),
        ]
        records.append(KnowledgeRecord(
            id=record_id, record_type="card", title=title, content=reply,
            search_text="\n".join(part for part in search_parts if part),
            product_line=str(row.get("product_line") or "general"),
            models=[str(value) for value in row.get("models") or []],
            intent=str(row.get("intent") or ""), risk_level=risk,
            auto_reply_allowed=bool(row.get("auto_reply_allowed", False)),
            keywords=keywords, synonyms=synonyms,
            source_files=[str(value) for value in row.get("source_files") or []],
            required_slots=[str(value) for value in row.get("required_slots") or []],
            actions=list(row.get("actions") or []),
            media=card_media,
        ))

    for row in _read_jsonl(chunk_path):
        record_id = str(row.get("id") or "").strip()
        if not record_id or record_id in seen:
            raise ValueError(f"Missing or duplicate chunk id: {record_id!r}")
        seen.add(record_id)
        title = str(row.get("title") or record_id)
        content = str(row.get("content") or "").strip()
        records.append(KnowledgeRecord(
            id=record_id, record_type="source_chunk", title=title, content=content,
            search_text=f"{title}\n{content}",
            product_line=str(row.get("product_line") or "general"),
            intent=str(row.get("intent") or ""),
            risk_level=str(row.get("risk_level") or "medium"),
            source_files=[str(row.get("source_file"))] if row.get("source_file") else [],
        ))

    digest = hashlib.sha256()
    for path in (card_path, chunk_path):
        digest.update(path.read_bytes())
    return KnowledgeCorpus(root=root.resolve(), records=records, warnings=warnings,
                           content_hash=digest.hexdigest(), media=media)
