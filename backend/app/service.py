from __future__ import annotations

from .index import RagIndex
from .media import MediaStore
from .openai_service import OpenAIService
from .risk import assess_risk
from .schemas import (DraftMedia, DraftRequest, DraftResponse, MediaItem,
                      ProductContext, RetrievalHit, RetrievalRequest, RetrievalResponse)


class RagService:
    def __init__(self, index: RagIndex, openai: OpenAIService | None,
                 generation_model: str, media: MediaStore):
        self.index = index
        self.openai = openai
        self.generation_model = generation_model
        self.media = media

    def retrieve(self, request: RetrievalRequest) -> RetrievalResponse:
        query = request.query
        product_line = request.product.line if request.product else None
        model = request.product.model if request.product else None
        if self.openai:
            plan = self.openai.plan_request(request.query)
            query = plan.rewritten_query
            product_line = product_line or plan.product_line or None
            model = model or plan.model or None
        return self._retrieve(request.query, query, request.platform, product_line,
                              model, request.limit)

    def _retrieve(self, original_query: str, retrieval_query: str, platform: str,
                  product_line: str | None, model: str | None,
                  limit: int) -> RetrievalResponse:
        risk = assess_risk(original_query)
        query_vector = self.openai.embed([retrieval_query])[0] \
            if self.openai and self.index.ready else None
        candidate_limit = min(max(limit * 6, 30), len(self.index.corpus.records))
        rows = self.index.search(retrieval_query, query_vector, limit=candidate_limit,
                                 product_line=product_line, model=model)
        if self.openai and rows:
            candidates = [{
                "record_id": row["record"].id,
                "record_type": row["record"].record_type,
                "title": row["record"].title,
                "content": row["record"].content,
                "product_line": row["record"].product_line,
                "models": row["record"].models,
            } for row in rows]
            selection = self.openai.select_knowledge(original_query, candidates)
            by_id = {row["record"].id: row for row in rows}
            selected = [by_id[record_id] for record_id in selection.selected_record_ids
                        if record_id in by_id]
            selected_ids = {row["record"].id for row in selected}
            rows = [*selected, *(row for row in rows if row["record"].id not in selected_ids)]
        rows = rows[:limit]
        return RetrievalResponse(
            query=original_query, risk_level=risk.level, risk_triggers=risk.triggers,
            index_ready=self.index.ready, hits=[self._hit(row) for row in rows],
        )

    def draft(self, request: DraftRequest, limit: int) -> DraftResponse:
        if not self.openai:
            raise RuntimeError("OPENAI_API_KEY is not configured")
        transcript = self._transcript(request)
        plan = self.openai.plan_request(transcript)
        product_line = request.product.line if request.product else None
        model = request.product.model if request.product else None
        retrieval = self._retrieve(
            request.customer_message, plan.rewritten_query, request.platform,
            product_line or plan.product_line or None, model or plan.model or None, limit)
        current_risk = assess_risk(request.customer_message)
        retrieval.risk_level = current_risk.level
        retrieval.risk_triggers = current_risk.triggers

        # JD customer replies are deliberately text-only. The media catalogue
        # remains available for internal review, but generation cannot select
        # outbound photos, videos, or files.
        media_candidates: list[MediaItem] = []

        payload = {
            "platform": request.platform,
            "product": ProductContext(
                line=product_line or plan.product_line or None,
                model=model or plan.model or None,
            ).model_dump(),
            "customer_message": request.customer_message,
            "recent_messages": [message.model_dump() for message in request.messages[-20:]],
            "customer_attachments": [
                stored.item.model_dump()
                for attachment in request.attachments
                if (stored := self.media.get(attachment.media_id))
            ],
            "deterministic_risk": {
                "level": retrieval.risk_level, "triggers": retrieval.risk_triggers},
            "knowledge": [hit.model_dump() for hit in retrieval.hits],
            "approved_media_candidates": [item.model_dump() for item in media_candidates],
            "rules": {
                "human_review_required": True, "text_only": True,
                "high_or_critical_must_handoff": retrieval.risk_level in {"high", "critical"},
                "continue_unresolved_goal_from_recent_messages": True,
            },
        }
        generated = self.openai.draft(
            payload, self.media.image_data_urls(
                [item.media_id for item in request.attachments]))
        allowed_record_ids = {hit.id for hit in retrieval.hits}
        generated.used_record_ids = [value for value in generated.used_record_ids
                                     if value in allowed_record_ids]
        if not generated.used_record_ids and retrieval.hits:
            generated.used_record_ids = [retrieval.hits[0].id]
        generated.attachments = [
            DraftMedia(media_id=item.media_id, kind=item.kind, caption=item.caption)
            for item in media_candidates
        ]
        decision = "human_review_required" \
            if retrieval.risk_level in {"high", "critical"} else generated.decision
        return DraftResponse(
            **generated.model_dump(exclude={"decision"}), decision=decision,
            risk_level=retrieval.risk_level, risk_triggers=retrieval.risk_triggers,
            auto_send_allowed=False, model=self.generation_model,
        )

    @staticmethod
    def _transcript(request: DraftRequest) -> str:
        return "\n".join(
            [f"{message.direction}: {message.body}" for message in request.messages[-12:]]
            + [f"incoming: {request.customer_message}"])

    @staticmethod
    def _contextual_query(request: DraftRequest) -> str:
        previous_customer_messages = [
            message.body for message in request.messages if message.direction == "incoming"
        ][-5:]
        return "\n".join([*previous_customer_messages, request.customer_message])

    @staticmethod
    def _hit(row: dict) -> RetrievalHit:
        record = row["record"]
        return RetrievalHit(
            id=record.id, record_type=record.record_type, title=record.title,
            content=record.content, product_line=record.product_line,
            risk_level=record.risk_level, auto_reply_allowed=record.auto_reply_allowed,
            score=round(row["score"], 6), lexical_score=round(row["lexical_score"], 6),
            vector_score=round(row["vector_score"], 6)
            if row["vector_score"] is not None else None,
            source_files=record.source_files, actions=record.actions,
            media=[MediaItem(
                media_id=item.media_id, kind=item.kind, filename=item.filename,
                caption=item.caption, source="knowledge", url=f"/v1/media/{item.media_id}",
            ) for item in record.media],
        )
