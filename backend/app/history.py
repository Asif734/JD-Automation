from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .schemas import DraftRequest, DraftResponse, HistoryEntry


class DraftHistoryStore:
    def __init__(self, data_dir: Path):
        self.path = data_dir / "draft_history.sqlite3"
        data_dir.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        return connection

    def _initialize(self) -> None:
        with self._connect() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript("""
                CREATE TABLE IF NOT EXISTS draft_history(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  created_at TEXT NOT NULL,
                  conversation_id TEXT,
                  customer_message TEXT NOT NULL,
                  request_json TEXT NOT NULL,
                  response_json TEXT,
                  status TEXT NOT NULL,
                  error TEXT
                );
                CREATE INDEX IF NOT EXISTS draft_history_recent
                  ON draft_history(created_at DESC, id DESC);
                CREATE INDEX IF NOT EXISTS draft_history_conversation
                  ON draft_history(conversation_id, created_at DESC, id DESC);
            """)

    def save(self, request: DraftRequest, response: DraftResponse | None, error: str | None = None) -> int:
        created_at = datetime.now(timezone.utc).isoformat()
        with self._connect() as db:
            cursor = db.execute(
                """INSERT INTO draft_history(
                     created_at, conversation_id, customer_message, request_json,
                     response_json, status, error
                   ) VALUES(?,?,?,?,?,?,?)""",
                (
                    created_at,
                    request.conversation_id,
                    request.customer_message,
                    json.dumps(request.model_dump(mode="json"), ensure_ascii=False),
                    json.dumps(response.model_dump(mode="json"), ensure_ascii=False) if response else None,
                    "success" if response else "error",
                    error,
                ),
            )
            return int(cursor.lastrowid)

    def list(self, limit: int, conversation_id: str | None = None) -> list[HistoryEntry]:
        query = "SELECT * FROM draft_history"
        parameters: list[Any] = []
        if conversation_id is not None:
            query += " WHERE conversation_id = ?"
            parameters.append(conversation_id)
        query += " ORDER BY created_at DESC, id DESC LIMIT ?"
        parameters.append(limit)
        with self._connect() as db:
            rows = db.execute(query, parameters).fetchall()
        return [HistoryEntry(
            id=row["id"], created_at=row["created_at"],
            conversation_id=row["conversation_id"], customer_message=row["customer_message"],
            request=json.loads(row["request_json"]),
            response=json.loads(row["response_json"]) if row["response_json"] else None,
            status=row["status"], error=row["error"],
        ) for row in rows]
