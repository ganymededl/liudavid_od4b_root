# Core Files Legend (Customer / Next Lab Tenant)

## Keep at root (required)

1. `RUNBOOK.md`  
   Step-by-step admin procedure (scope validation, eDiscovery search/export, report generation).
2. `Get-CopilotComplianceReport-ExportOnly.ps1`  
   Main parser/report generator (CSV + JSON + raw message JSON).
3. `Test-ComplianceSearchScope.ps1`  
   Pre-flight mailbox scope validator (prevents silent missing users in Content Search).
4. `README.md`  
   Quick start and output overview.

## Keep at root (reference)

5. `REPORT-ACCURACY-REVIEW.md`  
   Field-level explanation of what was fixed and why.

## Dedicated examples/output location

`Examples-Environment-Output\`

- `Current-Successful-Report\` → known-good outputs from this tenant
- `ExportExtracted-Sample\` → extracted Purview sample used for testing
- `Screenshots\` → runbook screenshots
- `Seed-and-Baseline-Data\` → seed indexes / baseline data
- `Attachments-Sample\` → sample attached files used in prompts
- `Legacy-Scripts\` → older helper scripts kept only as artifacts

## Deleted as non-applicable / obsolete

- superseded docs:
  - `Copilot-Chat-Compliance-Runbook.md`
  - `New-CopilotChatComplianceContentSearch-DOCUMENTATION.md`
  - `THIS-TENANT-SETUP-COMMANDS.md`
  - `COMPLETION-SUMMARY.md`
- troubleshooting / stale output folders:
  - `results\`
  - `report\`
  - `export-sample\`
- stale report artifacts:
  - old locked/incomplete `CopilotChat-ComplianceReport.csv` reference copy
  - run logs from troubleshooting in `ReportOutput\`
