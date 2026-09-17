# Knowledge-Base Conflict Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Apply the user's approved C01-C20 and S01-S03 decisions across the authoritative knowledge base and all derived RAG/package artifacts, then perform a new whole-database conflict audit.

**Architecture:** Store the approved rules in an authoritative confirmed-update source, remove or gate contradictory wording in older authoritative sources, expose one active curated RAG card per corrected intent, and map representative queries to those cards. Drive all package-scoped versions from one Python constant, regenerate chunks and the index, and build a verified immutable release archive. Tests assert both required wording and forbidden obsolete branches.

**Tech Stack:** Markdown, JSON/JSONL, Python 3 standard library, pytest, SHA-256 manifest verification, deterministic ZIP packaging.

**Spec:** `docs/superpowers/specs/2026-09-13-kb-conflict-remediation-design.md`

**Global Constraints:** Preserve unrelated user content; do not fabricate missing evidence media; do not count X01 as a conflict; do not expose C19 routinely; defer new Mac installation/function guidance; keep inactive and quarantined video records intact; use `apply_patch` for hand edits and builders for generated artifacts.

---

### Task 1: Capture all approved rules in failing regression tests

**Files:**
- Create: `tests/test_conflict_remediation_2026_09_13.py`
- Modify: `tests/test_full_kb_package.py`
- Modify: `tests/test_attendance_stepper_lost_step_and_normal_video.py`

- [ ] Add helpers that load active JSONL cards and normalized high-frequency queries.
- [ ] Add C01-C20 assertions against the authoritative update source and curated card fields, including exact sequencing for C05, C12, C13, C14, and C18.
- [ ] Add forbidden-text assertions for unconditional SF rejection, unconditional .NET upgrade, customer-facing manual TCP/IP setup, ZIP-only installer wording, missing runtime `outputs/customer_video_analysis` paths, and explicit C19 routine wording.
- [ ] Import `PACKAGE_ROOT` from the package-version module in the package test.
- [ ] Replace the three nonexistent runtime-file assertions with explicit `artifact_availability == "metadata_only"` and existing packaged-evidence checks.
- [ ] Run the new/modified tests and confirm they fail for the pre-correction database.

### Task 2: Correct authoritative customer-service sources

**Files:**
- Create: `confirmed_conflict_remediation_2026_09_13_kb.md`
- Modify: `dot_matrix_after_sales_issues_kb.md`
- Modify: `confirmed_needle_printer_updates_2026_08_24_kb.md`
- Modify: `confirmed_dot_matrix_updates_2026_08_30_kb.md`
- Modify: `confirmed_dot_matrix_updates_2026_08_24_afternoon_kb.md`
- Modify: `confirmed_customer_service_updates_2026_08_18_kb.md`
- Modify: `printernoble_td630_dot_matrix_kb.md`
- Modify: `wifi_bluetooth_printer_kb.md`
- Modify: `confirmed_dot_matrix_tencent_review_updates_2026_09_07_kb.md`
- Modify: `confirmed_dot_matrix_panel_paper_position_2026_09_08_kb.md`
- Modify: `all_platform_model_details_2026_09_09_kb.md`
- Modify: `dot_matrix_windows_usb_driver_install_kb.md`

- [ ] Add the 20 approved decision branches and customer/internal boundaries to the new confirmed-update source.
- [ ] Patch old unconditional or wrong-order wording so it cannot conflict with the confirmed update when chunked.
- [ ] Ensure C02 and C13 use the user's requested order, C19 remains internal, C20 states default 1.2 m and connector/data compatibility, and C06 contains no invented future Mac instructions.
- [ ] Run the authoritative-source subset of the regression tests and confirm it passes.

### Task 3: Update curated RAG cards and high-frequency routing

**Files:**
- Modify: `rag_cards/customer_service_rag_cards.jsonl`
- Modify: `rag_cards/high_frequency_queries.json`

- [ ] Add or update 20 active conflict-remediation cards with `source_files`, ordered actions, customer-facing templates, internal boundaries, and escalation behavior matching the approved rules.
- [ ] Route representative queries for each corrected issue to the intended active card without duplicating normalized queries.
- [ ] Remove nonexistent runtime evidence paths from the two affected attendance cards and mark metadata-only availability explicitly.
- [ ] Update relevant tutorial-catalog card package versions to the package revision without rewriting historical component versions unrelated to the package conflict.
- [ ] Run JSON/JSONL parse, unique-ID, normalized-query uniqueness, and dangling-card-reference tests.

### Task 4: Unify package-scoped version metadata

**Files:**
- Create: `scripts/package_version.py`
- Modify: `scripts/package_grozziie_china_kb.py`
- Modify: `scripts/build_rag_index.py`
- Modify: `scripts/import_china_market_video_catalog.py`
- Modify: `rag_cards/china_market_video_catalog.json`
- Modify: `rag_cards/high_frequency_queries.json`
- Modify: `tests/test_full_kb_package.py`
- Modify: `tests/test_china_market_video_catalog.py`

- [ ] Define `PACKAGE_VERSION = "2026-09-13-r16"` and the derived Chinese `PACKAGE_ROOT` once.
- [ ] Import the constant in package/index/catalog builders and tests.
- [ ] Rebuild or patch package-scoped JSON metadata to r16.
- [ ] Test that all declared package versions equal the single constant and no package-scoped r14/r15 remains.

### Task 5: Regenerate chunks, index, manifest, and release package

**Files:**
- Regenerate: `rag_cards/source_chunks.jsonl`
- Regenerate: `rag_index/customer_service_rag_index.json`
- Regenerate: `PACKAGE_MANIFEST.json`
- Regenerate: `README.md`
- Create: `outputs/格志中国市场客服完整知识库-2026-09-13-r16.zip`

- [ ] Run `scripts/build_source_chunks.py` from the database root.
- [ ] Run `scripts/build_rag_index.py` and confirm active-card/chunk/query counts are internally consistent.
- [ ] Build the r16 archive with `scripts/package_grozziie_china_kb.py --verify`.
- [ ] Confirm every manifest size/hash and archive member verifies.
- [ ] Run the full test suite in an isolated local test environment.

### Task 6: Perform a fresh whole-database conflict audit

**Files:**
- Create: calling-task `outputs/Grozziie_KB_Post_Correction_Audit_2026-09-13_EN.md`
- Create: calling-task `outputs/Grozziie_KB_Post_Correction_Visual_Report_2026-09-13_EN.html`

- [ ] Scan all authoritative Markdown, active cards, high-frequency queries, source chunks, index metadata, tests, and package metadata for the 23 resolved conflict signatures.
- [ ] Scan for duplicate IDs/queries, dangling mappings, missing source references, forbidden `outputs/` payload references, broken manifest entries, version drift, and stale generated text.
- [ ] Verify inactive `needs_reupload` and quarantined-wrong-topic video records remain inactive/quarantined.
- [ ] Record counts, executed checks, corrections, any residual conflicts, and correction suggestions in English.
- [ ] Open the visual report in Codex for user review.

### Task 7: Final self-review

- [ ] Compare every changed rule line-by-line with the approved design specification.
- [ ] Confirm only obsolete statements and stale generated copies were removed.
- [ ] Confirm C06's future Mac additions were not invented and X01 was not treated as a blocker.
- [ ] Re-run focused regression tests, the full suite, package verification, and whole-database audit from a clean command invocation.
- [ ] Report the database root, r16 package, Markdown audit, visual report, tests, and any environment limitation with exact evidence.
