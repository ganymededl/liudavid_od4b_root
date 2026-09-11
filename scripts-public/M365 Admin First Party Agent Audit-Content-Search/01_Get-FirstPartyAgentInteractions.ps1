<#
.SYNOPSIS
    Retrieves the PROMPT and the AGENT RESPONSE text for Microsoft first-party Copilot agent
    interactions (for example the Microsoft 365 Admin agent) from the user's Exchange Online mailbox.

.DESCRIPTION
    WHY THIS EXISTS

    First-party Microsoft 365 Copilot agents do NOT write to the Dataverse conversationtranscript
    table - Microsoft documents that transcripts are not written for "Microsoft 365 Copilot agents".
    So the Dataverse export used for custom Copilot Studio agents cannot reach them.

    Purview DSPM > Activity explorer > AI activities DOES surface these interactions and DOES render
    the user's prompt, but its detail pane has a "Prompt" field and NO "Response" field at all. The
    agent's answer is captured - the agent-attributed row is classified for sensitive info types,
    which is only possible if Purview has the response body - but the UI never renders it.

    The Microsoft Graph Copilot Export API
    (/copilot/users/{id}/interactionHistory/getAllEnterpriseInteractions) does return both, but it is
    APPLICATION-PERMISSION ONLY. A delegated / device-code sign-in fails with AADSTS650053 because
    AiEnterpriseInteraction.Read.All does not exist as a delegated scope. That path therefore requires
    an app registration plus admin consent.

    This script uses the third documented path, which needs no app registration: Microsoft states
    "All user prompts and responses from AI applications are stored in a user's mailbox" and
    "Each Microsoft 365 Copilot interaction is stored in the user's Exchange Online mailbox as an
    individual message-class item." The prompt and the response are SEPARATE items - the response has
    the Copilot / agent identity in the From field.

.PARAMETER UserUpn
    The mailbox to search. This must be the INTERACTING user - the person who talked to the agent -
    not the administrator running the search.

.PARAMETER Days
    How many days back to search. Defaults to 1.

.PARAMETER SearchName
    Optional explicit compliance search name. One is generated if omitted.

.PARAMETER KeywordFilter
    Optional extra KQL AND-ed onto the item class filter, for example a distinctive phrase from the
    conversation you are trying to locate.

.PARAMETER Preview
    Run a Preview action after the search and list the matching items with sender, recipient, date
    and subject. This is what identifies which items are prompts and which are responses.

.PARAMETER PurgeSearch
    Remove the compliance search object when finished, so the tenant is left clean.

.PARAMETER ReplaceExisting
    If a compliance search with the same name already exists, remove it and recreate it. Without
    this, re-running with the same -SearchName fails because compliance search names must be unique
    in the organization.

.PARAMETER Export
    Start an export action for the search so the message bodies can be downloaded with the
    eDiscovery Export Tool. Prints the exact follow-on command for Get-FirstPartyAgentReport.ps1,
    which turns the extracted export into a readable HTML conversation report.

.PARAMETER DisableWam
    Force Connect-IPPSSession -DisableWAM. The script already retries with this automatically after
    an MSAL broker assembly conflict; this switch skips straight to it.

.EXAMPLE
    .\Get-FirstPartyAgentInteractions.ps1 -UserUpn admin@contoso.onmicrosoft.com -Days 1 -Preview

.NOTES
    Requires: ExchangeOnlineManagement module, and the eDiscovery Manager role group (or equivalent)
    in Microsoft Purview. A compliance search is metadata-only until you Preview or Export.

    This creates a COMPLIANCE SEARCH in the tenant. Use -PurgeSearch to remove it afterwards, or
    -WhatIf to see what would run without creating anything.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [string] $UserUpn,

    [Parameter(Mandatory = $false)]
    [int] $Days = 1,

    [Parameter(Mandatory = $false)]
    [string] $SearchName,

    [Parameter(Mandatory = $false)]
    [string] $KeywordFilter,

    [Parameter(Mandatory = $false)]
    [switch] $Preview,

    [Parameter(Mandatory = $false)]
    [switch] $PurgeSearch,

    [Parameter(Mandatory = $false)]
    [switch] $ReplaceExisting,

    [Parameter(Mandatory = $false)]
    [switch] $Export,

    [Parameter(Mandatory = $false)]
    [switch] $DisableWam,

    [Parameter(Mandatory = $false)]
    [string] $OutputFolder = 'C:\Scout_Output\FirstParty-Agent-Audit',

    [Parameter(Mandatory = $false)]
    [int] $TimeoutMinutes = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string] $Message,
        [Parameter(Mandatory = $false)][ValidateSet('INFO','OK','WARN','ERROR','STEP')][string] $Level = 'INFO'
    )
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'), $Level, $Message
    switch ($Level) {
        'OK'    { Write-Host $line -ForegroundColor Green }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'STEP'  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line -ForegroundColor Gray }
    }
}

function Connect-Purview {
    <#
        Same broker-conflict handling as Test-CopilotAuditReadiness.ps1. An older
        Microsoft.Identity.Client.dll loaded by another module makes the WAM broker path throw
        "Method not found ... WithBroker". -DisableWAM avoids the broker entirely.
    #>
    param([switch] $ForceNoWam)

    $available = @(Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object -Property Version -Descending)
    if ($available.Count -eq 0) {
        Write-Log -Level 'ERROR' -Message 'ExchangeOnlineManagement is not installed. Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force'
        return $false
    }

    # Pick by MSAL ASSEMBLY CONSISTENCY and a minimum version, not by version number alone.
    #
    # Two independent constraints collide here:
    #
    # 1. Some releases ship a Microsoft.Identity.Client.Broker.dll built against a DIFFERENT
    #    Microsoft.Identity.Client.dll than the one in the same folder. The broker then calls a
    #    WithBroker(...) overload that is not present in the MSAL assembly actually loaded, and
    #    every connect attempt dies with "Method not found ... BrokerExtension.WithBroker".
    #    Observed: 3.9.2 ships Client 4.74.1.0 with Broker 4.68.0.0 (mismatched, broken).
    #    -DisableWAM does NOT rescue this - the broker assembly binds at import time.
    #
    # 2. Compliance search creation now requires Connect-IPPSSession -EnableSearchOnlySession,
    #    which only exists in 3.9.0 and later. Older modules connect happily and then fail at
    #    New-ComplianceSearch with "Please close the current PowerShell session and open a new
    #    session using Connect-IPPSSession with the -EnableSearchOnlySession flag".
    #    Observed: 3.7.1 has consistent assemblies but is too old to run a search.
    #
    # So the module must be BOTH assembly-consistent AND >= 3.9.0. In practice that means 3.9.0
    # (Client 4.68.0.0 / Broker 4.68.0.0 - consistent), which is what this selection finds.
    $minVersion = [version]'3.9.0'
    $ranked = New-Object System.Collections.Generic.List[object]
    foreach ($m in $available) {
        $client = Get-ChildItem -Path $m.ModuleBase -Recurse -Filter 'Microsoft.Identity.Client.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
        $broker = Get-ChildItem -Path $m.ModuleBase -Recurse -Filter 'Microsoft.Identity.Client.Broker.dll' -ErrorAction SilentlyContinue | Select-Object -First 1

        $cv = if ($client) { [string]$client.VersionInfo.FileVersion } else { '' }
        $bv = if ($broker) { [string]$broker.VersionInfo.FileVersion } else { '' }

        # No broker assembly at all is fine - there is nothing to mismatch.
        $consistent = ([string]::IsNullOrWhiteSpace($bv)) -or ($cv -eq $bv)

        $ranked.Add([pscustomobject]@{
            Module      = $m
            Version     = $m.Version
            ClientAsm   = $cv
            BrokerAsm   = $bv
            Consistent  = $consistent
            VersionOk   = ($m.Version -ge $minVersion)
        }) | Out-Null
    }

    $good = @($ranked | Where-Object { $_.Consistent -and $_.VersionOk } | Sort-Object -Property Version -Descending)

    foreach ($b in @($ranked | Where-Object { -not $_.Consistent })) {
        Write-Log -Level 'WARN' -Message ("ExchangeOnlineManagement {0} has MISMATCHED MSAL assemblies (Client {1} vs Broker {2}). Skipping - this combination throws 'Method not found ... WithBroker'." -f $b.Version, $b.ClientAsm, $b.BrokerAsm)
    }
    foreach ($b in @($ranked | Where-Object { $_.Consistent -and -not $_.VersionOk })) {
        Write-Log -Level 'WARN' -Message ("ExchangeOnlineManagement {0} is older than {1}. Skipping - it cannot create compliance searches because it lacks -EnableSearchOnlySession." -f $b.Version, $minVersion)
    }

    if ($good.Count -eq 0) {
        Write-Log -Level 'ERROR' -Message 'No installed ExchangeOnlineManagement version is both >= 3.9.0 AND free of the MSAL assembly mismatch.'
        Write-Log -Message '  Fix with:  Install-Module ExchangeOnlineManagement -RequiredVersion 3.9.0 -Scope CurrentUser -Force -AllowClobber'
        Write-Log -Message '  3.9.0 ships Client 4.68.0.0 with Broker 4.68.0.0 (consistent) and supports -EnableSearchOnlySession.'
        Write-Log -Message '  Alternatively use the Purview portal procedure - it has no module dependency at all.'
        return $false
    }

    $mod = $good[0].Module
    Remove-Module ExchangeOnlineManagement -Force -ErrorAction SilentlyContinue
    Import-Module $mod.Path -Force -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    Write-Log -Level 'OK' -Message ("Using ExchangeOnlineManagement {0} (MSAL Client {1} / Broker {2} - consistent, supports -EnableSearchOnlySession)." -f $good[0].Version, $good[0].ClientAsm, $(if ([string]::IsNullOrWhiteSpace($good[0].BrokerAsm)) { 'none' } else { $good[0].BrokerAsm }))

    # Already connected?
    try {
        Get-ComplianceSearch -ResultSize 1 -ErrorAction Stop | Out-Null
        Write-Log -Level 'OK' -Message 'Reusing the existing Security and Compliance PowerShell session.'
        return $true
    }
    catch { }

    $supportsNoWam = $false
    $supportsSearchOnly = $false
    try {
        $p = (Get-Command Connect-IPPSSession -ErrorAction Stop).Parameters
        $supportsNoWam      = $p.ContainsKey('DisableWAM')
        $supportsSearchOnly = $p.ContainsKey('EnableSearchOnlySession')
    } catch { }

    if (-not $supportsSearchOnly) {
        Write-Log -Level 'WARN' -Message 'This module build has no -EnableSearchOnlySession parameter. Compliance search creation will fail. Install ExchangeOnlineManagement 3.9.0.'
    }

    # -EnableSearchOnlySession is REQUIRED to create compliance searches. Without it the connect
    # succeeds and then New-ComplianceSearch fails with "Please close the current PowerShell session
    # and open a new session using Connect-IPPSSession with the -EnableSearchOnlySession flag",
    # often accompanied by AADSTS500011 for https://cpfdwebservicecloudapp.net - which is a WRONG
    # TOKEN AUDIENCE, not a missing tenant app. Try it first, then degrade.
    $attempts = New-Object System.Collections.Generic.List[object]
    if ($supportsSearchOnly -and -not $ForceNoWam) {
        $attempts.Add(@{ EnableSearchOnlySession = $true }) | Out-Null
    }
    if ($supportsSearchOnly -and $supportsNoWam) {
        $attempts.Add(@{ EnableSearchOnlySession = $true; DisableWAM = $true }) | Out-Null
    }
    if (-not $ForceNoWam) { $attempts.Add(@{}) | Out-Null }
    if ($supportsNoWam)   { $attempts.Add(@{ DisableWAM = $true }) | Out-Null }
    if ($attempts.Count -eq 0) { $attempts.Add(@{}) | Out-Null }

    foreach ($splat in $attempts) {
        try {
            $bits = @()
            if ($splat.ContainsKey('EnableSearchOnlySession')) { $bits += '-EnableSearchOnlySession' }
            if ($splat.ContainsKey('DisableWAM'))              { $bits += '-DisableWAM' }
            $label = if ($bits.Count -gt 0) { $bits -join ' ' } else { 'standard sign-in' }

            Write-Log -Level 'STEP' -Message ("Connecting to Security and Compliance PowerShell - {0}. A sign-in prompt is expected." -f $label)
            $s = $splat.Clone()
            $s['ErrorAction'] = 'Stop'; $s['WarningAction'] = 'SilentlyContinue'; $s['ShowBanner'] = $false
            Connect-IPPSSession @s | Out-Null
            Get-ComplianceSearch -ResultSize 1 -ErrorAction Stop | Out-Null
            Write-Log -Level 'OK' -Message ("Connected ({0})." -f $label)
            $script:ConnectedSearchOnly = $splat.ContainsKey('EnableSearchOnlySession')
            return $true
        }
        catch {
            $m = $_.Exception.Message
            if (($m -match 'WithBroker' -or $m -match 'Method not found' -or $m -match 'Microsoft\.Identity\.Client') -and -not $splat.ContainsKey('DisableWAM')) {
                Write-Log -Level 'WARN' -Message 'MSAL broker (WAM) assembly conflict. Trying the next connect variant ...'
                continue
            }
            if ($m -match 'parameter cannot be found|IsRpsSession') {
                Write-Log -Level 'WARN' -Message 'Module plumbing mismatch on this variant. Trying the next connect variant ...'
                continue
            }
            Write-Log -Level 'ERROR' -Message ("Connect failed: {0}" -f $m)
            return $false
        }
    }
    return $false
}

Write-Host ''
Write-Host '  ===================================================================' -ForegroundColor Cyan
Write-Host '   FIRST-PARTY COPILOT AGENT INTERACTIONS - MAILBOX RETRIEVAL' -ForegroundColor Cyan
Write-Host '  ===================================================================' -ForegroundColor Cyan
Write-Host '   Retrieves BOTH the user prompt and the agent RESPONSE, which' -ForegroundColor White
Write-Host '   Purview DSPM Activity explorer does not render.' -ForegroundColor Gray
Write-Host '  ===================================================================' -ForegroundColor Cyan
Write-Host ''

if (-not (Connect-Purview -ForceNoWam:$DisableWam)) { return }

$startDate = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString('yyyy-MM-dd')
$endDate   = (Get-Date).ToUniversalTime().AddDays(1).ToString('yyyy-MM-dd')

# KQL that is VERIFIED to work against a real tenant. Three details matter and all three were
# found the hard way:
#   1. ItemClass:IPM.SkypeTeams.Message.Copilot*  - NOT "Copilot.*". A dot immediately before the
#      wildcard is rejected by the KQL parser as "an unexpected character in the query".
#   2. Dates must be ISO yyyy-MM-dd. US-style MM/dd/yyyy is also rejected as an unexpected
#      character, because the slashes are not valid in a KQL date literal.
#   3. Use Sent>= / Sent<= rather than received>= / received<. The mailbox items are stored with a
#      Sent timestamp; the inclusive <= form matches the Purview portal's own condition builder.
# Microsoft documents that every Copilot / AI application interaction is stored in the interacting
# user's mailbox as an individual message-class item under the IPM.SkypeTeams.Message.Copilot
# family. The wildcard covers first-party agents as well as plain Copilot chat.
$kql = "ItemClass:IPM.SkypeTeams.Message.Copilot* AND (Sent>=$startDate AND Sent<=$endDate)"
if (-not [string]::IsNullOrWhiteSpace($KeywordFilter)) {
    $kql = "{0} AND ({1})" -f $kql, $KeywordFilter
}

if ([string]::IsNullOrWhiteSpace($SearchName)) {
    $SearchName = "FirstPartyAgent-{0}-{1}" -f ($UserUpn -split '@')[0], (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
}

Write-Log -Message ("Mailbox : {0}" -f $UserUpn)
Write-Log -Message ("Window  : last {0} day(s)" -f $Days)
Write-Log -Message ("KQL     : {0}" -f $kql)
Write-Log -Message ("Search  : {0}" -f $SearchName)

if (-not $PSCmdlet.ShouldProcess($SearchName, 'Create and run a compliance search')) { return }

# Re-running the same named search is a normal admin workflow, so make it work rather than fail.
if ($ReplaceExisting) {
    $existing = Get-ComplianceSearch -Identity $SearchName -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        Write-Log -Level 'WARN' -Message ("A search named '{0}' already exists. Removing it first (-ReplaceExisting)." -f $SearchName)
        try {
            Get-ComplianceSearchAction -ErrorAction SilentlyContinue |
                Where-Object { $_.SearchName -eq $SearchName } |
                ForEach-Object { Remove-ComplianceSearchAction -Identity $_.Name -Confirm:$false -ErrorAction SilentlyContinue }
            Remove-ComplianceSearch -Identity $SearchName -Confirm:$false -ErrorAction Stop
            Write-Log -Level 'OK' -Message 'Existing search removed.'
        }
        catch {
            Write-Log -Level 'ERROR' -Message ("Could not remove the existing search: {0}" -f $_.Exception.Message)
            return
        }
    }
}

try {
    New-ComplianceSearch -Name $SearchName -ExchangeLocation $UserUpn -ContentMatchQuery $kql -ErrorAction Stop | Out-Null
    Write-Log -Level 'OK' -Message 'Compliance search created.'
    Start-ComplianceSearch -Identity $SearchName -ErrorAction Stop | Out-Null
    Write-Log -Level 'STEP' -Message 'Search started. Waiting for completion ...'
}
catch {
    $msg = $_.Exception.Message
    Write-Log -Level 'ERROR' -Message ("Could not create or start the search: {0}" -f $msg)

    # Report the cause that actually matches the error. Order matters: the search-only-session
    # message contains the phrase "was not found in the tenant", which would otherwise be
    # misattributed to a bad mailbox address. Check the specific cases first.
    if ($msg -match 'EnableSearchOnlySession|cpfdwebservicecloudapp|AADSTS500011') {
        Write-Log -Level 'WARN' -Message 'The session is not a SEARCH-ONLY session, so the token has the wrong audience for the compliance search backend.'
        Write-Log -Message '  This is NOT a missing tenant app and NOT a bad mailbox address, despite what the'
        Write-Log -Message '  AADSTS500011 text implies. Fix it by reconnecting in a FRESH PowerShell window:'
        Write-Log -Message ''
        Write-Log -Message '    Install-Module ExchangeOnlineManagement -RequiredVersion 3.9.0 -Scope CurrentUser -Force -AllowClobber'
        Write-Log -Message '    Connect-IPPSSession -EnableSearchOnlySession'
        Write-Log -Message ''
        Write-Log -Message '  Then re-run this script in that same window. A session created WITHOUT the flag'
        Write-Log -Message '  cannot be upgraded in place - the window must be new.'
    }
    elseif ($msg -match 'unexpected character|query of the search is invalid|invalid.*query') {
        Write-Log -Level 'WARN' -Message 'The KQL was rejected by the parser, not by permissions.'
        Write-Log -Message '  Common causes: a dot before the wildcard (use Copilot* not Copilot.*),'
        Write-Log -Message '  US-style MM/dd/yyyy dates (use ISO yyyy-MM-dd), or an unbalanced quote'
        Write-Log -Message '  or bracket in -KeywordFilter. The query used was logged above.'
    }
    elseif ($msg -match 'already exists') {
        Write-Log -Level 'WARN' -Message ("A compliance search named '{0}' already exists. Pass -ReplaceExisting, use a different -SearchName, or remove it in Purview > eDiscovery > Content Search." -f $SearchName)
    }
    elseif ($msg -match 'access|denied|permission|unauthorized|role group') {
        Write-Log -Level 'WARN' -Message 'Access denied. The signed-in identity is most likely not a member of the eDiscovery Manager role group in Microsoft Purview.'
    }
    elseif ($msg -match "mailbox.*(not found|does not exist|couldn't be found)") {
        Write-Log -Level 'WARN' -Message ("The mailbox '{0}' could not be resolved. Check the UPN and that the mailbox exists in this tenant." -f $UserUpn)
    }
    else {
        Write-Log -Message 'If this is an access error, confirm eDiscovery Manager role group membership in Microsoft Purview.'
        Write-Log -Message 'The Purview portal procedure in the runbook (section 6A.5) has no module dependency and is a reliable fallback.'
    }
    return
}

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$search   = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    $search = Get-ComplianceSearch -Identity $SearchName -ErrorAction SilentlyContinue
    if ($null -ne $search -and $search.Status -eq 'Completed') { break }
    Write-Log -Message ("  status: {0}" -f $(if ($search) { $search.Status } else { 'unknown' }))
}

if ($null -eq $search -or $search.Status -ne 'Completed') {
    Write-Log -Level 'WARN' -Message 'Search did not complete within the timeout. Check Purview > eDiscovery.'
    return
}

Write-Host ''
Write-Host '  -------------------------------------------------------------------' -ForegroundColor Green
Write-Host '   SEARCH RESULT' -ForegroundColor Green
Write-Host '  -------------------------------------------------------------------' -ForegroundColor Green
Write-Host ("   Items found : {0}" -f $search.Items) -ForegroundColor White
Write-Host ("   Size        : {0}" -f $search.Size) -ForegroundColor Gray
Write-Host ("   Status      : {0}" -f $search.Status) -ForegroundColor Gray
Write-Host '  -------------------------------------------------------------------' -ForegroundColor Green
Write-Host ''

if ($search.Items -eq 0) {
    Write-Log -Level 'WARN' -Message 'Zero items. Either the interaction is not mailbox-backed for this agent, indexing has not caught up (allow time after the conversation), or the mailbox is wrong.'
}

if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
$stamp   = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

if ($Preview -and $search.Items -gt 0) {
    Write-Log -Level 'STEP' -Message 'Running a Preview action to list the individual items ...'
    $previewOk = $false
    try {
        New-ComplianceSearchAction -SearchName $SearchName -Preview -ErrorAction Stop | Out-Null
        $previewOk = $true
    }
    catch {
        $pm = $_.Exception.Message
        Write-Log -Level 'ERROR' -Message ("Preview action failed: {0}" -f $pm)

        if ($pm -match '403|Forbidden') {
            Write-Host ''
            Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
            Write-Host '   PREVIEW / EXPORT ARE BLOCKED IN A SEARCH-ONLY SESSION' -ForegroundColor Yellow
            Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
            Write-Host '   The search itself SUCCEEDED - the item count above is real and the' -ForegroundColor White
            Write-Host '   search now exists in the portal. Only the content-retrieval step' -ForegroundColor White
            Write-Host '   was refused.' -ForegroundColor White
            Write-Host ''
            Write-Host '   This is the second half of a catch-22:' -ForegroundColor Gray
            Write-Host '     - Creating and running a search REQUIRES -EnableSearchOnlySession.' -ForegroundColor Gray
            Write-Host '     - Preview and Export are content-retrieval actions, which a' -ForegroundColor Gray
            Write-Host '       search-only session is not permitted to perform (HTTP 403).' -ForegroundColor Gray
            Write-Host '     - A 403 here can ALSO mean the account is not in the eDiscovery' -ForegroundColor Gray
            Write-Host '       Manager role group, which carries the Preview and Export roles.' -ForegroundColor Gray
            Write-Host ''
            Write-Host '   DO THIS INSTEAD - the export download is a manual ClickOnce step anyway:' -ForegroundColor White
            Write-Host ''
            Write-Host '   1. Purview > Solutions > eDiscovery > Content Search' -ForegroundColor Green
            Write-Host ("      Open '{0}'." -f $SearchName) -ForegroundColor Green
            Write-Host '   2. Sample tab > Generate sample results > Run Query' -ForegroundColor Green
            Write-Host '      to read items in the browser, OR' -ForegroundColor Gray
            Write-Host '   3. Export > download with the eDiscovery Export Tool, extract it, then:' -ForegroundColor Green
            Write-Host ''
            Write-Host '      .\Get-FirstPartyAgentReport.ps1 `' -ForegroundColor Cyan
            Write-Host '          -ExportPath C:\Scout_Output\M365AdminExport `' -ForegroundColor Cyan
            Write-Host ("          -UserUpn '{0}'" -f $UserUpn) -ForegroundColor Cyan
            Write-Host ''
            Write-Host '   That renders the HTML conversation report with prompts and agent' -ForegroundColor Gray
            Write-Host '   responses paired by sender identity.' -ForegroundColor Gray
            Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
            Write-Host ''
        }
    }

    if (-not $previewOk) {
        # Do not fall through to the export attempt - it will fail the same way.
        $Export = $false
    }
    else {
    $actionName = "$SearchName" + "_Preview"
    $deadline2  = (Get-Date).AddMinutes($TimeoutMinutes)
    $action     = $null
    while ((Get-Date) -lt $deadline2) {
        Start-Sleep -Seconds 10
        $action = Get-ComplianceSearchAction -Identity $actionName -IncludeCredential:$false -ErrorAction SilentlyContinue
        if ($null -ne $action -and $action.Status -eq 'Completed') { break }
        Write-Log -Message ("  preview status: {0}" -f $(if ($action) { $action.Status } else { 'unknown' }))
    }

    if ($null -eq $action -or $action.Status -ne 'Completed') {
        Write-Log -Level 'WARN' -Message 'Preview did not complete in time.'
        return
    }

    $results = [string] $action.Results
    [System.IO.File]::WriteAllText((Join-Path $OutputFolder "PreviewResults-RAW-$stamp.txt"), $results, $utf8Bom)

    # The Results blob is a semicolon-delimited set of key:value pairs, one block per item.
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($block in ($results -split '(?=Location:)')) {
        if ([string]::IsNullOrWhiteSpace($block)) { continue }
        $h = @{}
        foreach ($pair in ($block -split ';')) {
            if ($pair -match '^\s*([^:]+):\s*(.*)$') { $h[$Matches[1].Trim()] = $Matches[2].Trim() }
        }
        if ($h.Count -gt 0) {
            $rows.Add([pscustomobject]@{
                Sender     = $(if ($h.ContainsKey('Sender')) { $h['Sender'] } else { '' })
                Recipients = $(if ($h.ContainsKey('Recipient')) { $h['Recipient'] } else { '' })
                Subject    = $(if ($h.ContainsKey('Subject')) { $h['Subject'] } else { '' })
                Type       = $(if ($h.ContainsKey('Type')) { $h['Type'] } else { '' })
                Received   = $(if ($h.ContainsKey('Received Time')) { $h['Received Time'] } else { '' })
                Size       = $(if ($h.ContainsKey('Size')) { $h['Size'] } else { '' })
            }) | Out-Null
        }
    }

    Write-Host ''
    Write-Host '  --- ITEMS (the RESPONSE is the item whose Sender is the agent / Copilot) ---' -ForegroundColor Cyan
    if ($rows.Count -gt 0) {
        $rows | Sort-Object Received | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
        $csvPath = Join-Path $OutputFolder "FirstPartyAgent-Items-$stamp.csv"
        [System.IO.File]::WriteAllText($csvPath, (($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"), $utf8Bom)
        Write-Log -Level 'OK' -Message "Item list written: $csvPath"
    }
    else {
        Write-Log -Level 'WARN' -Message 'Preview returned no parseable items. The raw blob was saved for inspection.'
        Write-Host ($results.Substring(0, [Math]::Min(2000, $results.Length))) -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '   To get the RESPONSE BODY TEXT, export these items:' -ForegroundColor White
    Write-Host ("     New-ComplianceSearchAction -SearchName '{0}' -Export -Format FxStream" -f $SearchName) -ForegroundColor Green
    Write-Host '   then download with the eDiscovery Export Tool from Purview > eDiscovery > Exports.' -ForegroundColor Gray
    Write-Host ''
    }
}

if ($Export) {
    # Kick off the export action. The actual download must be done with the eDiscovery Export Tool
    # (a ClickOnce app launched from the Purview portal) - there is no API to pull the PST directly.
    Write-Log -Level 'STEP' -Message 'Starting the export action ...'
    try {
        New-ComplianceSearchAction -SearchName $SearchName -Export -Format FxStream -ErrorAction Stop | Out-Null
        Write-Log -Level 'OK' -Message 'Export action created.'
        Write-Host ''
        Write-Host '  -------------------------------------------------------------------' -ForegroundColor Green
        Write-Host '   NEXT STEPS - download the export, then render the HTML report' -ForegroundColor Green
        Write-Host '  -------------------------------------------------------------------' -ForegroundColor Green
        Write-Host '   1. Purview > Solutions > eDiscovery > Content Search > Exports' -ForegroundColor White
        Write-Host ("      Open the export for '{0}' and select Download results." -f $SearchName) -ForegroundColor Gray
        Write-Host '      (The eDiscovery Export Tool is a ClickOnce app - there is no API' -ForegroundColor DarkGray
        Write-Host '       to pull the PST directly, so this step is always manual.)' -ForegroundColor DarkGray
        Write-Host '   2. Extract the download somewhere, for example C:\Scout_Output\M365AdminExport' -ForegroundColor White
        Write-Host '   3. Render the readable conversation report:' -ForegroundColor White
        Write-Host ''
        Write-Host '      .\Get-FirstPartyAgentReport.ps1 `' -ForegroundColor Green
        Write-Host '          -ExportPath C:\Scout_Output\M365AdminExport `' -ForegroundColor Green
        Write-Host ("          -UserUpn '{0}'" -f $UserUpn) -ForegroundColor Green
        Write-Host ''
        Write-Host '   That produces HTML / CSV / JSON in the same style as the Copilot' -ForegroundColor Gray
        Write-Host '   Studio transcript report, with prompts and agent responses paired.' -ForegroundColor Gray
        Write-Host '  -------------------------------------------------------------------' -ForegroundColor Green
        Write-Host ''
    }
    catch {
        Write-Log -Level 'ERROR' -Message ("Could not start the export: {0}" -f $_.Exception.Message)
        if ($_.Exception.Message -match 'already exists') {
            Write-Log -Message 'An export action already exists for this search. Download it from Purview > eDiscovery > Content Search > Exports.'
        }
    }
}

if ($PurgeSearch) {
    if ($PSCmdlet.ShouldProcess($SearchName, 'Remove compliance search')) {
        try {
            Get-ComplianceSearchAction | Where-Object { $_.SearchName -eq $SearchName } |
                ForEach-Object { Remove-ComplianceSearchAction -Identity $_.Name -Confirm:$false -ErrorAction SilentlyContinue }
            Remove-ComplianceSearch -Identity $SearchName -Confirm:$false -ErrorAction Stop
            Write-Log -Level 'OK' -Message 'Compliance search removed. Tenant left clean.'
        }
        catch {
            Write-Log -Level 'WARN' -Message ("Could not remove the search: {0}" -f $_.Exception.Message)
        }
    }
}
else {
    Write-Log -Message ("Search '{0}' left in place. Remove it with -PurgeSearch or in Purview > eDiscovery." -f $SearchName)
}
