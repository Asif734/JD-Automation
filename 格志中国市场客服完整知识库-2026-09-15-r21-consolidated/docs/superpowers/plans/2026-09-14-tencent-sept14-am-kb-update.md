# Tencent Sept 14 AM KB Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply all user-confirmed Sept 14 AM workbook corrections to the current Grozziie customer-service KB and ship synchronized r20 retrieval artifacts and tests.

**Architecture:** Preserve Markdown sources as authority, use an idempotent apply script to upsert focused RAG cards and exact query routes, then regenerate chunks/index and build the formal package from one canonical version. Regression tests exercise actual search behavior and negative routing boundaries rather than merely checking prose.

**Tech Stack:** Python 3, JSON/JSONL, Markdown, `unittest`/pytest-compatible tests, existing RAG build and package scripts.

**Spec:** `docs/superpowers/specs/2026-09-14-tencent-sept14-am-kb-update-design.md`

## Global Constraints

- Update the existing database only; do not create a separate KB.
- Preserve unrelated content and product-family boundaries.
- The website remains usable for downloads, videos, and manuals; only direct customer-service contact options are closed.
- Customer-facing driver email must not volunteer that the thermal and dot-matrix package names refer to the same package.
- No release-completion claim is allowed without fresh source, retrieval, index, package, and test evidence.

---

### Task 1: Regression contract

**Files:**
- Create: `tests/test_confirmed_tencent_sept14_am_2026_09_14.py`
- Modify: `scripts/package_version.py`
- Modify: `scripts/audit_kb_conflicts.py`

**Interfaces:**
- Consumes: current r19 sources, cards, queries, index, and package metadata.
- Produces: failing behavior assertions for the approved r20 rules and resolution IDs `S14AM-C01` through `S14AM-C29`.

- [x] **Step 1: Write failing tests** for the corrected source facts, card fields, exact high-frequency routes, top-1 search results, negative one-way/Wi-Fi/ribbon/website behavior, and r20 version synchronization.
- [x] **Step 2: Run the focused test** with `python3 -m unittest tests.test_confirmed_tencent_sept14_am_2026_09_14 -v` and verify failure is caused by missing r20 behavior.
- [x] **Step 3: Add the r20 version and expected resolution IDs** only after the failing result is observed.
- [x] **Step 4: Re-run the focused version/audit subset** and preserve remaining expected failures until cards and sources are implemented.

### Task 2: Authoritative source corrections

**Files:**
- Create: `confirmed_tencent_sept14_am_updates_2026_09_14_kb.md`
- Modify: `confirmed_tencent_sept13_updates_2026_09_14_kb.md`
- Modify: `confirmed_dot_matrix_updates_2026_08_24_afternoon_kb.md`
- Modify: `dot_matrix_after_sales_issues_kb.md`
- Modify: `qianniu_customer_service_training_kb.md`
- Modify: `wifi_bluetooth_printer_kb.md`
- Modify: `printernoble_bluetooth_wifi_dot_matrix_kb.md`
- Modify: `printernoble_td630_dot_matrix_kb.md`

**Interfaces:**
- Consumes: approved design decisions.
- Produces: one provenance source plus corrected canonical passages referenced by cards/chunks.

- [x] **Step 1: Add the confirmed source document** with all scoped customer-service rules and workbook provenance.
- [x] **Step 2: Correct direct contradictions** for website scope, online/offline queues, ribbon universality, and ZTO/SF/JD freight.
- [x] **Step 3: Add missing operational details** for placeholders, permissions, templates, Windows Settings, app QR loading, same-phone hotspot, HarmonyOS, and no-scaling/no-Force-Stop boundaries.
- [x] **Step 4: Run the focused source assertions** and verify the source layer passes without weakening tests.

### Task 3: RAG cards and deterministic routes

**Files:**
- Create: `scripts/apply_confirmed_2026_09_14_tencent_sept14_am.py`
- Modify through the script: `rag_cards/customer_service_rag_cards.jsonl`
- Modify through the script: `rag_cards/high_frequency_queries.json`
- Modify through the script: `rag_cards/china_market_video_catalog.json`

**Interfaces:**
- Consumes: `PACKAGE_VERSION`, confirmed source filename, existing card IDs.
- Produces: idempotent card upserts, corrected existing cards, and exact query-to-card mappings.

- [x] **Step 1: Implement idempotent card upserts** for every missing behavior and stamp resolution/source/version metadata.
- [x] **Step 2: Narrow existing cards** so dark text cannot route to one-way printing, App QR loading cannot route to Wi-Fi, and dot-matrix ribbon guidance no longer demands same-model ribbons.
- [x] **Step 3: Add exact high-frequency queries** for every reviewed scenario that needs deterministic behavior, without duplicating normalized queries.
- [x] **Step 4: Run the apply script twice** and verify card/query counts remain stable.
- [x] **Step 5: Run focused card and exact-route tests** until they pass.

### Task 4: Generated retrieval artifacts

**Files:**
- Regenerate: `rag_cards/source_chunks.jsonl`
- Regenerate: `rag_index/customer_service_rag_index.json`

**Interfaces:**
- Consumes: current Markdown sources, active cards, and high-frequency queries.
- Produces: synchronized r20 chunks, keyword index, vectors, and exact routes.

- [x] **Step 1: Run** `python3 scripts/build_source_chunks.py`.
- [x] **Step 2: Run** `python3 scripts/build_rag_index.py`.
- [x] **Step 3: Run focused top-1 retrieval tests** and confirm every dangerous query reaches the approved card.
- [x] **Step 4: Run representative manual searches** for dark text, QR loading, ribbon compatibility, website resources, TH880 queues, HarmonyOS, App template editing, and Windows Settings.

### Task 5: Package and verification

**Files:**
- Regenerate: `README.md`
- Regenerate: `PACKAGE_MANIFEST.json`
- Create: parent-directory `格志中国市场客服完整知识库-2026-09-14-r20.zip`
- Update version assertions in existing tests that intentionally track the canonical release.

**Interfaces:**
- Consumes: synchronized r20 source/card/query/chunk/index state.
- Produces: verified r20 release package and integrity evidence.

- [x] **Step 1: Run all focused Sept 14 AM tests** and all existing non-video-pipeline tests.
- [x] **Step 2: Build the package** with `python3 scripts/package_grozziie_china_kb.py` and verify manifest hashes.
- [x] **Step 3: Run** `python3 scripts/audit_kb_conflicts.py` and require zero structural conflicts.
- [x] **Step 4: Run** `python3 scripts/test_rag_queries.py` and the focused manual retrieval matrix.
- [x] **Step 5: Inspect package contents, version metadata, duplicate IDs/routes, and unrelated-file preservation** before reporting completion.
