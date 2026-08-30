from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, File, Form, Header, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse, RedirectResponse

from .config import Settings
from .history import DraftHistoryStore
from .index import RagIndex
from .knowledge import load_corpus
from .media import MediaStore
from .openai_service import OpenAIService
from .schemas import (
    CatalogMediaItem,
    CatalogMediaList,
    CatalogMediaUpdate,
    ContactedRequest,
    ContactingRequest,
    DraftRequest,
    DraftResponse,
    HistoryResponse,
    MediaItem,
    RebuildResponse,
    RetrievalRequest,
    RetrievalResponse,
    TicketListResponse,
    TicketSummary,
)
from .service import RagService
from .tickets import ConversationPausedError, TicketStore


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = Settings.from_env()
    corpus = load_corpus(settings.knowledge_dir)
    index = RagIndex(settings.data_dir, corpus)
    openai = OpenAIService(settings.openai_api_key, settings.generation_model, settings.embedding_model) \
        if settings.openai_api_key else None
    app.state.settings = settings
    app.state.corpus = corpus
    app.state.index = index
    app.state.media = MediaStore(settings.data_dir, corpus)
    app.state.service = RagService(index, openai, settings.generation_model, app.state.media)
    app.state.history = DraftHistoryStore(settings.data_dir)
    app.state.tickets = TicketStore(settings.data_dir)
    yield


app = FastAPI(title="JD Seller Automation RAG backend", version="0.3.0", lifespan=lifespan)
STATIC_DIR = Path(__file__).with_name("static")


@app.get("/", include_in_schema=False)
def root() -> RedirectResponse:
    return RedirectResponse(url="/tester")


@app.get("/tester", include_in_schema=False)
def tester() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/media-review", include_in_schema=False)
def media_review() -> FileResponse:
    return FileResponse(STATIC_DIR / "media_review.html")


@app.get("/health")
def health(request: Request) -> dict:
    settings: Settings = request.app.state.settings
    corpus = request.app.state.corpus
    return {
        "status": "ok", "scope": "backend-only; no desktop automation or sending",
        "records": len(corpus.records), "index_ready": request.app.state.index.ready,
        "openai_configured": bool(settings.openai_api_key),
        "generation_model": settings.generation_model, "embedding_model": settings.embedding_model,
        "warnings": corpus.warnings,
    }


@app.get("/v1/capabilities")
def capabilities(request: Request) -> dict[str, bool]:
    return {"capture": False, "retrieval": True, "vector_retrieval": request.app.state.index.ready,
            "ai_reply_draft": bool(request.app.state.settings.openai_api_key),
            "image_input": True, "video_storage": True, "video_understanding": False,
            "outbound_media": False, "auto_send": True}


@app.post("/v1/media/upload", response_model=MediaItem)
async def upload_media(
    request: Request,
    file: UploadFile = File(...),
    conversation_id: str | None = Form(default=None),
    caption: str = Form(default="", max_length=500),
) -> MediaItem:
    try:
        return await request.app.state.media.save_upload(file, conversation_id, caption)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.get("/v1/media", response_model=list[MediaItem])
def list_media(
    request: Request,
    query: str = Query(default="", max_length=200),
    limit: int = Query(default=50, ge=1, le=100),
) -> list[MediaItem]:
    return request.app.state.media.list_knowledge(query, limit)


@app.get("/v1/media/{media_id}", include_in_schema=False)
def media_file(media_id: str, request: Request) -> FileResponse:
    stored = request.app.state.media.get(media_id)
    if not stored:
        raise HTTPException(status_code=404, detail="Media not found")
    return FileResponse(stored.path, media_type=stored.mime_type, filename=stored.item.filename)


@app.get("/v1/media-catalog", response_model=CatalogMediaList)
def media_catalog(
    request: Request,
    query: str = Query(default="", max_length=300),
    verified: bool | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    x_admin_token: str | None = Header(default=None),
) -> CatalogMediaList:
    _require_admin(request.app.state.settings, x_admin_token)
    items, total = request.app.state.media.catalog(query, verified, limit, offset)
    return CatalogMediaList(items=items, total=total)


@app.put("/v1/media-catalog/{media_id}", response_model=CatalogMediaItem)
def update_media_catalog(
    media_id: str, payload: CatalogMediaUpdate, request: Request,
    x_admin_token: str | None = Header(default=None),
) -> CatalogMediaItem:
    _require_admin(request.app.state.settings, x_admin_token)
    item = request.app.state.media.update_catalog(media_id, payload)
    if not item:
        raise HTTPException(status_code=404, detail="Media asset not found")
    return item


@app.get("/v1/media-catalog/{media_id}/preview", include_in_schema=False)
def preview_media_catalog(
    media_id: str, request: Request,
    x_admin_token: str | None = Header(default=None),
) -> FileResponse:
    _require_admin(request.app.state.settings, x_admin_token)
    stored = request.app.state.media.get_for_review(media_id)
    if not stored:
        raise HTTPException(status_code=404, detail="Media asset not found")
    return FileResponse(stored.path, media_type=stored.mime_type)


@app.post("/v1/retrieve", response_model=RetrievalResponse)
def retrieve(payload: RetrievalRequest, request: Request) -> RetrievalResponse:
    return request.app.state.service.retrieve(payload)


@app.post("/v1/replies/draft", response_model=DraftResponse)
def draft(payload: DraftRequest, request: Request) -> DraftResponse:
    try:
        request.app.state.tickets.ensure_ai_may_reply(
            payload.conversation_id, payload.customer_message_id)
        response = request.app.state.service.draft(payload, request.app.state.settings.retrieval_limit)
        if response.decision == "human_review_required" and payload.conversation_id:
            reason = next(
                (action.description for action in response.actions if action.type == "human_handoff"),
                "Human review is required for this customer request.",
            )
            response.ticket = request.app.state.tickets.create_or_get(
                payload.conversation_id, payload.customer_message, reason)
            if any("\u4e00" <= character <= "\u9fff" for character in payload.customer_message):
                response.reply = (
                    "您的需求已提交给相关人员跟进，他们会就此问题与您联系。"
                    "请问还有其他问题需要我帮您处理吗？"
                )
            else:
                response.reply = (
                    "Your request has been sent to the relevant team for follow-up. "
                    "They will contact you about it. Is there anything else I can help you with?"
                )
        request.app.state.history.save(payload, response)
        return response
    except ConversationPausedError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except RuntimeError as exc:
        request.app.state.history.save(payload, None, str(exc))
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        request.app.state.history.save(payload, None, f"{type(exc).__name__}: {exc}")
        raise HTTPException(status_code=502, detail="Draft generation failed") from exc


@app.get("/v1/tickets", response_model=TicketListResponse)
def tickets(
    request: Request,
    conversation_id: str | None = Query(default=None),
    status: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
) -> TicketListResponse:
    return TicketListResponse(
        items=request.app.state.tickets.list(conversation_id, status, limit)
    )


@app.post("/v1/tickets/{ticket_id}/contacting", response_model=TicketSummary)
def ticket_contacting(ticket_id: int, payload: ContactingRequest,
                      request: Request) -> TicketSummary:
    ticket = request.app.state.tickets.mark_contacting(ticket_id, payload.assigned_to)
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket not found")
    return ticket


@app.post("/v1/tickets/{ticket_id}/contacted", response_model=TicketSummary)
def ticket_contacted(ticket_id: int, payload: ContactedRequest,
                     request: Request) -> TicketSummary:
    ticket = request.app.state.tickets.mark_contacted(
        ticket_id, payload.resume_after_message_id, payload.resolution_note)
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket not found")
    return ticket


def _require_admin(settings: Settings, supplied_token: str | None) -> None:
    if not settings.admin_token or supplied_token != settings.admin_token:
        raise HTTPException(status_code=403, detail="Valid X-Admin-Token required")


@app.get("/v1/history", response_model=HistoryResponse)
def history(
    request: Request,
    limit: int = Query(default=20, ge=1, le=100),
    conversation_id: str | None = Query(default=None),
    x_admin_token: str | None = Header(default=None),
) -> HistoryResponse:
    _require_admin(request.app.state.settings, x_admin_token)
    return HistoryResponse(items=request.app.state.history.list(limit, conversation_id))


@app.post("/v1/index/rebuild", response_model=RebuildResponse)
def rebuild(request: Request, x_admin_token: str | None = Header(default=None)) -> RebuildResponse:
    settings: Settings = request.app.state.settings
    _require_admin(settings, x_admin_token)
    service: RagService = request.app.state.service
    if not service.openai:
        raise HTTPException(status_code=503, detail="OPENAI_API_KEY is not configured")
    records, dimensions = request.app.state.index.rebuild(service.openai)
    return RebuildResponse(status="rebuilt", records=records, dimensions=dimensions,
                           warnings=request.app.state.corpus.warnings,
                           knowledge_hash=request.app.state.corpus.content_hash)
