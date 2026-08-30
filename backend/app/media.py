from __future__ import annotations

import base64
import hashlib
import mimetypes
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

from fastapi import UploadFile

from .knowledge import KnowledgeCorpus
from .schemas import CatalogMediaItem, CatalogMediaUpdate, MediaItem, MediaSearchPlan

ALLOWED_MIME = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp",
                "image/gif": ".gif", "video/mp4": ".mp4", "video/quicktime": ".mov",
                "video/webm": ".webm"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".webm"}
MAX_IMAGE_BYTES = 15 * 1024 * 1024
MAX_VIDEO_BYTES = 50 * 1024 * 1024


@dataclass(frozen=True)
class StoredMedia:
    item: MediaItem
    path: Path
    mime_type: str


class MediaStore:
    def __init__(self, data_dir: Path, corpus: KnowledgeCorpus):
        self.upload_dir = data_dir / "uploads"
        self.upload_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = data_dir / "media.sqlite3"
        self.knowledge = corpus.media
        self.knowledge_root = corpus.root
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self) -> None:
        with self._connect() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript("""
                CREATE TABLE IF NOT EXISTS knowledge_media(
                  media_id TEXT PRIMARY KEY, record_id TEXT, kind TEXT NOT NULL,
                  filename TEXT NOT NULL, caption TEXT NOT NULL, product_line TEXT NOT NULL,
                  models_text TEXT NOT NULL, search_text TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS knowledge_media_kind ON knowledge_media(kind);
                CREATE TABLE IF NOT EXISTS uploaded_media(
                  media_id TEXT PRIMARY KEY, conversation_id TEXT, kind TEXT NOT NULL,
                  filename TEXT NOT NULL, stored_path TEXT NOT NULL, mime_type TEXT NOT NULL,
                  caption TEXT NOT NULL, size_bytes INTEGER NOT NULL,
                  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX IF NOT EXISTS uploaded_media_conversation
                  ON uploaded_media(conversation_id, created_at DESC);
            """)
            existing = {row["name"] for row in db.execute("PRAGMA table_info(knowledge_media)")}
            migrations = {"stored_path": "TEXT", "mime_type": "TEXT",
                          "view_type": "TEXT NOT NULL DEFAULT 'other'",
                          "purpose": "TEXT NOT NULL DEFAULT 'other'",
                          "verified": "INTEGER NOT NULL DEFAULT 0",
                          "customer_send_allowed": "INTEGER NOT NULL DEFAULT 0"}
            for column, declaration in migrations.items():
                if column not in existing:
                    db.execute(f"ALTER TABLE knowledge_media ADD COLUMN {column} {declaration}")
            db.execute("CREATE INDEX IF NOT EXISTS knowledge_media_review ON knowledge_media(verified, customer_send_allowed, product_line)")
            self._inventory_files(db)
            self._upsert_curated_media(db)

    def _inventory_files(self, db: sqlite3.Connection) -> None:
        linked = {item.path.resolve() for item in self.knowledge.values()}
        for path in self.knowledge_root.rglob("*"):
            if not path.is_file() or path.suffix.lower() not in IMAGE_EXTENSIONS | VIDEO_EXTENSIONS:
                continue
            if path.resolve() in linked:
                continue
            relative = path.resolve().relative_to(self.knowledge_root).as_posix()
            media_id = "asset_" + hashlib.sha256(relative.encode()).hexdigest()[:20]
            kind = "image" if path.suffix.lower() in IMAGE_EXTENSIONS else "video"
            models = self._suggest_models(relative)
            view, purpose = self._classify(path, relative)
            product_line = self._suggest_product_line(relative)
            caption = path.stem.replace("_", " ").replace("-", " ").strip() or path.name
            search_text = self._search_text(path.name, relative, product_line, models, view, purpose)
            db.execute("""INSERT INTO knowledge_media(
                media_id,record_id,kind,filename,caption,product_line,models_text,search_text,
                stored_path,mime_type,view_type,purpose,verified,customer_send_allowed)
                VALUES(?,'',?,?,?,?,?,?,?,?,?,?,0,0)
                ON CONFLICT(media_id) DO UPDATE SET stored_path=excluded.stored_path,
                mime_type=excluded.mime_type""",
                (media_id, kind, path.name, caption, product_line, " ".join(models), search_text,
                 str(path), mimetypes.guess_type(path.name)[0] or "application/octet-stream",
                 view, purpose))

    def _upsert_curated_media(self, db: sqlite3.Connection) -> None:
        for item in self.knowledge.values():
            view, purpose = self._classify(item.path, item.caption)
            if item.record_id in {"dot_matrix_model_dimensions",
                                  "attendance_card_rack_20_slot_dimensions"}:
                view, purpose = "exterior", "product_showcase"
            elif item.record_id == "dot_matrix_copy_capacity":
                view, purpose = "other", "instruction"
            search_text = self._search_text(item.filename, item.caption, item.product_line,
                                            item.models, view, purpose)
            db.execute("""INSERT INTO knowledge_media(
                media_id,record_id,kind,filename,caption,product_line,models_text,search_text,
                stored_path,mime_type,view_type,purpose,verified,customer_send_allowed)
                VALUES(?,?,?,?,?,?,?,?,?,?,?,?,1,1)
                ON CONFLICT(media_id) DO UPDATE SET record_id=excluded.record_id,
                kind=excluded.kind,filename=excluded.filename,caption=excluded.caption,
                product_line=excluded.product_line,models_text=excluded.models_text,
                search_text=excluded.search_text,stored_path=excluded.stored_path,
                mime_type=excluded.mime_type,view_type=excluded.view_type,purpose=excluded.purpose,
                verified=1,customer_send_allowed=1""",
                (item.media_id, item.record_id, item.kind, item.filename, item.caption,
                 item.product_line, " ".join(item.models), search_text, str(item.path),
                 mimetypes.guess_type(item.path.name)[0] or "application/octet-stream", view, purpose))

    @staticmethod
    def _suggest_models(value: str) -> list[str]:
        return list(dict.fromkeys(re.findall(
            r"\b(?:[A-Za-z]{1,5}[A-Za-z0-9-]*\d[A-Za-z0-9-]*)\b", value)))

    @staticmethod
    def _suggest_product_line(value: str) -> str:
        lowered = value.lower()
        if "attendance" in lowered or "考勤" in value:
            return "attendance_machine"
        if "thermal" in lowered or "热敏" in value:
            return "thermal_printer"
        if "needle" in lowered or "dot_matrix" in lowered or "针式" in value:
            return "dot_matrix_printer"
        return "general"

    @staticmethod
    def _classify(path: Path, description: str) -> tuple[str, str]:
        value = f"{path.as_posix()} {description}".lower()
        if any(term in value for term in ("rear", "internal", "battery", "后盖", "电池")):
            return "internal", "troubleshooting"
        if any(term in value for term in ("label", "铭牌", "标签")):
            return "label", "troubleshooting"
        if any(term in value for term in ("screen", "display", "界面", "屏幕")):
            return "screen", "instruction"
        if any(term in value for term in ("setup", "setting", "step", "设置", "安装", "教程")):
            return "setup", "instruction"
        if any(term in value for term in ("front", "side", "exterior", "外观", "正面", "侧面")):
            return "exterior", "product_showcase"
        return "other", "other"

    @staticmethod
    def _search_text(filename: str, caption: str, product_line: str,
                     models: list[str], view: str, purpose: str) -> str:
        return f"{filename} {caption} {product_line} {' '.join(models)} {view} {purpose}".lower()

    async def save_upload(self, upload: UploadFile, conversation_id: str | None,
                          caption: str) -> MediaItem:
        mime_type = (upload.content_type or "").lower()
        if mime_type not in ALLOWED_MIME:
            raise ValueError("Only JPEG, PNG, WebP, GIF, MP4, MOV, and WebM are supported")
        kind = "image" if mime_type.startswith("image/") else "video"
        maximum = MAX_IMAGE_BYTES if kind == "image" else MAX_VIDEO_BYTES
        content = await upload.read(maximum + 1)
        if len(content) > maximum:
            raise ValueError(f"{kind.title()} exceeds the {maximum // (1024 * 1024)} MB limit")
        if not content:
            raise ValueError("Uploaded media is empty")
        media_id = f"customer_{uuid4().hex}"
        path = self.upload_dir / f"{media_id}{ALLOWED_MIME[mime_type]}"
        path.write_bytes(content)
        safe_name = Path(upload.filename or path.name).name
        with self._connect() as db:
            db.execute("""INSERT INTO uploaded_media(media_id,conversation_id,kind,filename,
                stored_path,mime_type,caption,size_bytes) VALUES(?,?,?,?,?,?,?,?)""",
                (media_id, conversation_id, kind, safe_name, str(path), mime_type,
                 caption, len(content)))
        return MediaItem(media_id=media_id, kind=kind, filename=safe_name,
                         caption=caption, source="customer", url=f"/v1/media/{media_id}")

    def get(self, media_id: str) -> StoredMedia | None:
        with self._connect() as db:
            knowledge = db.execute("""SELECT * FROM knowledge_media WHERE media_id=?
                AND verified=1 AND customer_send_allowed=1""", (media_id,)).fetchone()
            if knowledge:
                path = Path(knowledge["stored_path"] or "")
                if path.is_file():
                    return StoredMedia(self._media_item(knowledge), path,
                                       knowledge["mime_type"] or "application/octet-stream")
            row = db.execute("SELECT * FROM uploaded_media WHERE media_id=?", (media_id,)).fetchone()
        if not row:
            return None
        path = Path(row["stored_path"])
        if not path.is_file():
            return None
        return StoredMedia(MediaItem(media_id=row["media_id"], kind=row["kind"],
            filename=row["filename"], caption=row["caption"], source="customer",
            url=f"/v1/media/{row['media_id']}"), path, row["mime_type"])

    def get_for_review(self, media_id: str) -> StoredMedia | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM knowledge_media WHERE media_id=?", (media_id,)).fetchone()
        if not row:
            return None
        path = Path(row["stored_path"] or "")
        if not path.is_file():
            return None
        return StoredMedia(self._media_item(row), path,
                           row["mime_type"] or "application/octet-stream")

    def image_data_urls(self, media_ids: list[str]) -> list[str]:
        values: list[str] = []
        for media_id in media_ids:
            stored = self.get(media_id)
            if stored and stored.item.kind == "image" and stored.item.source == "customer":
                encoded = base64.b64encode(stored.path.read_bytes()).decode("ascii")
                values.append(f"data:{stored.mime_type};base64,{encoded}")
        return values

    def list_knowledge(self, query: str, limit: int = 50) -> list[MediaItem]:
        normalized = query.lower().strip()
        sql = "SELECT * FROM knowledge_media WHERE verified=1 AND customer_send_allowed=1"
        parameters: list[object] = []
        if normalized:
            sql += " AND search_text LIKE ? ESCAPE '\\'"
            parameters.append(f"%{self._escape_like(normalized)}%")
        sql += " ORDER BY purpose='product_showcase' DESC, media_id LIMIT ?"
        parameters.append(limit)
        with self._connect() as db:
            rows = db.execute(sql, parameters).fetchall()
        return [self._media_item(row) for row in rows]

    def catalog(self, query: str = "", verified: bool | None = None,
                limit: int = 100, offset: int = 0) -> tuple[list[CatalogMediaItem], int]:
        clauses: list[str] = []
        parameters: list[object] = []
        if query.strip():
            clauses.append("search_text LIKE ? ESCAPE '\\'")
            parameters.append(f"%{self._escape_like(query.lower().strip())}%")
        if verified is not None:
            clauses.append("verified=?")
            parameters.append(int(verified))
        where = " WHERE " + " AND ".join(clauses) if clauses else ""
        with self._connect() as db:
            total = db.execute(f"SELECT COUNT(*) FROM knowledge_media{where}", parameters).fetchone()[0]
            rows = db.execute(f"SELECT * FROM knowledge_media{where} ORDER BY verified,filename LIMIT ? OFFSET ?",
                              [*parameters, limit, offset]).fetchall()
        return [self._catalog_item(row) for row in rows], int(total)

    def approved_catalog(self, limit: int = 200) -> list[CatalogMediaItem]:
        with self._connect() as db:
            rows = db.execute("""SELECT * FROM knowledge_media
                WHERE verified=1 AND customer_send_allowed=1
                ORDER BY purpose='product_showcase' DESC,filename LIMIT ?""", (limit,)).fetchall()
        return [self._catalog_item(row) for row in rows]

    def update_catalog(self, media_id: str,
                       update: CatalogMediaUpdate) -> CatalogMediaItem | None:
        models = [model.strip() for model in update.models if model.strip()]
        with self._connect() as db:
            row = db.execute("SELECT filename FROM knowledge_media WHERE media_id=?", (media_id,)).fetchone()
            if not row:
                return None
            search_text = self._search_text(row["filename"], update.caption,
                                            update.product_line, models,
                                            update.view, update.purpose)
            db.execute("""UPDATE knowledge_media SET caption=?,product_line=?,models_text=?,
                search_text=?,view_type=?,purpose=?,verified=?,customer_send_allowed=?
                WHERE media_id=?""", (update.caption, update.product_line, " ".join(models),
                search_text, update.view, update.purpose, int(update.verified),
                int(update.customer_send_allowed), media_id))
            updated = db.execute("SELECT * FROM knowledge_media WHERE media_id=?", (media_id,)).fetchone()
        return self._catalog_item(updated)

    def search(self, plan: MediaSearchPlan, limit: int = 8) -> list[MediaItem]:
        if not plan.requested:
            return []
        if not plan.model.strip():
            return []
        clauses = ["verified=1", "customer_send_allowed=1"]
        parameters: list[object] = []
        if plan.kinds:
            clauses.append(f"kind IN ({','.join('?' for _ in plan.kinds)})")
            parameters.extend(plan.kinds)
        if plan.model.strip():
            clauses.append("(' ' || lower(models_text) || ' ') LIKE ? ESCAPE '\\'")
            parameters.append(f"% {self._escape_like(plan.model.lower().strip())} %")
        if plan.views and "other" not in plan.views:
            clauses.append(f"view_type IN ({','.join('?' for _ in plan.views)})")
            parameters.extend(plan.views)
        elif not plan.model.strip() and plan.query.strip():
            clauses.append("search_text LIKE ? ESCAPE '\\'")
            parameters.append(f"%{self._escape_like(plan.query.lower().strip())}%")
        sql = "SELECT * FROM knowledge_media WHERE " + " AND ".join(clauses)
        sql += " ORDER BY purpose='product_showcase' DESC,media_id LIMIT ?"
        parameters.append(limit)
        with self._connect() as db:
            rows = db.execute(sql, parameters).fetchall()
        return [self._media_item(row) for row in rows]

    @staticmethod
    def _media_item(row: sqlite3.Row) -> MediaItem:
        return MediaItem(media_id=row["media_id"], kind=row["kind"],
                         filename=row["filename"], caption=row["caption"],
                         source="knowledge", url=f"/v1/media/{row['media_id']}")

    @classmethod
    def _catalog_item(cls, row: sqlite3.Row) -> CatalogMediaItem:
        return CatalogMediaItem(**cls._media_item(row).model_dump(), record_id=row["record_id"],
            product_line=row["product_line"], models=row["models_text"].split(),
            view=row["view_type"], purpose=row["purpose"], verified=bool(row["verified"]),
            customer_send_allowed=bool(row["customer_send_allowed"]))

    @staticmethod
    def _escape_like(value: str) -> str:
        return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
