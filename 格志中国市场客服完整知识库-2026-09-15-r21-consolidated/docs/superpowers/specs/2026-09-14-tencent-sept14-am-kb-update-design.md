# Tencent Sept 14 AM KB Update Design

## Authority and scope

This specification records the user's confirmed decisions for the Tencent Docs workbook `Sept 14 (AM) Codex Test QnA Verification`, tab `Tmall QA Review`, rows 7–43. It updates the existing Grozziie China-market customer-service knowledge base; it does not create a separate database. Unrelated content must remain unchanged.

## Confirmed corrections

1. Repeated `*****`, `11111`, and `22222` characters in a preprinted-form template are temporary positioning and calibration placeholders for variable data. They have no special meaning and must be replaced by real data; fixed paper borders, labels, and text must not be printed again.
2. All relevant dot-matrix packages include a preinstalled ribbon, USB cable, and test paper. These three items do not require an exact model check; exact SKU checks remain necessary for extra bundle contents.
3. For App connection, scan the printer code labelled `app connect QR code` while the printer is on and paper is loaded. If scanning fails, use the App's manual Search route.
4. Guest and formal-account local templates both remain local and do not synchronize. Do not volunteer this fact when merely answering how to fill the login fields.
5. For missing App table lines, first set line width to `0.6` or `0.7`; the paper-thickness lever is an optional additional adjustment.
6. When TH880JM is grey/offline and TH880JMS is online, use TH880JMS and optionally make it the default. Do not delete an offline queue merely because another matching queue is online; clean reinstall is only for persistent genuine duplicate/incorrect-driver faults after connection, port, queue, and hidden-job checks.
7. Bidirectional printing is enabled in `Configure` by clearing `One-way printing`, then saving and testing.
8. On VIVO/Android, open SupPrint and select `DotMatrix Printer`; grant Bluetooth, location, and nearby-device permissions when the App prompts. Do not begin with a manual phone Settings route.
9. Do not invent a printer serial number. SupPrint does not require the printer serial number. The `Serial Number` template element is an optional printable field, not a device credential.
10. For slow printing visible in customer video/audio, lower print quality and clear `One-way printing`. Every customer video must be checked visually and audibly before replying.
11. If a quality-problem return cannot be cancelled and resubmitted, collect the tracking number for manual tracking and handoff. Approved ZTO return freight can be reimbursed; SF Express and JD Logistics must not be recommended and are not reimbursable. Evidence, amount, and final processing remain human-controlled.
12. Ribbons are universal across the supported new dot-matrix printer family. Preserve separate ribbon rules for attendance machines, thermal products, and excluded legacy products.
13. Default to Portrait. TH880JM and TH880JMS use the same paper sizes, so do not change drivers solely for paper size. Choose the correct size; if content remains small, adjust document margins, headers/footers, and document-side scaling.
14. In SupPrint templates, restore missing borders by selecting the table, setting line width to `0.6–0.7`, and confirming the preview.
15. The public website remains available for driver downloads, videos, manuals, and other resources. Only the website's direct customer-service contact options are closed. If the guide QR cannot be scanned, send the approved driver-download URL `https://www.zjweiting.com/download.htm`.
16. A fixed SupPrint template can be edited: open it, tap `Edit` in the upper-right corner, choose the required paper size, and add rows.
17. When a customer supplies a paper/document photo and an App-template photo and asks for layout correction, route to App template editing/support.
18. Other mobile billing Apps cannot print directly. Save/export the document and use `SupPrint → DotMatrix Printer → Document Printing`. Multipart paper up to `1+5` is not the same as requesting multiple software copies.
19. Clearing a stale Windows print job does not require a computer restart; clear the queue and `SPOOL/printers` hidden jobs.
20. Default USB data cables are `1.2 m`; a longer USB-A-to-USB-D data cable is acceptable when the connector matches and the cable carries data.
21. For a phone stuck on the printing screen after printer shutdown, remove SupPrint from recent tasks without Force Stop, power on the printer, load paper, reopen the App, and retry.
22. Windows Settings exposes `Print test page` after selecting the driver. In Control Panel, use right-click → Printer Properties → Print Test Page.
23. A QR-based App connection stuck loading is not initially a Wi-Fi/mobile-data fault. Confirm printer power and App Bluetooth/location permissions, then restart the printer, close the App, and retry.
24. SupPrint has no scaling option. For a saved Excel file, use `DotMatrix Printer → Document Printing`; do not invent an App scaling control.
25. The same phone may run SupPrint and provide a hotspot for Wi-Fi printing. Prefer Bluetooth when ordinary Wi-Fi is unavailable because it is simpler.
26. For HarmonyOS tablets, the ribbon is preinstalled, the Chinese-market App name is `速印通`/SupPrint, and Bluetooth is preferred unless Wi-Fi is explicitly requested.
27. Wi-Fi installation uses `Automatic → Search`; paper must be loaded. After the printer powers off, power it on again, reload paper, and let installation continue.
28. Do not promise a bulk discount. Ask the quantity and hand off to a human agent.
29. Dark, blurred, or merged text is unrelated to one-way printing. Lower SupPrint contrast and raise the paper-thickness lever to position 6 or as required by the print result.
30. Customer-facing driver email must not mention that `ThermalNobleDriver` and `DotNobleDriver` are the same package unless the customer specifically asks about package identity.

## Derived artifacts and release

- Add one authoritative confirmed-update source document inside the existing KB.
- Correct affected older source passages without deleting unrelated historical evidence.
- Update or add focused active RAG cards and deterministic high-frequency routes.
- Regenerate source chunks and the RAG index from the active sources/cards/routes.
- Add behavior-focused regression tests covering source-to-card-to-query behavior and dangerous negative routes.
- Bump the canonical package from `2026-09-14-r19` to `2026-09-14-r20`, synchronize catalog/query/index metadata, rebuild the manifest and ZIP, and run structural plus semantic verification.

