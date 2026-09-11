# Validation record — 2026-09-06

Everything in this folder was re-verified against a real Purview eDiscovery **Standard** export
before the test data was removed. This file records what was checked and what was found.

## Defects found and fixed in this pass

| # | Defect | Effect on the report | Fix |
|---|---|---|---|
| 1 | `Complete-Row` declared its parameter as `[hashtable]`, so the ordered row was coerced and lost insertion order | CSV and JSON columns emitted in random order (`Actor, Conversation, Attachments, Citations, ItemClass, Prompt, ...`) | Parameter typed as `[System.Collections.Specialized.OrderedDictionary]` |
| 2 | `Get-Body` only fell back to `HTMLBody` when `Body` was empty | On every attachment turn the answer was **silently discarded**; the Response column held just the file link (~196 chars instead of ~3,000) | The adaptive card is now decoded from either body, and the plain body is merged with the decoded answer |
| 3 | Attachments were captured by dumping any body containing `http` | A 4,295-character answer with no attachment at all was listed as an attachment | Attachments are identified structurally: a message whose entire body is file references |
| 4 | Grounded tenant files were reported as user attachments | Work-mode rows listed 9 SharePoint templates as if the user had uploaded them | New `GroundedFiles` column separates Copilot-referenced sources from user uploads |
| 5 | Web-search keyword regex only matched a bold `**...**` label | `### Exact Bing search terms used` was missed, so a genuine web search showed no keywords | Regex accepts bold or any heading level |
| 6 | Citations included tenant URLs | SharePoint and OWA links appeared as if they were web citations | Citations exclude file-reference URLs (after stripping the `EntityRepresentationId` suffix) and all tenant hosts |
| 7 | `Conversation` column was blank on 15 of 15 rows | Dead column | Replaced with `PromptLabel` (`prompt 1` … `prompt N`) |
| 8 | `Add-TextNodes` was redefined on every `Get-Body` call | Wasteful, harder to reason about | Promoted to a top-level function |
| 9 | `.EXAMPLE` block referenced machine-specific paths | Misleading for the customer | Replaced with neutral paths |

## Verification run

Source: the Purview Standard export for `M365CPI78116917`, 3 PSTs, 15 seeded prompts
(5 each for AmberR, LisaT, WillB), window `2026-09-06T00:00:00Z` to `2026-09-07T00:00:00Z`,
time zone `Eastern Standard Time`.

| Check | Result |
|---|---|
| Script parses (AST) | Pass |
| Rows produced | 15 |
| Rows per actor | AmberR 5, LisaT 5, WillB 5 |
| Blank prompts | 0 |
| Blank responses | 0 |
| Actor attribution | Correct per PST, no collapsing |
| Column order in CSV and JSON | Correct, matches the documented order |
| Attachment turns | 6 rows, exactly 1 attachment each, correct file name and URL |
| Answer text on attachment turns | Recovered (2,713–6,273 chars; previously 195) |
| Grounded files | Only LisaT Work-mode rows (9 and 2), correctly excluded from Attachments |
| Web search keywords | Captured on both turns that reported them (AmberR prompt 1, LisaT prompt 3) |
| Citations | 5 URLs, all `learn.microsoft.com`; zero tenant URLs leaked |
| Web search detection | 4 of 15 turns flagged `WebSearchUsed = Yes`, including WillB prompt 1 |
| Runs without `Items_*.csv` | Pass, verified separately |
| Completion time | Well under a minute for 3 PSTs |

## Finding: web search was NOT disabled for the Copilot Chat (Basic) pilot user

An earlier draft of this file claimed that WillB showing zero keywords and zero citations proved the
Cloud Policy web-search restriction was working. **That conclusion was wrong.** Zero keywords is
absence of evidence, not evidence of enforcement.

Re-reading the same export shows WillB's prompt 1 response begins with `Searching...` and carries
36 inline source reference markers. Web grounding ran for him. This was confirmed independently in
the tenant UI, where the same account, badged **Copilot Chat (Basic)**, answered a current-events
question with live `abc7ny` and `google` sources.

Two consequences:

1. The Cloud Policy configuration intended to disable web search for unlicensed Copilot Chat users
   did not take effect. Treat this as an open configuration issue, not a solved one.
2. The report generator needed a reliable web-grounding signal, since keywords and external URLs are
   both frequently absent. `WebSearchUsed` now derives from the `Searching...` status Copilot emits,
   reported keywords, or an external citation, whichever appears first.

## Known behavior, not a defect

- Copilot Chat (Basic) often cites with inline markers such as `【1-67b5b2】` and omits the URL from
  the exported body. On those rows **Citations is empty even though a web search occurred**. The
  **Web search keywords** column is the reliable web-grounding signal.
- Outlook must be closed before running. A running instance can block COM with
  `0x80080005 CO_E_SERVER_EXEC_FAILURE`.
- Detaching PST stores at the very end can be slow. The report files are written **before** detach,
  so the output is already safe if you interrupt at that point.

## Folder contents after cleanup

| File | Purpose |
|---|---|
| `RUNBOOK.md` | Customer-facing setup and export procedure |
| `README.md` | Script inputs, outputs, and column reference |
| `Get-CopilotChatComplianceReport.ps1` | Report generator |
| `Test-ComplianceSearchScope.ps1` | Validates mailbox identities before creating the search |
| `Screenshots\` | 33 PNGs referenced by the runbook |
| `VALIDATION.md` | This record |

All test inputs and prior report output have been deleted. The folder holds no tenant data.
