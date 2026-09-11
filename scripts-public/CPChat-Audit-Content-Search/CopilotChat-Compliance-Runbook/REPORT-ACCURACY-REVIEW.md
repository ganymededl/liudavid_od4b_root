# Report Accuracy Review — 2026-09-06

Two questions were raised against the first report. Both were valid. Both were defects, and
both are fixed. This documents what was wrong, why, and what changed.

---

## Question 1 — "I thought there were 12 admin prompts plus Aadi's. Why only 11 rows?"

The correct answer for this export is **13 rows**, not 11. The report was under-counting by
two, and a further six turns were never collected by the search at all.

### Ground truth vs. what the report showed

| | Turns |
|---|---|
| Admin prompts seeded (per `data/seed-index.json`) | 14 |
| Admin turns actually present in the export | 13 |
| Admin turns the old report showed | 11 |
| Admin turns the fixed report shows | **13** |
| Aadi (licensed cohort) prompts seeded | 5 |
| Aadi turns present in the export | **0** |

### Cause A — the de-duplication logic deleted two real turns

The old dedupe key was `Topic | PromptText`. Two threads in the pilot are legitimately
distinct but share both values:

| Thread | `CopilotConversationId` | Prompts |
|---|---|---|
| Expense Policy Update Notice | `dc7abddb-c659-4ae4-8519-09d565fe5904` | 03, 04 |
| Expense Policy Update Notice | `4714ce4c-b61a-4ec3-ad5a-698477659b7a` | 03, 04 |

These are two separate conversations — the Copilot Chat UI spawned a second thread while the
first was still streaming. `seed-index.json` records this deliberately, precisely to test that
the report surfaces near-identical prompts in separate threads. The old key collapsed them and
silently discarded 2 turns.

This is the dangerous class of bug for a compliance tool: **a user re-asking the same question
is a normal, real, individually-reportable event**, and text-similarity dedupe erases it.

**Fixed** — the key is now `CopilotConversationId | SkypeItemId`. A turn is only collapsed when
the *same message* was exported twice. Distinct threads always survive.

### Cause B — PROMPT 12 is genuinely absent from the export

`seed-index.json` lists the Azure Storage thread (`c244d060-…`) as 2 turns, prompts 11 and 12.
The exported transcript for that thread contains one user message and four Copilot messages,
all timestamped within `2026-09-05T03:00:39Z`–`03:00:40Z`. A search of every file in the export
for the string `PROMPT 12` returns nothing.

The follow-up turn was not captured by the search. Re-run the search over a window that ends
well after the activity to pick it up.

### Cause C — Aadi's 5 prompts were never collected (scope fault)

The export contains exactly one mailbox:

```
ExportExtracted\Exchange\admin@diax38232937.onmicrosoft.com
```

The Content Search was scoped with this mailbox list:

```
admin@diax38232937.onmicrosoft.com,
aadi.kapoor@diax38232937.onmicrosoft.com,
alice.smith@diax38232937.onmicrosoft.com,
bob.johnson@diax38232937.onmicrosoft.com,
charlie.brown@diax38232937.onmicrosoft.com,
diana.prince@diax38232937.onmicrosoft.com,
emma.watson@diax38232937.onmicrosoft.com,
frank.miller@diax38232937.onmicrosoft.com
```

Checked against the tenant's actual user list (`data/users-before.json`), **seven of those
eight addresses do not exist**. Aadi's real UPN is `AadiK@DIAx38232937.OnMicrosoft.com`, not
`aadi.kapoor@…`.

`New-ComplianceSearch` accepted every one of them without error. Non-resolving locations
contribute zero items and produce no warning, so the export completed, looked healthy, and was
missing an entire cohort.

The download timestamp rules out a timing explanation: Aadi seeded at 2026-09-05 16:51–16:54
EDT and the export ZIP was produced 2026-09-06 10:33 EDT, nearly 18 hours later.

**Fixed** — added `Test-ComplianceSearchScope.ps1`, which resolves every identity against
Exchange Online, flags any that resolve to a different primary address, hard-fails on any that
do not resolve, and emits a validated `-ExchangeLocation` string. RUNBOOK Phase 2a now requires
running it before creating a search, and Phase 2c requires reconciling per-mailbox hit counts.

---

## Question 2 — "The WebSearchKeywords don't look like Bing queries"

Correct. Only the first row was right, and that was coincidence.

### What was wrong

The old script inferred keywords by regex-scraping the **prose of Copilot's answer**:

```powershell
[regex]::Matches($Body, 'Searching for ([^\r\n.]{3,120})')
[regex]::Matches($Body, '(?:search|query)(?:\s+term)?:?\s+["\x27]?([^"\x27;\n]{5,80})')
```

Any sentence containing the word "search" or "query" matched. That produced the garbage you
circled:

- `results, so these drafts are based solely on the details you provided.`
- `EntityRepresentationId=923be67a-d138-46c5-b6c2-d69e49f30928) and iden…`
- `solutions; and API results while noting the date of the sources. I`

None of those were ever sent to Bing. The `NIST publications** ; MFA requirements**` value
looked plausible only because those words happened to sit next to "search" in the answer text.

### The authoritative field

Copilot writes a `LinksBlob` property on each response message recording what it actually
retrieved. It is a JSON array embedded as a JSON string. Search queries appear as:

```json
{"@type":"WebSearchQuery",
 "url":"queries=[\"site:pages.nist.gov 800-63B-4 MFA enterprise latest\"]",
 "isCitedInResponse":true}
```

Citations appear alongside as:

```json
{"@type":"CITATION",
 "url":"https://csrc.nist.gov/pubs/sp/800/63/B/4/final",
 "linkMetadata":{"…":{"displayData":{"content":{"metadata":{"type":"Web"},
   "providerDisplayName":"SP 800-63B-4, Digital Identity Guidelines…"}}}}}
```

`LinksBlob` additionally contains `bing.com/search?q=<url-encoded query>` citation URLs, which
independently corroborate the extracted terms.

**Fixed** — `Get-CopilotLinkFacts` parses `LinksBlob` directly. Nothing is inferred from
narrative text.

### Extracted terms, after the fix

| Conversation | WebSearchKeywords |
|---|---|
| Purchase Order vs Invoice Explained | `purchase order vs invoice` |
| Latest NIST MFA Guidance Summary | `site:pages.nist.gov 800-63B-4 MFA enterprise latest` \| `site:csrc.nist.gov/pubs/sp/800/63/b/4/final publication date` |
| EU AI Act Compliance Deadlines 2026-2027 | `EU AI Act 2026 2027 compliance deadlines` \| `EU AI Act application dates European Commission August 2026 August 2027` |
| Azure Storage Security Best Practices Summary | `site:learn.microsoft.com Azure Storage security recommendations best practices` |

The remaining 9 turns show `WebSearchUsed = No` with an empty keyword cell. That is a true
negative — those turns have no `WebSearchQuery` entry in `LinksBlob` because Copilot answered
from the model or from an attached file. This matches `seed-index.json`, which marks exactly
4 conversations as `webGrounded: true`.

---

## Question 3 — "Why not emit the JSON so admins can search the fields themselves?"

Added. Every run now writes three files.

| File | Purpose |
|---|---|
| `CopilotChat-ComplianceReport.csv` | Flat, one row per turn, for reviewers |
| `CopilotChat-ComplianceReport.json` | Full fidelity per turn — untruncated responses, all keywords, citations with titles, and a `FieldProvenance` block naming the source field for every value |
| `CopilotChat-RawMessages.json` | One object per raw message (user and Copilot), for verifying the CSV against source |

Every turn in the detailed JSON carries its own provenance map:

```json
"FieldProvenance": {
  "PromptText":        "ItemData.content  (message where ItemData.messageFrom starts \"8:orgid:\")",
  "ResponseText":      "ItemData.content  (message where ItemData.messageFrom starts \"28:\"); base64 SWIFT/AdaptiveCard decoded when present",
  "WebSearchKeywords": "LinksBlob[] -> entries with \"@type\":\"WebSearchQuery\" -> url = queries=[\"...\"]",
  "Citations":         "LinksBlob[] -> entries with \"@type\":\"CITATION\" -> url / linkMetadata.providerDisplayName",
  "Attachments":       "ItemData.properties -> copilotMetadata.messageAnnotations[] where messageAnnotationType = \"LocalFile\"",
  "TimestampUtc":      "CreatedDateTime (top-level, regex-read from raw JSON text)",
  "ConversationId":    "CopilotConversationId (top-level)"
}
```

Example — pull every search term the tenant issued, straight from the raw messages:

```powershell
$raw = Get-Content .\CopilotChat-RawMessages.json -Raw | ConvertFrom-Json
$raw | Where-Object { $_.WebSearchQueries.Count -gt 0 } |
       Select-Object SourceFile, CreatedUtc, @{n='Queries';e={$_.WebSearchQueries -join ' | '}}
```

---

## Field reference

Copilot Chat message, as exported by Purview eDiscovery:

| Field | Location | Notes |
|---|---|---|
| `CreatedDateTime` | top level | ISO-8601 UTC. Read by regex from raw text — `ConvertFrom-Json` coerces these to `[DateTime]` with unreliable `Kind`, inconsistently between sibling blocks in the same file. |
| `CopilotConversationId` | top level | Thread identity. The only safe dedupe discriminator. |
| `SkypeItemId` | top level | Message identity. |
| `Topic` | top level / `ItemData.topic` | Conversation title. |
| `ItemData` | top level, JSON-in-string | Contains `messageFrom`, `content`, `properties`. |
| `ItemData.messageFrom` | inside `ItemData` | `8:orgid:{guid}` = human, `28:{guid}` = Copilot service bot. |
| `ItemData.content` | inside `ItemData` | Prompt or answer. May be a `<URIObject type="SWIFT.1">` with a base64 Adaptive Card. |
| `ItemData.properties.copilotMetadata.messageAnnotations[]` | nested | `messageAnnotationType: "LocalFile"` names attachments. |
| **`LinksBlob`** | top level, JSON-in-string | **Authoritative retrieval record.** `WebSearchQuery` entries carry search terms; `CITATION` entries carry cited URLs and titles. |
| `RecipientsPreview.Sender` | top level, JSON-in-string | Actor display name and address. |

---

## Verified output — this tenant

```
Turns in range     : 13
Distinct threads   : 10
Actors             : 1        <- expected 2; see Cause C
Used web search    : 4        <- matches seed-index.json webGrounded count
Had attachments    : 2        <- matches seed-index.json withAttachments count
Messages captured  : 41
```

Prompts present: 01–11. Prompt 12 absent (Cause B). Prompts L1–L5 absent (Cause C).

## To close the remaining gaps

1. Run `Test-ComplianceSearchScope.ps1` against the real UPNs, notably
   `AadiK@DIAx38232937.OnMicrosoft.com`.
2. Recreate the Content Search using the validated `-ExchangeLocation` string.
3. Set the window to cover 2026-09-04 through 2026-09-06 so PROMPT 12 and Aadi's L1–L5 fall
   inside it.
4. Export, extract, re-run the report. Expect 19 turns across 2 actors.
