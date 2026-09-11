# SUPERSEDED — do not use for customer delivery

This folder is retained only as historical evidence of the original build.

**Use instead:** `C:\Scout_Output\917tenantv2\`

- Runbook: `C:\Scout_Output\917tenantv2\RUNBOOK.md`
- Script:  `C:\Scout_Output\917tenantv2\Get-CopilotChatComplianceReport.ps1`

## Why this folder was superseded

`RUNBOOK.md` and `Get-CopilotComplianceReport-ExportOnly.ps1` in this folder contain guidance that
is incorrect for eDiscovery **Standard** customers:

| Issue | Detail |
|---|---|
| Premium-only export guidance | Phase 3 instructs "Export format: Native … .html transcripts". Conversation-level HTML transcript export is an **eDiscovery Premium** feature. Standard produces PST and Reports packages. |
| Unnecessary audit dependency | Phase 3b and the `-AuditEventsPath "…\CopilotAuditEvents.json"` parameter are not required. The Copilot entrypoint is stamped on each exported message as its `MessageClass`, and the v2 script reads it directly. |
| Non-existent inputs | Troubleshooting sections reference HTML transcript files and per-message JSON that a Standard export never produces. |
| Metadata-only output | The legacy script could emit rows whose prompt and response fields were empty because it fell back to the metadata CSV. The v2 script reads the PST bodies and fails explicitly rather than producing blank fields. |

## What was carried forward

The screenshots, the mailbox-scope validator (`Test-ComplianceSearchScope.ps1`), and the case,
search, and permission setup steps were reviewed, corrected, and moved into the v2 folder.
