# Copilot Chat Compliance Audit Solution

Complete, portable compliance audit solution for Copilot Chat usage. Captures prompts, responses, web-search keywords, attachments, citations, and (when audit payload is supplied) Copilot entrypoint fields for management review.

## 📋 What's Included

### Documentation
- **`RUNBOOK.md`** — Complete step-by-step admin guide (validating search scope, creating the eDiscovery case, running the content search, exporting, generating the report)
- **`REPORT-ACCURACY-REVIEW.md`** — Field-level reference for the export schema, the two defects found in the first pilot report, and how each was fixed

### Scripts
- **`Test-ComplianceSearchScope.ps1`** — Validates mailbox identities *before* a Content Search is created. Run this first.
- **`Get-CopilotComplianceReport-ExportOnly.ps1`** — Portable report generator (reads pre-exported eDiscovery HTML transcripts, no tenant authentication required)

### Sample Data
- **`ReportOutput/`** — Example output from this pilot: 13 conversation turns across 10 threads, with prompts, responses, real search terms, and citations
- **`ExportExtracted/`** — Real Purview eDiscovery export (23 HTML transcript files from this pilot)

---

## 🚀 Quick Start

### For your tenant:
1. Validate your mailbox scope — an unresolvable address silently returns zero items:
   ```powershell
   Connect-ExchangeOnline
   .\Test-ComplianceSearchScope.ps1 -Mailbox 'user1@contoso.com','user2@contoso.com'
   ```
2. Follow **RUNBOOK.md** to create an eDiscovery search and export, using the validated
   `-ExchangeLocation` string the validator prints
3. Extract the export ZIP to a local folder
4. Run the report:
   ```powershell
   .\Get-CopilotComplianceReport-ExportOnly.ps1 `
     -ExportPath "C:\Path\To\Export\Extracted" `
     -OutputFolder "C:\Reports" `
     -TimeZoneId "Eastern Standard Time"
   ```
5. Open the resulting CSV in Excel, or query the JSON for field-level detail

### For customer tenants:
- Have the customer complete steps 1–3 in RUNBOOK.md
- Customer provides the extracted export ZIP
- Run the script on your machine with the customer's export path
- **No cloud access required** — everything is offline

---

## ✅ What This Solution Provides

### Output files
Each run writes four files:

| File | Purpose |
|---|---|
| `CopilotChat-ComplianceReport.csv` | Flat, one row per turn, for reviewers |
| `CopilotChat-ComplianceReport.json` | Full fidelity per turn — untruncated responses, all keywords, citations with titles, plus a `FieldProvenance` map naming the source field behind every value |
| `CopilotChat-RawMessages.json` | One object per raw message (user and Copilot), for verifying the CSV against source |
| `CopilotChat-ComplianceReport.html` | Interactive reviewer report combining content-search transcript text with audit entrypoint fields |

### Report Columns
- **Timestamp / TimestampUtc** — When the prompt was sent, in your chosen timezone and in UTC
- **Actor** — User display name and address
- **Conversation / ConversationId** — Chat topic and its thread identity
- **PromptText** — Exact user prompt to Copilot
- **ResponseText** — Copilot's full answer
- **Attachments** — Files the user attached to the prompt
- **WebSearchUsed** — Yes/No
- **WebSearchKeywords** — The literal terms Copilot sent to the search backend
- **CitationCount / CitationURLs** — Sources Copilot cited
- **AppIdentity / AppHost / CopilotEntrypoint** — Entrypoint metadata from Copilot audit payload (when `-AuditEventsPath` is provided)
- **SourceFile** — Transcript file the row came from

### Features
✅ Extracts prompts and responses from HTML transcripts, including base64 Adaptive Card answers  
✅ Detects attached files by name  
✅ Reads web-search terms from the authoritative `LinksBlob` field — never inferred from the wording of the answer  
✅ Lists citations with source titles  
✅ De-duplicates on message identity only, so two threads sharing prompt text both survive  
✅ Emits JSON with per-field provenance for independent verification  
✅ Optionally enriches each turn with `AppIdentity` and `AppHost` from audit events, plus a friendly `CopilotEntrypoint` label  
✅ Correlates content-search transcript rows to audit payload rows by `ConversationId`, with `ThreadId` fallback for older flattened audit CSVs  
✅ No tenant authentication required (local export parsing only)  
✅ Portable across tenants (one script, any customer)  
✅ Timezone-aware timestamps (configurable)  

---

## 📊 Sample Report Preview

11 conversations audited over a 2-day window:

| Timestamp | Conversation | Actor | Prompt | Has Keywords | Has Citations |
|-----------|---------------|-------|--------|--------------|---|
| 2026-09-04 22:51 | Purchase Order vs Invoice | admin | Explain difference... | No | Yes (SharePoint) |
| 2026-09-04 22:52 | Latest NIST MFA Guidance | admin | Search the web and... | **Yes** | Yes |
| 2026-09-04 22:53 | Expense Policy Update | admin | Draft an announcement... | **Yes** | Yes |
| 2026-09-04 22:56 | Legal Risks in Agreement | admin | Review attached MSA... | No | Yes (Document) |
| 2026-09-05 03:00 | Azure Storage Security | admin | Summarize best practices | **Yes** | Yes |

---

## 🔧 Technical Details

### How It Works
1. **Export format**: Parses native Purview eDiscovery "individual messages" HTML transcripts
2. **JSON parsing**: Extracts metadata (timestamp, sender, topic) and content from embedded `<script type="application/json">` blocks
3. **Adaptive Card recovery**: Handles Copilot's base64-encoded response blocks (malformed JSON fallback)
4. **Turn assembly**: Groups user prompts with bot responses into logical conversation turns
5. **Deduplication**: Removes duplicate conversations exported under multiple filenames

### Architecture
```
eDiscovery Export (HTML transcripts)
         ↓
ConvertFrom-CopilotJsonBlock (parse JSON blocks per message)
         ↓
Import-CopilotChatHtmlExport (assemble turns, deduplicate)
         ↓
Split-CopilotBody (extract prompts, responses, keywords, citations)
         ↓
CSV Report (management review)
```

### Design Principles
- **Portable**: No cloud connections, works offline
- **Tenant-agnostic**: Same script works for any tenant's export
- **Lightweight**: Standalone PowerShell, no dependencies or modules
- **Observable**: Logs skipped/deduplicated items for transparency

---

## ⚠️ Limitations & Notes

### Export Format
- **Requires**: Native "individual messages" HTML transcript export (default in 2025+)
- **Not supported**: Older CSV-based exports
- This script **cannot** query the audit log directly; it reads pre-exported, pre-downloaded files only

### Coverage
- Captures Copilot Chat usage in Teams, Word, Excel, and the web
- Does NOT capture Copilot free/web-only usage (no audit log)
- Does NOT capture usage from other Copilot surface (Designer, Bing, etc.)

### Licensing
- Requires **eDiscovery Standard** (to create searches and export) in the customer's tenant
- This script requires **no license** (runs on your machine, reads downloaded files)

---

## 🔐 Privacy & Security

- **Local processing only**: No data sent to cloud during report generation
- **Offline-friendly**: Can run in air-gapped environments
- **Customer data**: The export ZIP contains user prompts and Copilot responses in plaintext — treat as confidential
- **Suggested**: Label the report CSV with MIP sensitivity label (Confidential) before sharing

---

## 📝 Using This in Production

### Recommended workflow for your organization:

1. **Create a pilot group** (5–15 Copilot Chat users)
2. **Run weekly audits** over the pilot group (use Purview content search with specific mailboxes)
3. **Review compliance** — check for data leaks, hallucinations, policy violations
4. **Refine Copilot Chat policies** based on audit findings
5. **Roll out to broader user base** once pilot audit is clean
6. **Continue periodic audits** (monthly or quarterly) to monitor compliance

### For audit trails:
- **Archive export ZIPs** per your data retention policy (e.g., 1 year)
- **Store reports** in a centralized compliance folder
- **Document policy changes** that resulted from audit findings

---

## 🤝 Portability Examples

### Same-tenant re-run (weekly audit):
```powershell
$searchName = "CopilotChat-Weekly-$(Get-Date -Format 'yyyy-MM-dd')"
# (Run search in Purview, export, extract)
.\Get-CopilotComplianceReport-ExportOnly.ps1 `
  -ExportPath "$searchName-Extracted" `
  -OutputFolder ".\Reports\$searchName"
```

### Multi-tenant audit loop:
```powershell
$customers = @('ACME-Corp', 'TechStartup-Inc', 'GlobalBank-Ltd')
foreach ($cust in $customers) {
    $export = "\\audit-share\$cust\CopilotChat-Export-$(Get-Date -Format 'yyyy-MM')"
    .\Get-CopilotComplianceReport-ExportOnly.ps1 `
      -ExportPath "$export-Extracted" `
      -OutputFolder "\\audit-share\Reports\$cust"
}
```

### Send to customer (hands-off):
1. Provide customer with the script and `RUNBOOK.md`
2. Customer runs search, exports, and sends you the ZIP
3. You extract it locally and run the script
4. Send customer the CSV report
5. **No customer involvement required** after export download

---

## 📚 Related Resources

- [Microsoft Purview eDiscovery documentation](https://learn.microsoft.com/en-us/purview/ediscovery)
- [Copilot Chat adoption and compliance](https://learn.microsoft.com/en-us/copilot/adoption)
- [Copilot Chat configuration](https://learn.microsoft.com/en-us/microsoft-copilot/enterprise/manage-copilot-deployments)

---

## 📞 Support

**Script not working?**
- Check `RUNBOOK.md` troubleshooting section
- Verify the export folder contains `Exchange/*/TeamsMessagesData/*.html` files
- Confirm PowerShell version 5.1 or higher (`$PSVersionTable.PSVersion`)

**Need to audit multiple dates/users?**
- Run the Purview search with different date ranges
- Run the script with different `-StartUtc` / `-EndUtc` parameters
- Export path can stay the same; script filters by date

**Want to customize the report?**
- The script outputs a standard CSV; use Excel/PowerBI for further analysis
- To add columns, modify the `Export-Csv` section in the script

---

## 📄 License & Attribution

This solution was created as a portable, reusable compliance audit tool. 

**Use freely** across your organization and with customers.

---

## Checklist: Before First Use

- [ ] Read `RUNBOOK.md` (10 min)
- [ ] Confirm your tenant has eDiscovery Standard enabled
- [ ] Create a test eDiscovery case and search
- [ ] Export and extract the results locally
- [ ] Run the script once with the extracted export path
- [ ] Verify the CSV output contains prompt/response/keyword data
- [ ] Review the sample report in `ReportOutput/`

Once validated, you're ready to:
- [ ] Set up regular weekly/monthly audit runs
- [ ] Deploy to customer tenants (via portable script + runbook)
- [ ] Archive reports and exports per retention policy

---

**Last Updated**: 2026-09-06  
**Status**: Production-ready (export-only variant)
