# 2026-09-13 Knowledge-Base Conflict Remediation Design

## Authority and scope

This specification records the user's approved decisions for the 2026-09-13 whole-database conflict audit. It controls the correction of the active Grozziie China-market customer-service knowledge base, its curated RAG cards, high-frequency queries, generated source chunks, search index, regression tests, package metadata, manifest, and release archive.

The English visual report and Markdown inventory in the calling Codex task are the review evidence. This file is the in-database implementation authority. Existing unrelated knowledge remains unchanged.

## Approved content decisions

1. C01: Keep paper-loading, orientation, paper-size, margin, and fixed-page-height checks. If the print start position is still wrong, clean the corresponding paper sensor.
2. C02: For mobile text that is too bold, lower contrast and raise the paper-thickness wrench to the top position (6th) or to the position required by the print effect. This prevents overly bold text. Do not present Windows-only controls as mobile controls.
3. C03: Tmall normally ships by ZTO. Do not promise SF Express or promise that a note will secure it. If the customer offers to pay the difference, transfer to human service to check whether a special paid arrangement is possible.
4. C04: Normally install .NET 4.8 when required. On Windows 7, either install .NET 4.8 or manually install the printer driver; the manual route does not require a .NET upgrade.
5. C05: For a gray/offline Windows printer, first restore physical USB detection and look for the usual AT32 device. Only after detection should queue, Offline, and port checks run.
6. C06: On macOS, `NOBLE PARAGON TD630 SZ` is the installed queue/driver name, not the physical-device name. Offline normally means power or USB connection should be checked. Printer-installation guidance and additional Mac functions are deferred until the user supplies them.
7. C07: For vertical-feed discontinuity, separated table sections, or an abnormal blank band, enable one-way printing first, then transfer for maintenance if it remains. Clear horizontal printhead-motion lost-step remains a repair branch.
8. C08: Garbled-output routing must cover hidden jobs, USB/port faults, an incompatible third-party mobile app used for direct printing, and an unsupported/incorrect Mac driver. Select only evidence-supported branches.
9. C09: For horizontal drag marks, first power off, remove the ribbon, clean foreign material around the printhead/bracket, and test without the ribbon using multipart paper. A persistent obvious scratch indicates a pin that cannot retract and requires printhead repair/replacement.
10. C10: Multipart forms should be one joined set. Replace or correctly align curled, folded, or separated layers before diagnosing the printer.
11. C11: Some new housings may not show a prominent manufacturer logo. Products may be grouped by print width, while model information remains on the machine or label. Do not invent an exact model; request the label only when needed.
12. C12: Split combined shutdown/no-feed symptoms. For shutdown, test another known-working outlet and transfer for maintenance if it persists. For no feed, insert from the front and clean the corresponding paper sensor if it does not feed. Do not prescribe removing USB or pressing Feed for this combined symptom.
13. C13: For non-fixed broken characters, first diagnose the ribbon or printhead; only then adjust font and paper thickness.
14. C14: When isolated missing strokes occur but table lines and other fonts are normal, treat font/glyph compatibility first. Diagnose hardware only if the same fixed defect remains across fonts.
15. C15: Remove paper, hold Power until the red light flashes, then release. If shutdown still fails, disconnect the power supply.
16. C16: Normal Windows Wi-Fi setup is `Automatic -> Search`; it installs the wireless driver/port automatically. Manual `Standard TCP/IP` is an internal, exceptional fallback only and must not appear in normal customer templates.
17. C17: ZIP packages require extraction; EXE packages run directly. If ZIP extraction fails, download and run the EXE.
18. C18: For overlap on a Windows test page, first reposition the paper's starting edge or print an actual document instead. If the actual document also overlaps, check paper size and driver installation.
19. C19: Internally, `Configure` opens a separate driver-settings window and a nearby date/build number is not a model or feature. Do not mention this routinely in customer-facing replies.
20. C20: USB cable length is not an issue when the printer connector matches and the cable supports data. The default supplied cable is 1.2 meters.

## Approved structural decisions

1. S01: Package-name tests must import the package-root constant instead of duplicating a stale revision.
2. S02: The missing runtime video-analysis fixtures must not be fabricated. Because `outputs/` is intentionally excluded from the formal package and the files no longer exist, preserve verified evidence metadata, mark the normal reference as metadata-only, remove nonexistent runtime paths, and test the explicit availability state plus packaged evidence that actually exists.
3. S03: One package revision must drive the package builder, RAG index, high-frequency-query metadata, video-catalog metadata, relevant catalog cards, manifest, and release archive.
4. X01: The number of source test questions is not a blocking conflict. No fixed total is required; regression coverage may grow as corrections and additions are received.

## Release and generation policy

- Use the next package revision, `2026-09-13-r16`.
- Authoritative Markdown and curated RAG cards are edited first.
- `source_chunks.jsonl` and the RAG index are regenerated from their builders; generated records are not hand-edited.
- The manifest and release archive are rebuilt from the corrected payload and verified by SHA-256.
- No unrelated source document, valid exception branch, quarantined video assignment, or inactive `needs_reupload` record is deleted.

## Acceptance criteria

- Regression tests cover C01-C20 and S01-S03, including the user's overrides for C02, C13, C19, and C20.
- No active customer-facing content contains a rule that contradicts the approved decisions.
- Curated card IDs and normalized high-frequency queries remain unique, and all high-frequency mappings target active cards.
- Generated chunks contain the corrected source text, and the index is rebuilt from current cards/chunks.
- Every package manifest entry exists and matches its size and SHA-256.
- The complete test suite passes in a declared test environment; environment-only skips, if any, are reported separately from database conflicts.
- A fresh whole-database re-audit reports any remaining conflict by exact path and rule, or explicitly reports zero unresolved conflicts in the audited scope.
