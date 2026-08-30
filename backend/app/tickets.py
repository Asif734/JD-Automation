from __future__ import annotations

import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from .schemas import TicketSummary


class ConversationPausedError(RuntimeError):
    pass


class TicketStore:
    def __init__(self, data_dir: Path):
        self.path = data_dir / "tickets.sqlite3"
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
                CREATE TABLE IF NOT EXISTS tickets(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  conversation_id TEXT NOT NULL,
                  customer_request TEXT NOT NULL,
                  reason TEXT NOT NULL,
                  status TEXT NOT NULL CHECK(status IN ('open','contacting','contacted','resolved','cancelled')),
                  assigned_to TEXT,
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL,
                  contacted_at TEXT,
                  resolution_note TEXT
                );
                CREATE INDEX IF NOT EXISTS tickets_queue
                  ON tickets(status, updated_at DESC, id DESC);
                CREATE INDEX IF NOT EXISTS tickets_conversation
                  ON tickets(conversation_id, updated_at DESC, id DESC);
                CREATE TABLE IF NOT EXISTS conversation_control(
                  conversation_id TEXT PRIMARY KEY,
                  state TEXT NOT NULL CHECK(state IN ('ai_active','human_contacting','waiting_for_customer')),
                  state_version INTEGER NOT NULL DEFAULT 1,
                  resume_after_message_id TEXT,
                  updated_at TEXT NOT NULL
                );
            """)

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def _ticket(row: sqlite3.Row) -> TicketSummary:
        return TicketSummary(
            id=row["id"], conversation_id=row["conversation_id"],
            customer_request=row["customer_request"], reason=row["reason"],
            status=row["status"], assigned_to=row["assigned_to"],
            created_at=row["created_at"], updated_at=row["updated_at"],
            contacted_at=row["contacted_at"], resolution_note=row["resolution_note"],
        )

    def create_or_get(self, conversation_id: str, customer_request: str,
                      reason: str) -> TicketSummary:
        now = self._now()
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute(
                """SELECT * FROM tickets WHERE conversation_id=?
                   AND status IN ('open','contacting') ORDER BY id DESC LIMIT 1""",
                (conversation_id,),
            ).fetchone()
            if existing:
                return self._ticket(existing)
            cursor = db.execute(
                """INSERT INTO tickets(conversation_id, customer_request, reason,
                   status, created_at, updated_at) VALUES(?,?,?,'open',?,?)""",
                (conversation_id, customer_request, reason, now, now),
            )
            row = db.execute("SELECT * FROM tickets WHERE id=?", (cursor.lastrowid,)).fetchone()
            return self._ticket(row)

    def list(self, conversation_id: str | None = None,
             status: str | None = None, limit: int = 100) -> list[TicketSummary]:
        clauses: list[str] = []
        parameters: list[object] = []
        if conversation_id:
            clauses.append("conversation_id=?")
            parameters.append(conversation_id)
        if status:
            clauses.append("status=?")
            parameters.append(status)
        query = "SELECT * FROM tickets"
        if clauses:
            query += " WHERE " + " AND ".join(clauses)
        query += " ORDER BY updated_at DESC, id DESC LIMIT ?"
        parameters.append(limit)
        with self._connect() as db:
            rows = db.execute(query, parameters).fetchall()
        return [self._ticket(row) for row in rows]

    def mark_contacting(self, ticket_id: int, assigned_to: str | None) -> TicketSummary | None:
        now = self._now()
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM tickets WHERE id=?", (ticket_id,)).fetchone()
            if not row:
                return None
            db.execute(
                "UPDATE tickets SET status='contacting', assigned_to=?, updated_at=? WHERE id=?",
                (assigned_to, now, ticket_id),
            )
            db.execute(
                """INSERT INTO conversation_control(conversation_id,state,state_version,updated_at)
                   VALUES(?,'human_contacting',1,?) ON CONFLICT(conversation_id) DO UPDATE SET
                   state='human_contacting', state_version=state_version+1,
                   resume_after_message_id=NULL, updated_at=excluded.updated_at""",
                (row["conversation_id"], now),
            )
            updated = db.execute("SELECT * FROM tickets WHERE id=?", (ticket_id,)).fetchone()
            return self._ticket(updated)

    def mark_contacted(self, ticket_id: int, resume_after_message_id: str,
                       resolution_note: str | None) -> TicketSummary | None:
        now = self._now()
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM tickets WHERE id=?", (ticket_id,)).fetchone()
            if not row:
                return None
            db.execute(
                """UPDATE tickets SET status='contacted', contacted_at=?, updated_at=?,
                   resolution_note=? WHERE id=?""",
                (now, now, resolution_note, ticket_id),
            )
            db.execute(
                """INSERT INTO conversation_control(
                   conversation_id,state,state_version,resume_after_message_id,updated_at)
                   VALUES(?,'waiting_for_customer',1,?,?) ON CONFLICT(conversation_id) DO UPDATE SET
                   state='waiting_for_customer', state_version=state_version+1,
                   resume_after_message_id=excluded.resume_after_message_id,
                   updated_at=excluded.updated_at""",
                (row["conversation_id"], resume_after_message_id, now),
            )
            updated = db.execute("SELECT * FROM tickets WHERE id=?", (ticket_id,)).fetchone()
            return self._ticket(updated)

    def ensure_ai_may_reply(self, conversation_id: str | None,
                            customer_message_id: str | None) -> None:
        if not conversation_id:
            return
        now = self._now()
        with self._connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute(
                "SELECT * FROM conversation_control WHERE conversation_id=?",
                (conversation_id,),
            ).fetchone()
            if not row or row["state"] == "ai_active":
                return
            if row["state"] == "human_contacting":
                raise ConversationPausedError("A human agent is contacting this customer; AI is paused.")
            boundary = row["resume_after_message_id"]
            if customer_message_id and customer_message_id != boundary:
                db.execute(
                    """UPDATE conversation_control SET state='ai_active', state_version=state_version+1,
                       resume_after_message_id=NULL, updated_at=? WHERE conversation_id=?""",
                    (now, conversation_id),
                )
                return
            raise ConversationPausedError(
                "Human contact is complete; AI is waiting for a new incoming customer message."
            )
