# Copilot Chat Compliance Report v2

This folder is the clean, customer-ready **eDiscovery Standard** implementation. It deliberately
does not use any Premium-only capability.

## Contents

| File | Purpose |
|---|---|
| `RUNBOOK.md` | The admin-facing runbook: permissions, case, search, export, report, review |
| `Get-CopilotChatComplianceReport.ps1` | Generates the CSV, JSON, and HTML report from the export |
| `Test-ComplianceSearchScope.ps1` | Validates mailbox identities before creating the search |
| `Screenshots\` | Purview UI screenshots referenced by the runbook |

## What this solution reads

Standard eDiscovery exports Copilot Chat content as **PST files**. This script reads
those PSTs through Outlook COM and extracts the real prompt and response text.

Two inputs, only one of which is required:

| Input | Required | Purpose |
|---|---|---|
| `Exchange\*.pst` | Yes | Prompts, responses, attachments, timestamps, message class |
| `Items_*.csv` | No | Optional metadata enrichment only |

There is **no** `-AuditEventsPath` parameter in this script and no audit JSON is needed.

## Report columns

Emitted in this exact order to CSV, JSON, and HTML:

`Timestamp`, `TimestampUtc`, `Actor`, `Entrypoint`, `ItemClass`, `PromptLabel`, `Prompt`,
`Response`, `Attachments`, `GroundedFiles`, `WebSearchKeywords`, `Citations`, `SourcePst`,
`SourceFolder`.

`Attachments` holds only files the user uploaded. `GroundedFiles` holds tenant documents and mail
items Copilot referenced on its own. `Citations` holds external web URLs only; tenant links never
appear there.

## How the Entrypoint column is derived

Entrypoint comes directly from the Outlook `MessageClass` on each exported message,
so it requires no Unified Audit Log export:

| MessageClass in PST | Entrypoint shown |
|---|---|
| `IPM.SkypeTeams.Message.Copilot.BizChat` | Outlook/Teams BizChat |
| `IPM.SkypeTeams.Message.Copilot.WebChat` | Copilot Chat web |
| Any other Copilot class | Copilot Chat |

## Relationship to the legacy runbook

The older folder `C:\Scout_Output\CopilotChat-Compliance-Runbook` is **superseded**. It documented a
different script (`Get-CopilotComplianceReport-ExportOnly.ps1`) that took
`-AuditEventsPath "...\CopilotAuditEvents.json"` and instructed admins to use Premium-only HTML
transcript export. Ignore that guidance.

The corrected, customer-ready runbook is `RUNBOOK.md` in this folder.

## Run against a Standard export

1. Extract the Standard export so the folder contains the mailbox `.pst` files
   (typically under an `Exchange` subfolder). `Items_*.csv` may be present but is
   not required.
2. Close Outlook completely before running. The script starts its own Outlook COM
   session and logs on to MAPI.
3. Run:

```powershell
.\Get-CopilotChatComplianceReport.ps1 `
  -ExportPath 'C:\Path\To\ExtractedExport' `
  -OutputFolder 'C:\Path\To\Report' `
  -StartUtc ([datetime]'2026-09-06T00:00:00Z') `
  -EndUtc ([datetime]'2026-09-07T00:00:00Z') `
  -TimeZoneId 'Eastern Standard Time'
```

The script creates CSV, JSON, and HTML only when readable Copilot message bodies
are actually present. It never treats metadata-only CSV rows as prompt/response
content.

## Outlook COM behavior

The script uses the installed desktop Outlook application to read PST files.

- If `New-Object -ComObject Outlook.Application` returns `0x80080005`, fully exit
  Outlook, confirm no `OUTLOOK.EXE` process remains, and run again. Do not run
  PowerShell elevated if Outlook is not elevated (or vice versa).
- Progress is printed per PST and per item, so a stall is always visible.
- Report files are written **before** the PST stores are detached from the Outlook
  profile. If the final `Detaching PST stores...` step is slow, the CSV, JSON, and
  HTML are already complete on disk and Ctrl+C is safe.
- Stores left behind by an interrupted run are removed automatically at startup.

## Important boundary

The script creates output only when readable Copilot message bodies are present.
No script can reconstruct prompt or response text that is absent from the export.
