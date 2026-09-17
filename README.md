# Qianniu message-capture MVP

Flutter desktop UI plus a native Swift/macOS Accessibility adapter for **capture only**. It detects `com.taobao.Aliworkbench`, requests Accessibility access, dumps its AX tree, polls the selected conversation, fingerprints visible messages, queues captures, and stores them in SQLite. There is deliberately no native method for inserting or sending a reply.

## Run

Prerequisites: Flutter stable with macOS desktop enabled and the full Xcode app selected (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`).

```sh
flutter pub get
flutter run -d macos
```

## RAG backend

The backend loads 91 curated customer-service cards and 535 supporting source chunks. It provides lexical retrieval immediately, optional FAISS vector retrieval using OpenAI embeddings, and structured Simplified-Chinese reply drafts using `gpt-5.4-mini`. Every reply is returned as a reviewable draft with `auto_send_allowed: false`; the API has no Qianniu send capability.

Create the local configuration and start it:

```sh
cp .env.example .env
# Edit .env and add OPENAI_API_KEY plus a private RAG_ADMIN_TOKEN.
docker compose up --build api
curl http://127.0.0.1:8080/health
```

Open `http://127.0.0.1:8080/tester` for the lightweight browser test interface. It keeps the last 20 test messages in browser storage and supplies them to each draft request automatically.

The Flutter conversation dialog now uses the same API. It selects the latest captured incoming/unknown message as `customer_message`, sends up to 20 earlier real messages as context, saves the returned draft in the local capture SQLite database, and displays it in a review-only panel. Configure a non-default backend at build time with `--dart-define=RAG_BACKEND_URL=http://127.0.0.1:PORT`. The Flutter app contains no insert/send reply action.

The tester also accepts customer screenshots, photos, and videos. Images are supplied to the model as visual evidence; videos uploaded through the backend tester are stored but deliberately not treated as analyzed. Uploaded images are limited to 15 MB and videos to 50 MB. Retrieved knowledge records expose only allow-listed local media, and draft attachments are filtered against those retrieved IDs before being returned.

The macOS JD capture path separately recognizes the centered play overlay on an incoming video bubble. JD 10.4 already stores received videos in its per-chat media cache, so the app copies the newest fresh cached video into the private customer media directory without clicking, typing, opening a menu, or changing the selected conversation. It then runs local FFmpeg at one frame per second with a hard limit of 20 frames. Those chronological JPEG frames are passed to Codex through the same guarded image-input path and their factual descriptions are saved back to the conversation JSON. FFmpeg also detects and extracts a mono 16 kHz audio track; meaningful audio is transcribed in Chinese and English through macOS Speech, while silent and no-audio videos are explicitly recorded as such.

Local Codex drafts use low reasoning effort and low verbosity, ignore unrelated user-level Codex plugin configuration, run at most 20 customer workers concurrently, and have a 90-second generation deadline. New evidence is collected for 2.5 seconds before a batch starts. Ready replies can be sent while other customers are still generating. On a Codex timeout, the app sends one randomly selected short holding message in the customer's language, keeps that batch pending, and retries Codex after 10 seconds. The two-minute SLA acknowledgement uses the same one-per-batch record, so it cannot send a second holding message for that batch. A successful Codex reply is then sent as the final answer. Invalid output and process errors still use the human-review fallback.

Local Codex replies use the extracted `格志中国市场客服完整知识库-2026-09-15-r21-consolidated` directory by default, including its app-specific `product_model_feature_catalog_kb.md`. Set `QIANNIU_KNOWLEDGE_DIR` to a different directory to override it. Retrieval reads active RAG cards, source chunks, and root-level customer knowledge Markdown; the package's plans and READMEs are excluded. The app checks these files for changes before each retrieval and reloads them when needed. On macOS it reranks up to 35 lexical candidates with sentence embeddings made from the loaded text; if embedding is unavailable or exceeds 1.5 seconds, lexical results are used. Requests for a product model list load the catalog and ask Codex to list the full Current category before asking about preferences. Questions about a named model's features also load the catalog and pass matching model rows as primary evidence, including grouped paper-width rows. Keep the curated RAG cards, source chunks, and catalog consistent when editing the raw Markdown knowledge; file reload does not regenerate those authored records.

The macOS `.app` does not embed the extracted r21 directory. When installing it outside this project, deploy that directory alongside it and set `QIANNIU_KNOWLEDGE_DIR` to its absolute path. The catalog file must be present in that directory.

Media API:

```text
POST /v1/media/upload       multipart customer image/video upload
GET  /v1/media?query=M880   search approved knowledge media
GET  /v1/media/{media_id}   display a known media object
```

The backend inventories every image/video below the knowledge directory into a governed media
catalogue. Existing card-linked assets start verified and customer-sendable; newly discovered
files remain quarantined until a supervisor supplies the correct product model, view, purpose,
and caption. Open `http://127.0.0.1:8080/media-review`, enter `RAG_ADMIN_TOKEN`, review the
thumbnail and metadata, then enable both **Verified** and **Send allowed**. The review API is:

```text
GET /v1/media-catalog                 list/search assets (admin token required)
GET /v1/media-catalog/{id}/preview    preview quarantined assets (admin token required)
PUT /v1/media-catalog/{id}            update and approve metadata (admin token required)
```

Outbound search requires an exact model and returns only verified, customer-sendable assets.
If no approved asset matches the requested model and view, the draft creates a human-review
ticket instead of substituting another product. When a verified match exists, the backend adds
up to three deterministic attachments even if the language model omits attachment IDs.

For media requests, the LLM produces a typed search plan (model, media kind, and requested view). The backend translates that plan into a read-only parameterized SQLite query. Raw model-generated SQL is never executed. Recent customer turns are included when resolving short follow-ups such as `both`, `M880`, or `M880UT`.

An outbound draft can contain attachment suggestions:

```json
{
  "reply": "我把对应图片发您参考。",
  "attachments": [
    {"media_id": "kb_...", "kind": "image", "caption": "图片说明"}
  ],
  "auto_send_allowed": false
}
```

The knowledge directory is mounted read-only and the generated FAISS/SQLite metadata is kept in the `rag-data` Docker volume. Build the vector index once (and again whenever the knowledge files change):

```sh
docker compose exec api python -m app.build_index
```

Lexical retrieval works even before that command. Try it with:

```sh
curl -s http://127.0.0.1:8080/v1/retrieve \
  -H 'Content-Type: application/json' \
  -d '{"query":"TD630G 在 Mac 上怎么无线打印？","product":{"model":"TD630G"}}'
```

Generate a human-reviewed draft:

```sh
curl -s http://127.0.0.1:8080/v1/replies/draft \
  -H 'Content-Type: application/json' \
  -d '{"conversation_id":"demo","customer_message":"TD630G 在 Mac 上怎么无线打印？","messages":[]}'
```

Inspect recent draft history (customer data, so the admin token is required):

```sh
curl -s 'http://127.0.0.1:8080/v1/history?limit=5' \
  -H "X-Admin-Token: $RAG_ADMIN_TOKEN"
```

Filter by conversation:

```sh
curl -s 'http://127.0.0.1:8080/v1/history?limit=20&conversation_id=demo' \
  -H "X-Admin-Token: $RAG_ADMIN_TOKEN"
```

The alternative HTTP rebuild route requires `X-Admin-Token`; the CLI above is simpler. Docker must remain running only while the Flutter app needs retrieval or drafting. Message capture and its local SQLite database remain inside the macOS app and do not depend on Docker.

For local backend tests without Docker:

```sh
python3 -m venv .venv-rag
source .venv-rag/bin/activate
pip install -r backend/requirements-dev.txt
PYTHONPATH=backend pytest backend/tests
```

## Accessibility setup and AX mapping

1. Start Qianniu/Aliworkbench and log in.
2. In this app, click **Request Accessibility access**.
3. In **System Settings → Privacy & Security → Accessibility**, enable the built `.app` (or the Terminal/IDE launching `flutter run`). Restart the app after changing permission if macOS does not refresh it.
4. Select a real Qianniu conversation, click **Inspect AX tree**, and save the displayed output.
5. Validate which reported paths correspond to the sidebar row, unread marker, customer identity, message list, and composer before tightening selectors.
6. Click **Start capture** only after the tree is visible.

The installed app found during development is `/Applications/Aliworkbench.app`, bundle `com.taobao.Aliworkbench`, version `9.95.01`.

## Current capture behavior and limitations

- Polls at 700 ms so capture work stays independent of future AI work.
- Uses selected `AXRow`/`AXCell` plus structural scroll-area candidates. It does **not** assume Chinese or English element labels.
- Uses native AX identifiers when exposed; otherwise SHA-256 fingerprints include conversation, content, geometry, and AX path.
- SQLite uniqueness is a second dedupe boundary. `messages_recent` supports efficient last-20 retrieval.
- Direction is inferred from message position relative to the message container; it remains `unknown` when geometry is absent.
- Opening unread rows is intentionally not performed until an actual tree dump identifies the unread marker and conversation row on this installed Qianniu build. Blindly pressing a guessed row would violate conversation safety.
- Customer IDs and message timestamps are saved when exposed by a validated mapping; the generic discovery pass cannot invent them.

If the AX dump lacks customer identity, message text, unread state, or actionable conversation rows, record precisely those missing attributes first. Clipboard or targeted vision should be considered only for the missing fields.

For a minimal permission probe independent of Flutter:

```sh
clang -framework ApplicationServices tools/ax_probe.c -o /tmp/qianniu_ax_probe
/tmp/qianniu_ax_probe <qianniu-pid>
```

Development probe result on 2026-08-18: Qianniu launched as PID `32562`, but the calling process was not Accessibility-trusted, so macOS returned only `AXUnknown` and no child tree. Consequently the exact unread marker, customer ID, message container, composer attributes, and safe row action remain unmapped; the MVP does not guess or press them.

## Safety boundary

Windows can later implement the same Dart `CaptureAdapter` with UI Automation. Future sending must be a separate adapter and enforce:

`expected conversation → open chat → verify identity → insert → verify again → send`

The backend never controls desktop UI, and this MVP exposes no send capability.
