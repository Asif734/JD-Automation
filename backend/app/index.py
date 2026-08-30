from __future__ import annotations

import json
import math
import re
import sqlite3
from dataclasses import asdict
from pathlib import Path
from threading import RLock
from typing import Protocol, Sequence

import faiss
import numpy as np

from .knowledge import KnowledgeCorpus, KnowledgeRecord


class Embedder(Protocol):
    model: str

    def embed(self, texts: Sequence[str]) -> list[list[float]]: ...


def _normalize(text: str) -> str:
    return re.sub(r"\s+", "", text.lower())


def _char_ngrams(text: str, size: int = 2) -> set[str]:
    value = _normalize(text)
    return {value[index:index + size] for index in range(max(0, len(value) - size + 1))}


def _lexical_score(query: str, record: KnowledgeRecord, product_line: str | None, model: str | None) -> float:
    compact = _normalize(query)
    score = 0.0
    for keyword in [*record.keywords, *record.synonyms]:
        token = _normalize(keyword)
        if token and token in compact:
            score += 10.0 + min(10.0, len(token))
    title = _normalize(record.title)
    if title and (title in compact or compact in title):
        score += 18.0
    query_grams = _char_ngrams(query)
    record_grams = _char_ngrams(record.search_text)
    if query_grams and record_grams:
        score += 8.0 * len(query_grams & record_grams) / math.sqrt(len(query_grams) * len(record_grams))
    if product_line:
        score += 12.0 if record.product_line in {product_line, "all"} else -12.0
    if model:
        normalized_model = _normalize(model)
        if record.models and any(normalized_model == _normalize(value) for value in record.models):
            # Prefer a model-specific card over a broad family card when both match.
            score += 10.0 + (25.0 / math.sqrt(len(record.models)))
        elif record.models:
            score -= 20.0
    if record.record_type == "card":
        score += 4.0
    return score


class RagIndex:
    def __init__(self, data_dir: Path, corpus: KnowledgeCorpus):
        self.data_dir = data_dir
        self.corpus = corpus
        self._records = {record.id: record for record in corpus.records}
        self._ordered_ids: list[str] = []
        self._faiss: faiss.Index | None = None
        self._lock = RLock()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self._load()

    @property
    def ready(self) -> bool:
        return self._faiss is not None and bool(self._ordered_ids)

    def _load(self) -> None:
        meta_path = self.data_dir / "index_meta.json"
        index_path = self.data_dir / "knowledge.faiss"
        if not meta_path.is_file() or not index_path.is_file():
            return
        metadata = json.loads(meta_path.read_text(encoding="utf-8"))
        if metadata.get("knowledge_hash") != self.corpus.content_hash:
            return
        ids = [str(value) for value in metadata.get("ids") or []]
        if not ids or any(value not in self._records for value in ids):
            return
        self._ordered_ids = ids
        self._faiss = faiss.read_index(str(index_path))

    def rebuild(self, embedder: Embedder, batch_size: int = 64) -> tuple[int, int]:
        vectors: list[list[float]] = []
        records = self.corpus.records
        for start in range(0, len(records), batch_size):
            vectors.extend(embedder.embed([record.search_text for record in records[start:start + batch_size]]))
        matrix = np.asarray(vectors, dtype="float32")
        if matrix.ndim != 2 or matrix.shape[0] != len(records) or matrix.shape[1] == 0:
            raise ValueError("Embedding service returned an invalid matrix")
        faiss.normalize_L2(matrix)
        index = faiss.IndexFlatIP(matrix.shape[1])
        index.add(matrix)
        ids = [record.id for record in records]
        metadata = {
            "knowledge_hash": self.corpus.content_hash,
            "embedding_model": embedder.model,
            "dimensions": int(matrix.shape[1]),
            "ids": ids,
        }
        with self._lock:
            faiss.write_index(index, str(self.data_dir / "knowledge.faiss"))
            (self.data_dir / "index_meta.json").write_text(
                json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
            self._write_sqlite(records)
            self._ordered_ids = ids
            self._faiss = index
        return len(records), int(matrix.shape[1])

    def _write_sqlite(self, records: list[KnowledgeRecord]) -> None:
        path = self.data_dir / "metadata.sqlite3"
        with sqlite3.connect(path) as db:
            db.executescript("""
                DROP TABLE IF EXISTS knowledge_records;
                CREATE TABLE knowledge_records(
                  vector_id INTEGER PRIMARY KEY,
                  record_id TEXT NOT NULL UNIQUE,
                  record_type TEXT NOT NULL,
                  product_line TEXT NOT NULL,
                  risk_level TEXT NOT NULL,
                  payload_json TEXT NOT NULL
                );
                CREATE INDEX knowledge_product ON knowledge_records(product_line, record_type);
            """)
            db.executemany(
                "INSERT INTO knowledge_records VALUES(?,?,?,?,?,?)",
                [(index, record.id, record.record_type, record.product_line, record.risk_level,
                  json.dumps(asdict(record), ensure_ascii=False, default=str))
                 for index, record in enumerate(records)],
            )

    def search(self, query: str, query_vector: list[float] | None, *, limit: int,
               product_line: str | None = None, model: str | None = None) -> list[dict]:
        lexical = {
            record.id: _lexical_score(query, record, product_line, model)
            for record in self.corpus.records
        }
        vector_scores: dict[str, float] = {}
        if query_vector is not None and self.ready:
            vector = np.asarray([query_vector], dtype="float32")
            if vector.shape[1] != self._faiss.d:
                raise ValueError(f"Query embedding has {vector.shape[1]} dimensions; index expects {self._faiss.d}")
            faiss.normalize_L2(vector)
            count = min(max(limit * 8, 30), len(self._ordered_ids))
            scores, positions = self._faiss.search(vector, count)
            for score, position in zip(scores[0], positions[0]):
                if position >= 0:
                    vector_scores[self._ordered_ids[int(position)]] = float(score)

        candidates = set(sorted(lexical, key=lexical.get, reverse=True)[:max(30, limit * 8)]) | set(vector_scores)
        ranked: list[dict] = []
        for record_id in candidates:
            record = self._records[record_id]
            lexical_value = lexical[record_id]
            vector_value = vector_scores.get(record_id)
            combined = lexical_value + (max(0.0, vector_value) * 20.0 if vector_value is not None else 0.0)
            if record.record_type == "source_chunk":
                combined -= 2.0
            ranked.append({"record": record, "score": combined, "lexical_score": lexical_value,
                           "vector_score": vector_value})
        ranked.sort(key=lambda item: item["score"], reverse=True)
        return ranked[:limit]
