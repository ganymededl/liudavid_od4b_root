<#
.SYNOPSIS
    Runbook Phases 1-3 as PowerShell: create a dedicated eDiscovery case, create and run a
    Copilot-scoped Content Search inside it, then start the native/individual-messages export.

.DESCRIPTION
    This is the scripted equivalent of RUNBOOK.md Phase 1 (create case), Phase 2 (validate
    scope + create/run search with the Copilot item-class query), and Phase 3 (export). It
    exists so the same case/search/export can be reproduced identically in any customer
    tenant via Security & Compliance PowerShell instead of manual Purview GUI clicks.

    It deliberately does NOT reuse the tenant's built-in "Content Search" case, and it
    deliberately does NOT allow an empty content match query - both of those were the root
    causes of an invalid run in the field (see 917-tenant-run-notes.md, 2026-09-07).

    Requires an existing Security & Compliance PowerShell session:
        Connect-IPPSSession
        Connect-ExchangeOnline   (only needed if you also want Test-ComplianceSearchScope.ps1
                                   run against Get-Recipient first)

.PARAMETER CaseName
    Name of the new eDiscovery (Standard) case. Runbook convention:
    Copilot-Chat-Pilot-Audit-[date], e.g. Copilot-Chat-Pilot-Audit-2026-09-06

.PARAMETER SearchName
    Name of the Content Search inside the case. Runbook convention:
    CopilotChat-[date-range], e.g. CopilotChat-2026-09-04-to-2026-09-06

.PARAMETER Mailbox
    One or more validated mailbox UPNs/SMTP addresses to scope the search to. Run
    Test-ComplianceSearchScope.ps1 first and pass its resolved output here - do not pass
    unvalidated identities.

.PARAMETER StartDate
    Start of the audit window (local date/time, will be sent as-is to -ExchangeLocation's
    date filter conditions).

.PARAMETER EndDate
    End of the audit window.

.PARAMETER ContentMatchQuery
    KQL condition for the search. Defaults to the runbook-mandated Copilot query. Override
    only if you have a documented reason - an empty/blank query is what caused the invalid
    917-tenant run and must never be passed here.

.PARAMETER SkipExport
    Create and run the search but do not start the export action. Useful if you want to
    review Statistics first before committing to an export.

.PARAMETER ExportOutputFolder
    Where to write a small JSON record of the case/search/export names + ids for later
    reference. Defaults to .\eDiscoveryRunMetadata.

.EXAMPLE
    Connect-IPPSSession
    Connect-ExchangeOnline
    $scope = .\Test-ComplianceSearchScope.ps1 -Mailbox LisaT@contoso.onmicrosoft.com,AmberR@contoso.onmicrosoft.com,WillB@contoso.onmicrosoft.com
    .\New-CopilotComplianceCaseAndSearch.ps1 `
        -CaseName 'Copilot-Chat-Pilot-Audit-2026-09-06' `
        -SearchName 'CopilotChat-2026-09-04-to-2026-09-06' `
        -Mailbox ($scope -split ',') `
        -StartDate '2026-09-04' -EndDate '2026-09-07'
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]   $CaseName,
    [Parameter(Mandatory)] [string]   $SearchName,
    [Parameter(Mandatory)] [string[]] $Mailbox,
    [Parameter(Mandatory)] [datetime] $StartDate,
    [Parameter(Mandatory)] [datetime] $EndDate,
    [string] $ContentMatchQuery = 'RecordType:TeamsConversation OR ItemClass:IPM.SkypeTeams.Message.Copilot*',
    [switch] $SkipExport,
    [string] $ExportOutputFolder = '.\eDiscoveryRunMetadata'
)

$ErrorActionPreference = 'Stop'

# --- Guardrails that encode the two root causes from the 917-tenant failure ---
if ([string]::IsNullOrWhiteSpace($ContentMatchQuery)) {
    Write-Error 'ContentMatchQuery is blank. RUNBOOK.md Phase 2b requires a Copilot-scoped ' +
                'KQL condition - an empty query returns unrelated mailbox content and looks ' +
                'like a healthy export. Refusing to continue.'
}
if ($CaseName -ieq 'Content Search') {
    Write-Error 'Refusing to use the built-in "Content Search" case. RUNBOOK.md Phase 1 ' +
                'requires creating a dedicated case (e.g. Copilot-Chat-Pilot-Audit-<date>) ' +
                'so searches/exports for this audit are isolated and traceable.'
}
if (-not (Get-Command New-ComplianceCase -ErrorAction SilentlyContinue)) {
    Write-Error 'New-ComplianceCase is unavailable. Run Connect-IPPSSession first.'
}

$Mailbox = @($Mailbox | Where-Object { $_ } | Select-Object -Unique)
if ($Mailbox.Count -eq 0) { Write-Error 'Supply at least one validated mailbox via -Mailbox.' }

Write-Host ''
Write-Host '=== Phase 1: Create dedicated eDiscovery case ===' -ForegroundColor Cyan
$existingCase = Get-ComplianceCase -Identity $CaseName -ErrorAction SilentlyContinue
if ($existingCase) {
    Write-Host "Case '$CaseName' already exists (Status=$($existingCase.Status)) - reusing it." -ForegroundColor Yellow
} else {
    $existingCase = New-ComplianceCase -Name $CaseName -CaseType eDiscovery
    Write-Host "Created case '$CaseName' (Identity=$($existingCase.Identity))." -ForegroundColor Green
}

Write-Host ''
Write-Host '=== Phase 2: Create and run the Copilot-scoped Content Search ===' -ForegroundColor Cyan
Write-Host "Case:               $CaseName"
Write-Host "Search name:        $SearchName"
Write-Host "Mailboxes:          $($Mailbox -join ', ')"
Write-Host "Date window:        $StartDate  to  $EndDate"
Write-Host "ContentMatchQuery:  $ContentMatchQuery"
Write-Host ''

$dateQuery = "(Sent>=$($StartDate.ToString('MM/dd/yyyy')) AND Sent<=$($EndDate.ToString('MM/dd/yyyy')))"
$fullQuery = "$ContentMatchQuery AND $dateQuery"

$existingSearch = Get-ComplianceSearch -Identity $SearchName -ErrorAction SilentlyContinue
if ($existingSearch) {
    Write-Host "Search '$SearchName' already exists - removing it first so it can be recreated cleanly." -ForegroundColor Yellow
    Remove-ComplianceSearch -Identity $SearchName -Confirm:$false
}

$search = New-ComplianceSearch `
    -Name $SearchName `
    -Case $CaseName `
    -ExchangeLocation $Mailbox `
    -ContentMatchQuery $fullQuery

Write-Host "Created search '$SearchName'. Starting it..." -ForegroundColor Green
Start-ComplianceSearch -Identity $SearchName

Write-Host 'Polling for completion (this typically takes 5-30 minutes)...' -ForegroundColor Yellow
do {
    Start-Sleep -Seconds 20
    $status = Get-ComplianceSearch -Identity $SearchName
    Write-Host "  Status=$($status.Status)  Items=$($status.Items)  Size=$($status.Size)"
} while ($status.Status -notin @('Completed', 'CompletedWithErrors', 'Failed'))

if ($status.Status -eq 'Failed') {
    Write-Error "Search '$SearchName' failed. Inspect Get-ComplianceSearch -Identity '$SearchName' | fl * for details."
}

Write-Host ''
Write-Host "Search completed: Status=$($status.Status)  Items=$($status.Items)  Size=$($status.Size)" -ForegroundColor Green
if ($status.Items -eq 0) {
    Write-Host 'WARNING: 0 items returned. Per RUNBOOK.md Phase 2c, treat this as a scope/timing' -ForegroundColor Red
    Write-Host 'fault (unresolved mailbox identity, or search run before indexing completed) -' -ForegroundColor Red
    Write-Host 'NOT as evidence the users were inactive. Re-check Test-ComplianceSearchScope.ps1' -ForegroundColor Red
    Write-Host 'output and the date window before exporting.' -ForegroundColor Red
}

$exportAction = $null
if (-not $SkipExport) {
    Write-Host ''
    Write-Host '=== Phase 3: Export native/individual-messages results ===' -ForegroundColor Cyan
    $exportName = "$SearchName-Export"
    $existingExport = Get-ComplianceSearchAction -Identity "${SearchName}_Export" -ErrorAction SilentlyContinue
    if ($existingExport) {
        Write-Host "Export action for '$SearchName' already exists - removing it first." -ForegroundColor Yellow
        Remove-ComplianceSearchAction -Identity "${SearchName}_Export" -Confirm:$false
    }

    $exportAction = New-ComplianceSearchAction -SearchName $SearchName -Export `
        -Format FxStream `
        -ExchangeArchiveFormat PerUserPst `
        -EnableDedupe $false `
        -Scope IndexedItemsOnly

    Write-Host "Started export action '$($exportAction.Name)'. Polling for completion..." -ForegroundColor Green
    do {
        Start-Sleep -Seconds 20
        $expStatus = Get-ComplianceSearchAction -Identity $exportAction.Name
        Write-Host "  Status=$($expStatus.Status)"
    } while ($expStatus.Status -notin @('Completed', 'CompletedWithErrors', 'Failed'))

    if ($expStatus.Status -eq 'Failed') {
        Write-Error "Export action '$($exportAction.Name)' failed. Inspect it via Get-ComplianceSearchAction -Identity '$($exportAction.Name)' -Details | fl *."
    }
    Write-Host "Export completed: Status=$($expStatus.Status)" -ForegroundColor Green
    Write-Host 'Next: open Purview > eDiscovery > Standard > <case> > Searches > <search> > Export,' -ForegroundColor Cyan
    Write-Host 'and download the results package (this still requires the Purview UI / signed blob URL).' -ForegroundColor Cyan
}

if (-not (Test-Path $ExportOutputFolder)) { New-Item -ItemType Directory -Path $ExportOutputFolder -Force | Out-Null }
$metadata = [pscustomobject]@{
    CaseName          = $CaseName
    SearchName        = $SearchName
    Mailboxes         = $Mailbox
    StartDate         = $StartDate
    EndDate           = $EndDate
    ContentMatchQuery = $fullQuery
    SearchStatus      = $status.Status
    SearchItems       = $status.Items
    SearchSize        = $status.Size
    ExportActionName  = $exportAction.Name
    GeneratedUtc      = (Get-Date).ToUniversalTime()
}
$metaPath = Join-Path $ExportOutputFolder "$SearchName-metadata.json"
$metadata | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $metaPath
Write-Host ''
Write-Host "Run metadata written to $metaPath" -ForegroundColor Green
