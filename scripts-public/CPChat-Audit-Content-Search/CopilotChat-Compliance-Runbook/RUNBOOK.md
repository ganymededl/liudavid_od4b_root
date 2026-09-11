# Copilot Chat Compliance Audit Runbook

> ## ⚠️ SUPERSEDED — DO NOT USE
>
> This document contains guidance that is **incorrect for eDiscovery Standard**, including
> Premium-only "Native / HTML transcript" export instructions and an unnecessary
> `-AuditEventsPath` audit-log dependency.
>
> **Use instead:** `C:\Scout_Output\917tenantv2\RUNBOOK.md`
>
> See `SUPERSEDED.md` in this folder for the full list of corrections.

**Objective**: Audit Copilot Chat usage over a 7-day window, capturing prompts, responses, web-search keywords, attachments, and citations for management review.

**Audience**: Exchange Online / Purview administrators

**Estimated Time**: 15-30 minutes (assuming eDiscovery is already available)

---

## Prerequisites

### Tenant Requirements
- **eDiscovery Standard or Premium** (to create content searches and export results)
- **Unified Audit Log** enabled (enabled by default; check via `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true`)
- **Copilot Chat** deployed to a pilot user group (recommend 5-15 users for initial audit)

### Role Requirements
- **eDiscovery Manager** (or higher) in the Microsoft Purview Compliance Portal
- **Search and Purge** role (to query the audit log)

### What You'll Need
1. **This runbook** (RUNBOOK.md)
2. **PowerShell script**: `Get-CopilotComplianceReport-ExportOnly.ps1` (provided in this folder)
3. **A text editor** (to update the script parameters before running)

---

## Step-by-Step Guide

### Phase 1: Create a Purview eDiscovery Case (if needed)

If you don't already have an eDiscovery case for this audit, create one:

1. Open **Microsoft Purview Compliance Portal** → **eDiscovery** → **Standard**
2. Click **+ Create a case**
3. Name: `Copilot-Chat-Pilot-Audit-[date]` (e.g., `Copilot-Chat-Pilot-Audit-2026-09-06`)
4. Click **Create**

---

### Phase 2: Create a Content Search

#### 2a. Validate your mailbox scope FIRST (do not skip)

`New-ComplianceSearch` accepts an `-ExchangeLocation` value that does not resolve to a real
mailbox. It does **not** error and does **not** warn — the location simply contributes zero
items. The export then completes successfully and is quietly missing that user's entire
history, with nothing in the UI or the logs to indicate a problem.

This is not hypothetical. In the pilot run for this solution the search was scoped to
`aadi.kapoor@<tenant>.onmicrosoft.com` while the account's real UPN was
`SampleUser@<tenant>.onmicrosoft.com`. The export came back containing only the admin's mailbox
and looked completely healthy.

Run the bundled validator before you create the search:

```powershell
Connect-ExchangeOnline
Connect-IPPSSession

.\Test-ComplianceSearchScope.ps1 -Mailbox `
    'SampleUser@contoso.onmicrosoft.com','admin@contoso.onmicrosoft.com'
```

It resolves every identity against Exchange Online, flags any that resolve to a *different*
primary address, hard-fails on any that do not resolve at all, and prints a ready-to-paste
`-ExchangeLocation` string built from the resolved addresses. Use that string verbatim.

#### 2b. Create the search

1. In your case, click the **Searches** tab
2. Click **+ New search**
3. Name: `CopilotChat-[date-range]` (e.g., `CopilotChat-2026-09-04-to-2026-09-06`)
4. In **Locations**, select:
   - **Exchange mailboxes** for every pilot user (use the validated list from step 2a)
   - **Teams channels** (if users also use Copilot in Teams)
   - Do NOT select SharePoint or OneDrive (Copilot Chat messages are not stored there)
5. In **Conditions**, add:
   ```
   Keyword: RecordType:TeamsConversation OR ItemClass:IPM.SkypeTeams.Message.Copilot
   ```
   **Explanation**: `ItemClass` targets Copilot Chat items specifically; `RecordType:TeamsConversation` captures Teams audit records.
6. Set the **date range** to your audit window (e.g., Sept 4–6, 2026)
7. Click **Save & Run**

The search will take 5–30 minutes depending on mailbox count and activity volume.

#### 2c. Reconcile the result against expectations

Before exporting, confirm the search results include **every** mailbox you scoped. If a pilot
user shows zero items, treat that as a scope or timing fault to investigate — not as evidence
that the user was inactive. Two things silently produce an empty-but-successful result:

- a mailbox identity that did not resolve (step 2a)
- a search run before Copilot activity finished indexing (allow a few hours after the activity)


---

### Phase 3: Export the Search Results

Once the search completes:

1. Go back to the **Searches** tab and select your search
2. Click **Export results**
3. In the export dialog, choose:
   - **Export items**: All items in search results
   - **Export format**: Native (this exports Copilot Chat conversations as .html transcripts)
   - **Output**: Keep the default (individual messages)
4. Click **Export**

**Note**: The export will take 5–15 minutes. You'll receive an email when it's ready.

5. Download the export ZIP file to your local machine (e.g., `C:\MyExport\CopilotChat_Export.zip`)
6. **Extract the ZIP** to a folder (e.g., `C:\MyExport\CopilotChat_Extracted\`)

The extracted folder should look like:
```
CopilotChat_Extracted\
  ├── Exchange\
  │   └── user1@tenant.onmicrosoft.com\
  │       └── TeamsMessagesData\
  │           ├── Conversation_1.html
  │           ├── Conversation_2.html
  │           └── ...
  └── SharePoint\
      └── ...
```

---

### Phase 3b (Optional, Recommended): Export Copilot audit payload for entrypoint mapping

The eDiscovery export gives prompt/response content, but not a reliable Copilot entrypoint
label (web URL vs Teams app vs Outlook). The entrypoint lives in the `CopilotInteraction`
audit payload. To enrich the report with entrypoint fields, also export audit events:

```powershell
Connect-ExchangeOnline

$start = [datetime]'2026-09-04T00:00:00Z'
$end   = [datetime]'2026-09-07T00:00:00Z'

Search-UnifiedAuditLog `
  -StartDate $start `
  -EndDate $end `
  -RecordType CopilotInteraction `
  -ResultSize 5000 |
  Select-Object CreationDate, UserIds, AuditData |
  ConvertTo-Json -Depth 8 |
  Set-Content -Encoding UTF8 "C:\Reports\CopilotAuditEvents.json"
```

Pass this JSON file to Phase 4 via `-AuditEventsPath`.

Best result: pass raw `AuditData` as shown above. The script then joins content-search turns
to audit rows by `CopilotEventData.ConversationId`, actor, and nearest timestamp. If you only
have an older audit-only CSV that already flattened away `AuditData`, the script can still
fall back to `ThreadId`, but the entrypoint label may be host-derived and less specific.

---

### Phase 4: Generate the Compliance Report

1. **Open PowerShell** as Administrator
2. Navigate to the folder containing the script:
   ```powershell
   cd "C:\Path\To\Script\Folder"
   ```
3. Run the report script:
   ```powershell
   .\Get-CopilotComplianceReport-ExportOnly.ps1 `
     -ExportPath "C:\MyExport\CopilotChat_Extracted" `
     -StartUtc ([datetime]'2026-09-04T18:00:00') `
     -EndUtc ([datetime]'2026-09-06T18:00:00') `
     -OutputFolder "C:\Reports" `
     -TimeZoneId "Eastern Standard Time" `
     -AuditEventsPath "C:\Reports\CopilotAuditEvents.json"
   ```

   **Parameter explanations**:
   - `-ExportPath`: Full path to the extracted eDiscovery export folder
   - `-StartUtc`: Audit window start (UTC)
   - `-EndUtc`: Audit window end (UTC)
   - `-OutputFolder`: Where to write the report files
   - `-TimeZoneId`: Windows timezone for report timestamps (e.g., "Eastern Standard Time", "Pacific Standard Time", "UTC")
   - `-AuditEventsPath` (optional): JSON/CSV export of `Search-UnifiedAuditLog` rows for entrypoint enrichment (`AppIdentity`, `AppHost`)

4. The script will:
   - Parse all .html transcript files
   - Extract prompts, responses, attachments, web-search terms, and citations
   - Collapse only re-exported copies of the *same* message (see "De-duplication" below)
   - Correlate content-search transcript turns with optional audit payload rows
   - Write four files to `-OutputFolder`

| File | Contents |
|------|----------|
| `CopilotChat-ComplianceReport.csv` | Flat, reviewer-friendly. One row per conversation turn. |
| `CopilotChat-ComplianceReport.json` | Full fidelity per turn — untruncated responses, all keywords, all citations with titles, plus a `FieldProvenance` map naming the exact export field each value came from. |
| `CopilotChat-RawMessages.json` | One object per raw message (user *and* Copilot), for field-level searching when you want to verify the CSV against source. |
| `CopilotChat-ComplianceReport.html` | Interactive reviewer report combining prompt/response content with entrypoint fields when `-AuditEventsPath` is supplied. |

If a report file is open in Excel the script writes a timestamped copy alongside it rather
than failing.

#### De-duplication

A turn is treated as a duplicate **only** when the same message was exported more than once —
matched on `CopilotConversationId` **plus** the prompt message's `SkypeItemId`.

Two threads can legitimately contain byte-identical prompt text: a user re-asking the same
question starts a new conversation, and the Copilot Chat UI can itself spawn a second thread
if the first is still streaming. Those are separate, individually reportable events. Matching
on topic + prompt text alone would silently delete real activity from the report.

---

### Phase 5: Review the Report

The CSV report contains the following columns:

| Column | Contents | Source field in the export |
|--------|----------|----------------------------|
| **Timestamp** | When the prompt was sent, in the timezone you specified | `CreatedDateTime` |
| **TimestampUtc** | Same instant in round-trip UTC, for sorting and joining | `CreatedDateTime` |
| **Actor** | Display name and address of the user who prompted Copilot | `RecipientsPreview.Sender` |
| **Conversation** | Topic name of the Copilot conversation | `ItemData.topic` / `Topic` |
| **ConversationId** | Thread identity — distinguishes two threads with identical prompts | `CopilotConversationId` |
| **PromptText** | Exact text of the prompt sent to Copilot | `ItemData.content` where `messageFrom` starts `8:orgid:` |
| **ResponseText** | Copilot's answer, all response messages joined | `ItemData.content` where `messageFrom` starts `28:` |
| **Attachments** | Files the user attached to the prompt | `copilotMetadata.messageAnnotations[]` type `LocalFile` |
| **WebSearchUsed** | Yes/No — whether Copilot issued any web search | derived |
| **WebSearchKeywords** | The literal terms sent to the search backend, `\|`-separated | `LinksBlob[]` entries `"@type":"WebSearchQuery"` |
| **CitationCount** | Number of distinct sources cited | `LinksBlob[]` entries `"@type":"CITATION"` |
| **CitationURLs** | The cited URLs | `LinksBlob[]` entries `"@type":"CITATION"` |
| **AppIdentity** | App identity from Copilot audit event | `AuditData.AppIdentity` |
| **AppHost** | Host shell from Copilot audit event | `AuditData.AppHost` |
| **CopilotEntrypoint** | Friendly label derived from `AppIdentity` + `AppHost` | derived |
| **SourceFile** | Transcript file the row came from, for spot-checking | filename |

**About WebSearchKeywords** — these are read from the `LinksBlob` property that Copilot writes
alongside each response, which records exactly what it sent to the search backend. They are
**not** inferred from the wording of the answer. Entries look like:

```json
{"@type":"WebSearchQuery","url":"queries=[\"site:pages.nist.gov 800-63B-4 MFA enterprise latest\"]","isCitedInResponse":true}
```

You will frequently see `site:` operators and multiple refinement queries per turn — that is
Copilot's real search behaviour, not a parsing artifact. Where Copilot answered from the model
or from an attached file without searching, `WebSearchUsed` is `No` and the keyword cell is
empty; that is a true negative, not missing data.

`LinksBlob` also records `bing.com/search?q=...` citation URLs containing the URL-encoded
query, which independently corroborates the keyword column.

**Key things to check**:
1. **Attachments**: the `Attachments` column names each file the user supplied
2. **Web searches**: `WebSearchUsed` = Yes, with the literal terms in `WebSearchKeywords`
3. **Citations**: review `CitationURLs` for external sources referenced by Copilot
4. **Prompt content**: scan `PromptText` for sensitive or personal data typed into the prompt
5. **Response content**: check `ResponseText` for policy violations or fabricated claims
6. **Coverage**: confirm every pilot user appears; a missing user is a scope fault (Phase 2a)

#### Entrypoint mapping legend (audit-enriched runs)

| AppIdentity | AppHost | CopilotEntrypoint meaning |
|---|---|---|
| `Copilot.M365Copilot.WebChat` | any | Copilot Chat web URL (`m365.cloud.microsoft/chat`) |
| `Copilot.M365Copilot.Bizchat` | `BizChat` | Microsoft 365 Copilot Chat / BizChat |
| `Copilot.M365Copilot.Bizchat` | `Office`, `M365App`, `OfficeCopilot*` | Microsoft 365 Copilot Chat in Microsoft 365 app / Office host |
| `Copilot.M365Copilot.Bizchat` | `Teams` | Copilot app in Teams |
| `Copilot.M365Copilot.Bizchat` | `Outlook` | Copilot in Outlook |
| `Copilot.M365Copilot.Bizchat` | `Bing`, `Edge` | Copilot Chat through Bing/Edge host |
| `Copilot.M365Copilot.Bizchat` | `Word` | Copilot in Word |
| `Copilot.M365Copilot.Bizchat` | `Excel` | Copilot in Excel |
| `Copilot.M365Copilot.Bizchat` | `PowerPoint` | Copilot in PowerPoint |
| anything else | anything else | Unknown (inspect raw AppIdentity/AppHost) |

Important: `Office` is not automatically Outlook. Treat `Office` / `M365App` as the Microsoft
365 app / Office host unless the audit payload explicitly says `Outlook`.


---

## Portability: Using This Script in Customer Tenants

This script is **tenant-agnostic** and requires **no authentication** — it only reads the pre-exported, pre-downloaded eDiscovery ZIP file.

### To use in a customer tenant:

1. **In the customer's tenant**:
   - Have an **eDiscovery Manager** follow **Phases 1–3** (create case, run search, export results)
   - Download and extract the export ZIP to a known folder

2. **On your machine** (or the customer's machine):
   - Copy the script: `Get-CopilotComplianceReport-ExportOnly.ps1`
   - Run it with the customer's export path:
     ```powershell
     .\Get-CopilotComplianceReport-ExportOnly.ps1 `
       -ExportPath "C:\CustomerExport\ExportExtracted" `
       -StartUtc ([datetime]'2026-09-04T00:00:00') `
       -EndUtc ([datetime]'2026-09-06T00:00:00') `
       -OutputFolder "C:\CustomerReports" `
       -TimeZoneId "Eastern Standard Time"
     ```
   - Share the resulting CSV with the customer's security/compliance team

### No tenant access required after export

The script **does not connect to Exchange Online, Purview, or any cloud services**. It only parses the downloaded HTML transcript files locally. This makes it safe to run offline, in air-gapped environments, or on customer-supplied machines.

---

## Troubleshooting

### A pilot user is missing from the report entirely
This is the highest-risk failure mode, because the export looks healthy.

1. Check which mailboxes are actually present:
   ```powershell
   Get-ChildItem "<ExportPath>\Exchange" -Directory | Select-Object Name
   ```
   Only mailboxes that returned items appear here.
2. If a pilot user is absent, re-run `Test-ComplianceSearchScope.ps1` against the exact
   identities used in the search. An identity that does not resolve contributes zero items
   to a Content Search **without raising an error**.
3. If the identity resolves correctly, the activity may not have been indexed when the search
   ran. Re-run the search and export.

### WebSearchKeywords is empty for a row
Expected whenever Copilot answered from the model or from an attached file. Confirm with the
`WebSearchUsed` column — `No` means no `WebSearchQuery` entry existed in that message's
`LinksBlob`, which is a true negative.

To verify against source, search the raw messages file for the turn:
```powershell
$raw = Get-Content .\CopilotChat-RawMessages.json -Raw | ConvertFrom-Json
$raw | Where-Object { $_.WebSearchQueries.Count -gt 0 } |
       Select-Object SourceFile, Role, @{n='Queries';e={$_.WebSearchQueries -join ' | '}}
```

### WebSearchKeywords looks like prose rather than search terms
That is the signature of an older build of this script, which regex-scraped the wording of the
answer. The current version reads `LinksBlob` → `"@type":"WebSearchQuery"` only. Confirm you
are on the current script by checking that the CSV has a `WebSearchUsed` column.

### Two rows look like duplicates
Compare their `ConversationId` values. Different ids means two genuinely separate threads that
happen to share prompt text — both are real events and both belong in the report. Identical
ids **and** identical timestamps would indicate a defect; report it.

### "TeamsMessagesData folder not found"
- The extracted export folder is missing the correct structure
- Verify you extracted the **entire ZIP** file (not just the Exchange folder)
- Check that the path `ExportPath\Exchange\*\TeamsMessagesData\` exists

### "Found 0 HTML transcript files"
- The search returned no Copilot Chat results
- Verify the search date range was correct
- Confirm Copilot Chat activity occurred during the window (check audit log manually if needed)
- Try widening the date range and re-running the search

### "Skipped N rendered-card file(s) with no per-message JSON"
Informational, not an error. Purview exports a rendered `Microsoft 365 Chat_N.html` copy of
some Adaptive Card answers. These carry no structured metadata, and the same answer is already
captured — with full metadata — from the correspondingly-named conversation file.

### "Timestamp parsing errors"
- Ensure the `-TimeZoneId` is valid (run `Get-TimeZone -ListAvailable` for a full list)
- Default is UTC if omitted

### Report file is locked
If a previous report is open in Excel the script warns and writes a timestamped copy beside
it. Close Excel and re-run to overwrite the canonical filename.

### CSV shows empty ResponseText for all rows
- The export may be in an older format (CSV manifest instead of HTML transcripts)
- This script **only** works with HTML transcript exports (the default in 2025+)
- If the export is a CSV file, contact Microsoft Support for format guidance

---

## Data Privacy & Compliance Notes

- **The exported HTML transcripts contain user-created prompts and Copilot responses in plain text.** Treat as sensitive/confidential.
- **The script reads from local files only** — no data is sent to any external service during report generation.
- **Archive the export ZIP and report CSV** according to your organization's data retention policy.
- **Consider labeling the CSV as "Confidential"** or applying an appropriate MIP sensitivity label before sharing.

---

## Script Parameters (Full Reference)

```
Get-CopilotComplianceReport-ExportOnly.ps1
  -ExportPath <string>              [Required] Path to extracted eDiscovery export
  -StartUtc <datetime>              [Optional] Audit window start (UTC)
                                    Default: 7 days ago
  -EndUtc <datetime>                [Optional] Audit window end (UTC)
                                    Default: now
  -OutputFolder <string>            [Optional] Report output folder
                                    Default: .\CopilotComplianceReport
  -TimeZoneId <string>              [Optional] Timezone for timestamps
                                    Default: UTC
                                    Examples: "Eastern Standard Time", "Pacific Standard Time"
```

---

## Example: Multi-Tenant Audit

To audit Copilot Chat across multiple customer tenants:

```powershell
$customers = @('Customer-A', 'Customer-B', 'Customer-C')
$startDate = [datetime]'2026-09-04'
$endDate = [datetime]'2026-09-06'

foreach ($customer in $customers) {
    $exportPath = "\\shared-drive\$customer\CopilotExports\CopilotChat_Extracted"
    $outputPath = "\\shared-drive\Reports\$customer-Report"
    
    .\Get-CopilotComplianceReport-ExportOnly.ps1 `
      -ExportPath $exportPath `
      -StartUtc $startDate -EndUtc $endDate `
      -OutputFolder $outputPath `
      -TimeZoneId "Eastern Standard Time"
    
    Write-Host "✓ Report generated: $outputPath\CopilotChat-ComplianceReport.csv"
}
```

---

## Next Steps

1. **Schedule regular audits** — run this script weekly or monthly to track compliance over time
2. **Build feedback loops** — share findings with users and Copilot administrators
3. **Refine pilot rules** — adjust Copilot Chat policies based on audit results
4. **Plan rollout** — once pilot audit is clean, expand Copilot Chat to broader user groups

---

**Questions?** Refer to:
- [Microsoft Purview eDiscovery documentation](https://learn.microsoft.com/en-us/purview/ediscovery)
- [Copilot Chat adoption guide](https://learn.microsoft.com/en-us/copilot/adoption)
- Script inline comments for detailed parsing logic

