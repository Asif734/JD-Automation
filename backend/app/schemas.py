from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ConversationMessage(BaseModel):
    direction: Literal["incoming", "outgoing", "unknown"]
    body: str = Field(min_length=1, max_length=20_000)


class ProductContext(BaseModel):
    line: str | None = None
    model: str | None = None


class RetrievalRequest(BaseModel):
    query: str = Field(min_length=1, max_length=4_000)
    platform: Literal["tmall", "jd", "pinduoduo", "unknown"] = "unknown"
    product: ProductContext | None = None
    limit: int = Field(default=5, ge=1, le=10)


class RetrievalHit(BaseModel):
    id: str
    record_type: Literal["card", "source_chunk"]
    title: str
    content: str
    product_line: str
    risk_level: str
    auto_reply_allowed: bool
    score: float
    lexical_score: float
    vector_score: float | None = None
    source_files: list[str] = Field(default_factory=list)
    actions: list[dict[str, Any]] = Field(default_factory=list)
    media: list["MediaItem"] = Field(default_factory=list)


class RetrievalResponse(BaseModel):
    query: str
    risk_level: str
    risk_triggers: list[str]
    index_ready: bool
    hits: list[RetrievalHit]


class DraftRequest(BaseModel):
    conversation_id: str | None = None
    customer_message_id: str | None = Field(default=None, max_length=500)
    customer_message: str = Field(min_length=1, max_length=4_000)
    platform: Literal["tmall", "jd", "pinduoduo", "unknown"] = "unknown"
    product: ProductContext | None = None
    messages: list[ConversationMessage] = Field(default_factory=list, max_length=20)
    attachments: list["IncomingMedia"] = Field(default_factory=list, max_length=10)


class IncomingMedia(BaseModel):
    media_id: str
    caption: str = Field(default="", max_length=500)


class MediaItem(BaseModel):
    media_id: str
    kind: Literal["image", "video"]
    filename: str
    caption: str
    source: Literal["knowledge", "customer"]
    url: str


class CatalogMediaItem(MediaItem):
    record_id: str | None = None
    product_line: str
    models: list[str] = Field(default_factory=list)
    view: Literal["exterior", "screen", "internal", "label", "setup", "other"]
    purpose: Literal["product_showcase", "instruction", "troubleshooting", "other"]
    verified: bool
    customer_send_allowed: bool


class CatalogMediaList(BaseModel):
    items: list[CatalogMediaItem]
    total: int


class CatalogMediaUpdate(BaseModel):
    product_line: str = Field(min_length=1, max_length=200)
    models: list[str] = Field(default_factory=list, max_length=30)
    view: Literal["exterior", "screen", "internal", "label", "setup", "other"]
    purpose: Literal["product_showcase", "instruction", "troubleshooting", "other"]
    caption: str = Field(min_length=1, max_length=1_000)
    verified: bool
    customer_send_allowed: bool


class MediaSearchPlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    requested: bool
    query: str
    model: str
    kinds: list[Literal["image", "video"]]
    views: list[Literal["exterior", "screen", "internal", "label", "setup", "other"]]


class RequestPlan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    rewritten_query: str
    product_line: str
    model: str
    media_requested: bool
    kinds: list[Literal["image", "video"]]
    views: list[Literal["exterior", "screen", "internal", "label", "setup", "other"]]


class MediaSelection(BaseModel):
    model_config = ConfigDict(extra="forbid")

    selected_media_ids: list[str] = Field(default_factory=list, max_length=3)
    reason: str


class KnowledgeSelection(BaseModel):
    model_config = ConfigDict(extra="forbid")

    selected_record_ids: list[str] = Field(default_factory=list, max_length=10)
    reason: str


class DraftMedia(BaseModel):
    model_config = ConfigDict(extra="forbid")

    media_id: str
    kind: Literal["image", "video"]
    caption: str


class DraftAction(BaseModel):
    model_config = ConfigDict(extra="forbid")

    type: Literal["collect_information", "send_guide", "human_handoff"]
    description: str


class GeneratedDraft(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reply: str
    decision: Literal["draft", "ask_clarification", "human_review_required"]
    confidence: float = Field(ge=0, le=1)
    used_record_ids: list[str] = Field(default_factory=list)
    required_slots: list[str] = Field(default_factory=list)
    actions: list[DraftAction] = Field(default_factory=list)
    attachments: list[DraftMedia] = Field(default_factory=list)


class TicketSummary(BaseModel):
    id: int
    conversation_id: str
    customer_request: str
    reason: str
    status: Literal["open", "contacting", "contacted", "resolved", "cancelled"]
    assigned_to: str | None = None
    created_at: str
    updated_at: str
    contacted_at: str | None = None
    resolution_note: str | None = None


class TicketListResponse(BaseModel):
    items: list[TicketSummary]


class ContactingRequest(BaseModel):
    assigned_to: str | None = Field(default=None, max_length=200)


class ContactedRequest(BaseModel):
    resume_after_message_id: str = Field(min_length=1, max_length=500)
    resolution_note: str | None = Field(default=None, max_length=2_000)


class DraftResponse(GeneratedDraft):
    risk_level: str
    risk_triggers: list[str]
    auto_send_allowed: Literal[False] = False
    model: str
    ticket: TicketSummary | None = None


class RebuildResponse(BaseModel):
    status: str
    records: int
    dimensions: int
    warnings: list[str]
    knowledge_hash: str


class HistoryEntry(BaseModel):
    id: int
    created_at: str
    conversation_id: str | None
    customer_message: str
    request: dict[str, Any]
    response: dict[str, Any] | None
    status: Literal["success", "error"]
    error: str | None


class HistoryResponse(BaseModel):
    items: list[HistoryEntry]
