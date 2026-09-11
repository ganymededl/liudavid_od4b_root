<#
.SYNOPSIS
    Exports Microsoft Copilot Studio agent conversation transcripts (full user prompts and
    agent responses) from the Microsoft Dataverse ConversationTranscript table.

.DESCRIPTION
    Microsoft Purview Audit and DSPM for AI record that a Copilot Studio interaction occurred
    (who, when, source IP, host application), but they do NOT reliably return the prompt and
    response body for custom Copilot Studio agents. The authoritative store for the actual
    conversation content is the Dataverse 'conversationtranscript' table in the environment
    that hosts the agent.

    This script reads that table through the Dataverse Web API and produces reviewer-friendly
    output containing:
      - Full user prompt text
      - Full agent response text
      - Turn timestamps (UTC)
      - Entra ID object ID of the user (join key back to Purview Audit UserKey / UserId)
      - Agent identity (BotName / BotId) from the transcript metadata
      - Orchestration traces (tool calls, knowledge lookups, generative plan steps, errors)

    The script is READ ONLY against Dataverse. It never modifies or deletes transcript records.
    The only write operations are the local output files, which honor -WhatIf and -Confirm.

.PARAMETER EnvironmentUrl
    Dataverse environment URL that hosts the Copilot Studio agent, for example
    https://orgd63eebeb.crm.dynamics.com

    OPTIONAL. When omitted the script discovers it automatically using the Microsoft Global
    Discovery Service, so an administrator does not need to know or look up the URL in advance.
    If the signed-in identity has access to exactly one environment it is selected automatically.
    If several exist, the script lists them and asks you to re-run with -EnvironmentName.

.PARAMETER EnvironmentName
    Selects an environment by friendly name or URL name (for example 'Contoso (default)' or
    'orgd63eebeb') when discovery finds more than one. Matching is case-insensitive and accepts
    a partial name. Ignored when -EnvironmentUrl is supplied.

.PARAMETER ListEnvironments
    Lists every Dataverse environment the signed-in identity can reach, with friendly name, URL
    name and API URL, then exits. Use this when you do not know the environment URL.

.PARAMETER StartDateUtc
    Inclusive start of the conversation start time window, in UTC. Defaults to 90 days ago.
    Ignored when -AllHistory is supplied.

.PARAMETER EndDateUtc
    Exclusive end of the conversation start time window, in UTC. Defaults to now.

.PARAMETER AllHistory
    Ignores -StartDateUtc and exports everything the environment still retains, back to the
    oldest surviving transcript. Use this when you do not know how far the data goes, or when
    you want the maximum recoverable window. The script always reports the true retention
    horizon before exporting so the result is never mistaken for "all interactions ever".

.PARAMETER Discover
    Probes the environment and reports the retention horizon only - oldest transcript, newest
    transcript, total transcript count, and the per-agent breakdown - then exits without
    exporting anything. Run this FIRST against an unfamiliar tenant so you know what is actually
    recoverable before you scope an investigation. Read-only and very fast (three small queries).

.PARAMETER AgentName
    Optional agent filter. Matches the **friendly display name** shown in the Microsoft 365 admin
    center Agent Registry (for example 'MCP Enterprise Admin Assistant' or just 'Enterprise Admin'),
    OR the underlying Dataverse schema name (for example 'cr834_MCPEnterpriseAdminAssistant').
    Matching is case-insensitive, ignores spaces, and accepts a partial name - so an administrator
    can copy the name straight from the Agent Registry without knowing any identifier.

.PARAMETER User
    Optional user filter, accepting whatever the administrator actually has to hand:
      - alias                       AdilE
      - user principal name         AdilE@contoso.onmicrosoft.com
      - display name (partial)      Adil Eli
      - Entra object GUID           24ecf3bc-3a28-4657-bac1-b569df000107
    The value is resolved against the Dataverse system user directory and reported before the
    export runs, so you can confirm the right person was matched.

.PARAMETER UserObjectId
    Optional Entra ID object GUID. Equivalent to passing the same GUID to -User, and kept for
    scripted pivots from a Purview Audit record where you already hold the UserKey value.

.PARAMETER TimeZoneId
    Windows time zone used for all human-readable timestamps in the console and reports.
    Defaults to 'Eastern Standard Time'. UTC is always retained alongside local time for evidence.
    Run [TimeZoneInfo]::GetSystemTimeZones() to list valid IDs.

.PARAMETER SortOrder
    Default chronological ordering of conversations in every output. 'Newest' (default) lists the
    most recent conversation first; 'Oldest' lists the earliest conversation first. Turns inside a
    conversation are ALWAYS rendered oldest to newest so the exchange reads in the order it happened.
    The HTML report also exposes a Newest/Oldest selector so a reviewer can flip the order without
    re-running the export.

.PARAMETER OutputFolder
    Folder that receives the generated files. Created if it does not exist.
    Defaults to C:\Scout_Output\CopilotStudio-Transcripts.

.PARAMETER Format
    Output format: Json, Csv, Html, or All. Defaults to All.
      Json - one structured file per run containing the verbatim original text plus orchestration
             traces (best for forensics and chain of custody)
      Csv  - one flat row per conversational turn, with markup stripped for readability
             (best for review, filtering and pivoting)
      Html - self-contained, filterable chat-style review report with summary cards
             (best for handing to a stakeholder or customer)

.PARAMETER AccessToken
    Optional pre-acquired OAuth bearer token for the Dataverse environment. When omitted the
    script acquires one using the method chosen by -AuthMethod.

.PARAMETER TenantId
    Microsoft Entra tenant GUID that owns the Dataverse environment. Strongly recommended when
    the environment is in a different tenant than your default Azure CLI context (for example a
    lab or demo tenant). When supplied, the script verifies that the acquired token was actually
    issued for this tenant and fails fast with a clear message if it was not.

.PARAMETER AuthMethod
    How to acquire the Dataverse token:
      Auto       - use -AccessToken if supplied, otherwise Azure CLI, otherwise device code (default)
      AzureCli   - force Azure CLI ('az account get-access-token')
      DeviceCode - force interactive device code sign-in. Use this for cross-tenant lab and demo
                   environments. It does NOT modify your default Azure CLI context.
      Token      - require -AccessToken and use it unchanged

.PARAMETER IncludeTraces
    Include orchestration trace activities (tool and MCP calls, knowledge lookups, generative
    plan steps, error traces) in the JSON output. Increases output size significantly.

.PARAMETER MaxRetries
    Maximum retry attempts for throttled or transient failures. Defaults to 5.

.PARAMETER Force
    Suppresses the quick-reference banner and does not prompt for confirmation on overwrite.

.PARAMETER PassThru
    Emits the conversation objects to the PowerShell pipeline for further scripting. Off by
    default so the console stays readable - the report files are the deliverable, not console text.

.PARAMETER Help
    Displays this help text and exits.

.EXAMPLE
    .\Export-CopilotStudioTranscripts.ps1 -TenantId c1fdbce8-e6b0-43e2-82b5-6fbe5dda28b4 `
        -AuthMethod DeviceCode -ListEnvironments

    Lists every Dataverse environment the signed-in identity can reach. Use this first when the
    environment URL is unknown - no need to hunt through the Power Platform admin center.

.EXAMPLE
    .\Export-CopilotStudioTranscripts.ps1 -TenantId c1fdbce8-e6b0-43e2-82b5-6fbe5dda28b4 `
        -AuthMethod DeviceCode -Discover

    Auto-discovers the environment, then reports the retention horizon and per-agent inventory.
    Nothing is exported. This is the recommended first command in an unfamiliar tenant.

.EXAMPLE
    .\Export-CopilotStudioTranscripts.ps1 -EnvironmentUrl https://orgd63eebeb.crm.dynamics.com

    Exports the last 90 days of all Copilot Studio transcripts in every supported format.

.EXAMPLE
    .\Export-CopilotStudioTranscripts.ps1 -EnvironmentUrl https://orgd63eebeb.crm.dynamics.com `
        -TenantId c1fdbce8-e6b0-43e2-82b5-6fbe5dda28b4 -AuthMethod DeviceCode -Discover

    STEP 1 for any unfamiliar tenant. Reports exactly how far back the data goes and how many
    transcripts exist per agent, without exporting anything.

.EXAMPLE
    .\Export-CopilotStudioTranscripts.ps1 -EnvironmentUrl https://orgd63eebeb.crm.dynamics.com `
        -TenantId c1fdbce8-e6b0-43e2-82b5-6fbe5dda28b4 -AuthMethod DeviceCode -AllHistory

    Exports everything the environment still retains, back to the oldest surviving transcript.

.EXAMPLE
    .\Export-CopilotStudioTranscripts.ps1 -EnvironmentUrl https://orgd63eebeb.crm.dynamics.com `
        -AgentName 'MCPEnterpriseAdminAssistant' -StartDateUtc '2026-08-23' -EndDateUtc '2026-08-25'

    Narrow investigation window for one named agent.

.EXAMPLE
    .\Export-CopilotStudioTranscripts.ps1 -EnvironmentUrl https://orgd63eebeb.crm.dynamics.com `
        -UserObjectId 'cb410005-38ba-4475-bb3c-81b70678a246' -Format Html

    Pivots from a Purview Audit UserKey to every conversation that user had with any agent,
    rendered as a readable HTML review packet.

.EXAMPLE
    .\Export-CopilotStudioTranscripts.ps1 -EnvironmentUrl https://orgd63eebeb.crm.dynamics.com `
        -TenantId c1fdbce8-e6b0-43e2-82b5-6fbe5dda28b4 -AuthMethod DeviceCode

    Signs in interactively to a lab or demo tenant that differs from your default Azure CLI
    context. This is the correct pattern when 'az account show' reports a different tenant,
    which otherwise produces an HTTP 403 from Dataverse.

.EXAMPLE
    .\Export-CopilotStudioTranscripts.ps1 -EnvironmentUrl https://orgd63eebeb.crm.dynamics.com -WhatIf

    Performs the read and reports exactly what would be written without creating any files.

.NOTES
    Author        : David Shih Chun Liu
    Compatibility : Windows PowerShell 5.1 and PowerShell 7.x
    Permissions   : A Dataverse security role with Read on the ConversationTranscript table.
                    The documented least-privilege role is Bot Transcript Viewer. Environment Maker
                    does NOT grant it, and a Microsoft 365 Global Administrator is not automatically
                    a Dataverse user at all. Both are granted PER ENVIRONMENT.
                    Run Test-CopilotAuditReadiness.ps1 first - it surveys every environment in the
                    tenant, proves access with a live read, and prints the exact remediation steps.
    Data handling : Output contains full prompt and response text. Treat as sensitive.
                    Apply least privilege and organizational retention rules to the output.

    Related product limits:
      - Copilot Studio Monitor downloads only cover roughly the last 28 days, from a SEPARATE store.
        Dataverse is the longer-window source, subject to the environment's bulk deletion job.
      - Default Dataverse retention is 30 days via the job "Bulk Delete Conversation Transcript
        Records Older Than 1 Month". This is a DEFAULT, not a platform limit - an administrator can
        extend it. This script always measures the real horizon instead of assuming.
      - Transcripts are NOT written for Microsoft 365 Copilot agents, for Microsoft Dataverse for
        Teams environments, or for agents deployed in DEVELOPER environments.
      - For SharePoint-grounded answers the user's question is stored but the generated answer is
        stored as REDACTED. Expect legitimate gaps; this is not a defect in this script.
      - Every environment stores its own transcripts. There is no tenant-wide transcript table, so a
        complete tenant audit means running this script once per environment.
      - Records larger than 1 MB are split across rows sharing the same Name value; merge them
        in Metadata.BatchId order. This script performs that merge automatically.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string] $EnvironmentUrl,

    [Parameter(Mandatory = $false)]
    [string] $EnvironmentName,

    [Parameter(Mandatory = $false)]
    [switch] $ListEnvironments,

    [Parameter(Mandatory = $false)]
    [datetime] $StartDateUtc = (Get-Date).ToUniversalTime().AddDays(-90),

    [Parameter(Mandatory = $false)]
    [datetime] $EndDateUtc = (Get-Date).ToUniversalTime(),

    [Parameter(Mandatory = $false)]
    [switch] $AllHistory,

    [Parameter(Mandatory = $false)]
    [switch] $Discover,

    [Parameter(Mandatory = $false)]
    [string] $AgentName,

    [Parameter(Mandatory = $false)]
    [string] $User,

    [Parameter(Mandatory = $false)]
    [string] $UserObjectId,

    [Parameter(Mandatory = $false)]
    [string] $TimeZoneId = 'Eastern Standard Time',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Newest', 'Oldest')]
    [string] $SortOrder = 'Newest',

    [Parameter(Mandatory = $false)]
    [string] $OutputFolder = 'C:\Scout_Output\CopilotStudio-Transcripts',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Json', 'Csv', 'Html', 'All')]
    [string] $Format = 'All',

    [Parameter(Mandatory = $false)]
    [string] $AccessToken,

    [Parameter(Mandatory = $false)]
    [string] $TenantId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'AzureCli', 'DeviceCode', 'Token')]
    [string] $AuthMethod = 'Auto',

    [Parameter(Mandatory = $false)]
    [switch] $IncludeTraces,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 20)]
    [int] $MaxRetries = 5,

    [Parameter(Mandatory = $false)]
    [switch] $Force,

    [Parameter(Mandatory = $false)]
    [switch] $PassThru,

    [Parameter(Mandatory = $false)]
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------------------------
$script:LogLines = New-Object System.Collections.Generic.List[string]

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Message,
        [Parameter(Mandatory = $false)][ValidateSet('INFO', 'WARN', 'ERROR', 'OK', 'STEP')][string] $Level = 'INFO'
    )

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $line  = '[{0}] [{1,-5}] {2}' -f $stamp, $Level, $Message
    $script:LogLines.Add($line) | Out-Null

    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        'STEP'  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line -ForegroundColor Gray }
    }
}

function Show-Banner {
    Write-Host ''
    Write-Host '===============================================================================' -ForegroundColor DarkCyan
    Write-Host ' Export-CopilotStudioTranscripts - Copilot Studio conversation content export'   -ForegroundColor White
    Write-Host '===============================================================================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host ' WHAT THIS DOES' -ForegroundColor White
    Write-Host '   Reads full user prompts and agent responses from the Dataverse'
    Write-Host '   ConversationTranscript table. This is the authoritative content source.'
    Write-Host ''
    Write-Host ' WHY NOT PURVIEW' -ForegroundColor White
    Write-Host '   Purview Audit CopilotInteraction records prove that an interaction happened'
    Write-Host '   (user, time, IP, AppHost, ThreadId) but do not carry the prompt/response body'
    Write-Host '   for custom Copilot Studio agents. DSPM for AI commonly reports'
    Write-Host '   "Information not available" for these same agents.'
    Write-Host ''
    Write-Host ' JOIN KEY BACK TO AUDIT' -ForegroundColor White
    Write-Host '   Purview Audit UserKey / UserId  ==  transcript turn aadObjectId'
    Write-Host '   Correlate on that GUID plus the UTC time window plus BotName.'
    Write-Host ''
    Write-Host ' SAFETY' -ForegroundColor White
    Write-Host '   Read only against Dataverse. Supports -WhatIf. Output contains sensitive'
    Write-Host '   conversation text - store and share accordingly.'
    Write-Host ''
    Write-Host ' QUICK START' -ForegroundColor White
    Write-Host '   1. .\Export-CopilotStudioTranscripts.ps1 -TenantId <guid> -AuthMethod DeviceCode -Discover'
    Write-Host '      Finds the Dataverse environment for you and reports how far back data goes.'
    Write-Host '   2. Add -AllHistory to export everything the environment still retains.'
    Write-Host '   You do NOT need to know the Dataverse URL - it is discovered automatically.'
    Write-Host '   Add -Help for full documentation. Add -Force to skip this banner.'
    Write-Host ''
    Write-Host '===============================================================================' -ForegroundColor DarkCyan
    Write-Host ''
}

# ---------------------------------------------------------------------------------------------
# Help / banner gates
# ---------------------------------------------------------------------------------------------
if ($Help) {
    Get-Help -Full $MyInvocation.MyCommand.Path
    return
}

if (-not $Force) { Show-Banner }

if (-not [string]::IsNullOrWhiteSpace($EnvironmentUrl)) {
    $EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')
    if ($EnvironmentUrl -notmatch '^https://') {
        Write-Log -Level 'ERROR' -Message "EnvironmentUrl must start with https:// . Received: $EnvironmentUrl"
        return
    }
}

if ($EndDateUtc -le $StartDateUtc) {
    Write-Log -Level 'ERROR' -Message 'EndDateUtc must be later than StartDateUtc.'
    return
}

if ($PSBoundParameters.ContainsKey('UserObjectId') -and -not [string]::IsNullOrWhiteSpace($UserObjectId)) {
    $parsedGuid = [guid]::Empty
    if (-not [guid]::TryParse($UserObjectId, [ref]$parsedGuid)) {
        Write-Log -Level 'ERROR' -Message "UserObjectId must be a valid GUID. Received: $UserObjectId"
        return
    }
}

# ---------------------------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------------------------

# Well-known Microsoft first-party public client that is pre-consented for Dataverse.
# Using a public client avoids any app registration work in the target tenant.
$script:PublicClientId = '51f81489-12ee-4a9e-aaae-a2591f45987d'
$script:CachedRefreshToken = $null

function ConvertFrom-JwtPayload {
    <#
        Decodes the (unverified) payload of a JWT so the script can report which identity and
        tenant the token actually represents. Used for diagnostics only, never for trust.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Token)

    try {
        $parts = $Token.Split('.')
        if ($parts.Count -lt 2) { return $null }

        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
            1 { return $null }
        }

        $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
        return $json | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-TokenIdentityInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Token)

    $claims = ConvertFrom-JwtPayload -Token $Token
    if ($null -eq $claims) {
        return [pscustomobject]@{ Upn = '(undecodable)'; TenantId = '(undecodable)'; Audience = '(undecodable)' }
    }

    $upn = '(unknown)'
    foreach ($c in 'upn', 'preferred_username', 'unique_name', 'appid') {
        if (($claims.PSObject.Properties.Name -contains $c) -and -not [string]::IsNullOrWhiteSpace($claims.$c)) {
            $upn = [string] $claims.$c
            break
        }
    }

    $tid = '(unknown)'
    if (($claims.PSObject.Properties.Name -contains 'tid') -and -not [string]::IsNullOrWhiteSpace($claims.tid)) {
        $tid = [string] $claims.tid
    }

    $aud = '(unknown)'
    if (($claims.PSObject.Properties.Name -contains 'aud') -and -not [string]::IsNullOrWhiteSpace($claims.aud)) {
        $aud = [string] $claims.aud
    }

    return [pscustomobject]@{ Upn = $upn; TenantId = $tid; Audience = $aud }
}

function Get-TokenByDeviceCode {
    <#
        Interactive device code sign-in against the target tenant. Does not read or modify the
        Azure CLI context, so it is safe to use for lab and demo tenants while the corporate
        Azure CLI session stays signed in elsewhere.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Resource,
        [Parameter(Mandatory = $true)][string] $Tenant
    )

    $authority = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0"
    $scope     = "$Resource/.default offline_access openid profile"

    Write-Log -Level 'STEP' -Message "Starting device code sign-in against tenant $Tenant"

    try {
        $codeResponse = Invoke-RestMethod -Method Post -Uri "$authority/devicecode" `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{ client_id = $script:PublicClientId; scope = $scope } `
            -UseBasicParsing -TimeoutSec 60
    }
    catch {
        throw "Could not start device code sign-in against tenant $Tenant. Detail: $($_.Exception.Message)"
    }

    Write-Host ''
    Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host '   INTERACTIVE SIGN-IN REQUIRED' -ForegroundColor Yellow
    Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ("   1. Open : {0}" -f $codeResponse.verification_uri) -ForegroundColor White
    Write-Host ("   2. Code : {0}" -f $codeResponse.user_code) -ForegroundColor Green
    Write-Host  '   3. Sign in with an account that exists in the TARGET tenant' -ForegroundColor White
    Write-Host  '      (for a lab tenant this is the lab admin, not your corporate account).' -ForegroundColor Gray
    Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ''

    $interval = 5
    if (($codeResponse.PSObject.Properties.Name -contains 'interval') -and $codeResponse.interval) {
        $interval = [int] $codeResponse.interval
    }

    $expires = (Get-Date).AddSeconds([int] $codeResponse.expires_in)
    $script:PollNoticeShown = $false

    while ((Get-Date) -lt $expires) {
        Start-Sleep -Seconds $interval
        try {
            $tokenResponse = Invoke-RestMethod -Method Post -Uri "$authority/token" `
                -ContentType 'application/x-www-form-urlencoded' `
                -Body @{
                    grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                    client_id   = $script:PublicClientId
                    device_code = $codeResponse.device_code
                } -UseBasicParsing -TimeoutSec 60

            Write-Log -Level 'OK' -Message 'Device code sign-in completed.'
            # Cache the refresh token so a second resource (for example Global Discovery followed
            # by the environment itself) can be obtained silently without a second sign-in.
            if ($tokenResponse.PSObject.Properties.Name -contains 'refresh_token') {
                $script:CachedRefreshToken = [string] $tokenResponse.refresh_token
            }
            return $tokenResponse.access_token
        }
        catch {
            # PowerShell surfaces the OAuth error body differently depending on host and version.
            # Check ErrorDetails first (populated by Invoke-RestMethod in 5.1 and 7.x), then fall
            # back to reading the response stream directly.
            $errBody = ''

            if ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
                $errBody = [string] $_.ErrorDetails.Message
            }

            if ([string]::IsNullOrWhiteSpace($errBody) -and $null -ne $_.Exception.Response) {
                try {
                    $stream = $_.Exception.Response.GetResponseStream()
                    if ($null -ne $stream) {
                        if ($stream.CanSeek) { $stream.Position = 0 }
                        $reader  = New-Object System.IO.StreamReader($stream)
                        $errBody = $reader.ReadToEnd()
                        $reader.Close()
                    }
                }
                catch { $errBody = '' }
            }

            $oauthError = ''
            if (-not [string]::IsNullOrWhiteSpace($errBody)) {
                try { $oauthError = [string] ($errBody | ConvertFrom-Json).error } catch { $oauthError = '' }
            }
            if ([string]::IsNullOrWhiteSpace($oauthError) -and $errBody -match '"error"\s*:\s*"([a-z_]+)"') {
                $oauthError = $Matches[1]
            }

            # NOTE: 'continue' inside a PowerShell switch acts on the switch, not the enclosing
            # loop. Use an explicit flag so polling actually continues.
            $shouldKeepPolling = $false

            if ($oauthError -eq 'authorization_pending') {
                $shouldKeepPolling = $true
            }
            elseif ($oauthError -eq 'slow_down') {
                $interval += 5
                $shouldKeepPolling = $true
            }
            elseif ($oauthError -eq 'authorization_declined') {
                throw 'Device code sign-in was declined in the browser.'
            }
            elseif ($oauthError -eq 'expired_token') {
                throw 'The device code expired before sign-in completed. Re-run and complete sign-in within the displayed time.'
            }
            elseif ($oauthError -eq 'bad_verification_code') {
                throw 'The device code was rejected. Re-run to obtain a fresh code.'
            }
            else {
                # A 400 with no decodable OAuth error during polling is still almost always a
                # pending authorization, so keep polling rather than failing the whole run.
                $statusCode = $null
                if ($null -ne $_.Exception.Response) {
                    try { $statusCode = [int] $_.Exception.Response.StatusCode } catch { $statusCode = $null }
                }
                if ($statusCode -eq 400 -and [string]::IsNullOrWhiteSpace($oauthError)) {
                    $shouldKeepPolling = $true
                }
            }

            if ($shouldKeepPolling) {
                if (-not $script:PollNoticeShown) {
                    Write-Log -Message 'Waiting for sign-in to complete in the browser ...'
                    $script:PollNoticeShown = $true
                }
                continue
            }

            throw "Device code sign-in failed. OAuth error: '$oauthError'. Detail: $errBody $($_.Exception.Message)"
        }
    }

    throw 'Device code sign-in timed out.'
}

function Get-TokenByAzureCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Resource,
        [Parameter(Mandatory = $false)][string] $Tenant
    )

    $azCmd = Get-Command -Name 'az' -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $azCmd) {
        throw "Azure CLI ('az') was not found on PATH."
    }

    # Report the CLI context up front. A tenant mismatch here is the single most common
    # cause of an HTTP 403 from Dataverse.
    try {
        $ctxRaw = & az account show --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $ctxRaw) {
            $ctx = ($ctxRaw | Out-String) | ConvertFrom-Json
            Write-Log -Message ("Azure CLI context : {0} in tenant {1}" -f $ctx.user.name, $ctx.tenantId)

            if (-not [string]::IsNullOrWhiteSpace($Tenant) -and $ctx.tenantId -ne $Tenant) {
                throw ("Azure CLI is signed in to tenant {0} as {1}, but the target environment is in tenant {2}. " -f $ctx.tenantId, $ctx.user.name, $Tenant) +
                      "A cross-tenant token will be rejected by Dataverse with HTTP 403. " +
                      "Re-run with -AuthMethod DeviceCode (recommended, leaves your Azure CLI context untouched), " +
                      "or run: az login --tenant $Tenant --allow-no-subscriptions"
            }
        }
    }
    catch {
        if ($_.Exception.Message -like '*cross-tenant*' -or $_.Exception.Message -like '*Azure CLI is signed in to tenant*') { throw }
        Write-Log -Level 'WARN' -Message 'Could not read the Azure CLI context; continuing.'
    }

    $azArgs = @('account', 'get-access-token', '--resource', $Resource, '--output', 'json')
    if (-not [string]::IsNullOrWhiteSpace($Tenant)) { $azArgs += @('--tenant', $Tenant) }

    Write-Log -Level 'STEP' -Message "Acquiring Dataverse token via Azure CLI for resource $Resource"
    $raw = & az @azArgs 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI token acquisition failed (exit code $LASTEXITCODE). Detail: $raw"
    }

    try {
        $parsed = ($raw | Out-String) | ConvertFrom-Json
    }
    catch {
        throw "Could not parse the Azure CLI token response. Detail: $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace($parsed.accessToken)) {
        throw 'Azure CLI returned an empty access token.'
    }

    return $parsed.accessToken
}

function Get-DataverseToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Resource,
        [Parameter(Mandatory = $false)][string] $SuppliedToken,
        [Parameter(Mandatory = $false)][string] $Tenant,
        [Parameter(Mandatory = $false)][string] $Method = 'Auto'
    )

    $token = $null

    # If a previous acquisition in this run already produced a refresh token (for example the
    # Global Discovery call), redeem it silently for this resource instead of prompting again.
    if (-not [string]::IsNullOrWhiteSpace($script:CachedRefreshToken) -and -not [string]::IsNullOrWhiteSpace($Tenant) -and $Method -ne 'Token') {
        $silent = Get-TokenByRefresh -Resource $Resource -Tenant $Tenant -RefreshToken $script:CachedRefreshToken
        if (-not [string]::IsNullOrWhiteSpace($silent)) {
            Write-Log -Level 'OK' -Message ("Reused existing sign-in for {0} (no second prompt)." -f $Resource)
            $token = $silent
        }
    }

    if ([string]::IsNullOrWhiteSpace($token)) {
        switch ($Method) {
            'Token' {
                if ([string]::IsNullOrWhiteSpace($SuppliedToken)) {
                    throw '-AuthMethod Token requires -AccessToken to be supplied.'
                }
                $token = $SuppliedToken
                Write-Log -Level 'OK' -Message 'Using caller-supplied access token.'
            }
            'DeviceCode' {
                if ([string]::IsNullOrWhiteSpace($Tenant)) {
                    throw '-AuthMethod DeviceCode requires -TenantId (the Entra tenant GUID that owns the Dataverse environment).'
                }
                $token = Get-TokenByDeviceCode -Resource $Resource -Tenant $Tenant
            }
            'AzureCli' {
                $token = Get-TokenByAzureCli -Resource $Resource -Tenant $Tenant
            }
            default {
                if (-not [string]::IsNullOrWhiteSpace($SuppliedToken)) {
                    $token = $SuppliedToken
                    Write-Log -Level 'OK' -Message 'Using caller-supplied access token.'
                }
                else {
                    try {
                        $token = Get-TokenByAzureCli -Resource $Resource -Tenant $Tenant
                    }
                    catch {
                        Write-Log -Level 'WARN' -Message ("Azure CLI path unavailable: {0}" -f $_.Exception.Message)
                        if ([string]::IsNullOrWhiteSpace($Tenant)) {
                            throw 'Azure CLI token acquisition failed and no -TenantId was supplied, so device code sign-in cannot be attempted. Re-run with -TenantId <tenant GUID> -AuthMethod DeviceCode.'
                        }
                        Write-Log -Level 'STEP' -Message 'Falling back to interactive device code sign-in.'
                        $token = Get-TokenByDeviceCode -Resource $Resource -Tenant $Tenant
                    }
                }
            }
        }
    }

    # Preflight: report exactly which identity and tenant this token represents.
    $info = Get-TokenIdentityInfo -Token $token
    Write-Log -Level 'OK' -Message ("Token identity  : {0}" -f $info.Upn)
    Write-Log -Message           ("Token tenant    : {0}" -f $info.TenantId)
    Write-Log -Message           ("Token audience  : {0}" -f $info.Audience)

    if (-not [string]::IsNullOrWhiteSpace($Tenant) -and $info.TenantId -notin @($Tenant, '(unknown)', '(undecodable)')) {
        throw ("Token tenant mismatch. The token was issued for tenant {0} but the environment is in tenant {1}. Dataverse will reject this with HTTP 403. Re-run with -AuthMethod DeviceCode." -f $info.TenantId, $Tenant)
    }

    if ($info.Audience -notin @('(unknown)', '(undecodable)') -and $info.Audience.TrimEnd('/') -ne $Resource.TrimEnd('/')) {
        Write-Log -Level 'WARN' -Message ("Token audience '{0}' does not match the environment URL '{1}'. Dataverse may reject it." -f $info.Audience, $Resource)
    }

    return $token
}

# ---------------------------------------------------------------------------------------------
# Throttle-safe Dataverse Web API call
# ---------------------------------------------------------------------------------------------
function Invoke-DataverseRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Uri,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $false)][int] $Retries = 5
    )

    $headers = @{
        'Authorization'    = "Bearer $Token"
        'Accept'           = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
        'Prefer'           = 'odata.maxpagesize=200'
    }

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get -UseBasicParsing -TimeoutSec 180
        }
        catch {
            $status = $null
            $retryAfter = $null

            if ($null -ne $_.Exception.Response) {
                try { $status = [int] $_.Exception.Response.StatusCode } catch { $status = $null }
                try { $retryAfter = $_.Exception.Response.Headers['Retry-After'] } catch { $retryAfter = $null }
            }

            $isTransient = ($status -in 429, 500, 502, 503, 504) -or ($null -eq $status)

            if (-not $isTransient -or $attempt -gt $Retries) {
                $detail = $_.Exception.Message
                if ($status -eq 401) {
                    $detail += " (HTTP 401 - the token is expired, malformed, or was issued for a different audience. Re-acquire the token.)"
                }
                elseif ($status -eq 403) {
                    $detail += ' (HTTP 403 - Dataverse accepted the token but refused the request. In order of likelihood: ' +
                               '(1) the token identity belongs to a DIFFERENT TENANT than the environment - compare the "Token tenant" line above with your environment tenant, and re-run with -TenantId <guid> -AuthMethod DeviceCode; ' +
                               '(2) the identity is not provisioned as an enabled user in this Dataverse environment - a Global Administrator is NOT automatically a Dataverse user; ' +
                               '(3) the identity lacks Read privilege on the ConversationTranscript table - assign the Bot Transcript Viewer security role in THIS environment, as Environment Maker does not grant it. ' +
                               'Run Test-CopilotAuditReadiness.ps1 to have this diagnosed per environment automatically.)'
                }
                throw "Dataverse request failed after $attempt attempt(s). URI: $Uri. Detail: $detail"
            }

            $delay = [math]::Min(60, [math]::Pow(2, $attempt))
            if ($retryAfter -and ($retryAfter -as [int])) { $delay = [int] $retryAfter }

            Write-Log -Level 'WARN' -Message ("Transient failure (status {0}) on attempt {1}. Backing off {2}s." -f $status, $attempt, $delay)
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-TokenByRefresh {
    <#
        Redeems a cached refresh token for a different resource. This is what makes
        "discover the environment, then read it" a single interactive sign-in instead of two.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Resource,
        [Parameter(Mandatory = $true)][string] $Tenant,
        [Parameter(Mandatory = $true)][string] $RefreshToken
    )

    $authority = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0"

    try {
        $resp = Invoke-RestMethod -Method Post -Uri "$authority/token" `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{
                grant_type    = 'refresh_token'
                client_id     = $script:PublicClientId
                refresh_token = $RefreshToken
                scope         = "$Resource/.default offline_access openid profile"
            } -UseBasicParsing -TimeoutSec 60

        if ($resp.PSObject.Properties.Name -contains 'refresh_token') {
            $script:CachedRefreshToken = [string] $resp.refresh_token
        }
        return $resp.access_token
    }
    catch {
        return $null
    }
}

function Get-DataverseEnvironments {
    <#
        Enumerates every Dataverse environment the signed-in identity can reach, using the
        Microsoft Global Discovery Service. This removes the need for an administrator to know
        the environment URL in advance - a common blocker, since the URL is not shown anywhere
        obvious in Copilot Studio and requires a trip to the Power Platform admin center.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Token
    )

    $uri = 'https://globaldisco.crm.dynamics.com/api/discovery/v2.0/Instances'

    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers @{
            Authorization = "Bearer $Token"
            Accept        = 'application/json'
        } -Method Get -UseBasicParsing -TimeoutSec 120
    }
    catch {
        throw "Global Discovery Service query failed. Detail: $($_.Exception.Message)"
    }

    $out = New-Object System.Collections.Generic.List[object]
    if ($resp.PSObject.Properties.Name -contains 'value' -and $null -ne $resp.value) {
        foreach ($i in $resp.value) {
            $out.Add([pscustomobject]@{
                FriendlyName = $(if ($i.PSObject.Properties.Name -contains 'FriendlyName') { [string] $i.FriendlyName } else { '' })
                UrlName      = $(if ($i.PSObject.Properties.Name -contains 'UrlName')      { [string] $i.UrlName }      else { '' })
                Url          = $(if ($i.PSObject.Properties.Name -contains 'Url')          { ([string] $i.Url).TrimEnd('/') } else { '' })
                ApiUrl       = $(if ($i.PSObject.Properties.Name -contains 'ApiUrl')       { ([string] $i.ApiUrl).TrimEnd('/') } else { '' })
                State        = $(if ($i.PSObject.Properties.Name -contains 'State')        { [string] $i.State }        else { '' })
            }) | Out-Null
        }
    }

    # Return a plain array; the caller wraps in @() so a single result keeps .Count.
    return ($out.ToArray() | Sort-Object FriendlyName)
}

function Get-BotDirectory {
    <#
        Maps Copilot Studio agent identifiers to the friendly display name an administrator
        actually sees in the Microsoft 365 admin center Agent Registry.

        Transcript metadata carries the Dataverse schema name (for example
        'cr834_harvardprofessionalwritingc_3_SZtu'), which is unreadable and does not appear in
        any admin UI. The Dataverse 'bot' table carries both that schema name and the display
        name ('Harvard Writing Coach'), keyed by BotId - which transcript metadata also carries.
        Uses the same Dataverse token, so no Microsoft Graph consent is required.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $BaseUrl,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $false)][int] $Retries = 5
    )

    $map = @{}
    try {
        $uri = "$BaseUrl/api/data/v9.2/bots?`$select=botid,name,schemaname"
        while (-not [string]::IsNullOrWhiteSpace($uri)) {
            $resp = Invoke-DataverseRequest -Uri $uri -Token $Token -Retries $Retries
            if ($resp.PSObject.Properties.Name -contains 'value' -and $null -ne $resp.value) {
                foreach ($b in $resp.value) {
                    $entry = [pscustomobject]@{
                        BotId       = [string] $b.botid
                        DisplayName = [string] $b.name
                        SchemaName  = [string] $b.schemaname
                    }
                    if (-not [string]::IsNullOrWhiteSpace($entry.BotId))      { $map[$entry.BotId.ToLowerInvariant()]      = $entry }
                    if (-not [string]::IsNullOrWhiteSpace($entry.SchemaName)) { $map[$entry.SchemaName.ToLowerInvariant()] = $entry }
                }
            }
            $uri = ''
            if ($resp.PSObject.Properties.Name -contains '@odata.nextLink') { $uri = [string] $resp.'@odata.nextLink' }
        }
    }
    catch {
        Write-Log -Level 'WARN' -Message ("Could not read the agent directory (bot table): {0}. Falling back to raw schema names." -f $_.Exception.Message)
    }

    return $map
}

function Get-UserDirectory {
    <#
        Maps Entra ID object GUIDs to display name and user principal name using the Dataverse
        'systemuser' table, which stores azureactivedirectoryobjectid alongside fullname and
        domainname. This lets the tool accept an alias, UPN or display name from an administrator
        and report who was actually matched, without requiring Microsoft Graph permissions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $BaseUrl,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $false)][int] $Retries = 5
    )

    $users = New-Object System.Collections.Generic.List[object]
    try {
        $uri = "$BaseUrl/api/data/v9.2/systemusers?`$select=azureactivedirectoryobjectid,domainname,fullname,internalemailaddress&`$filter=azureactivedirectoryobjectid ne null"
        while (-not [string]::IsNullOrWhiteSpace($uri)) {
            $resp = Invoke-DataverseRequest -Uri $uri -Token $Token -Retries $Retries
            if ($resp.PSObject.Properties.Name -contains 'value' -and $null -ne $resp.value) {
                foreach ($u in $resp.value) {
                    $oid = [string] $u.azureactivedirectoryobjectid
                    if ([string]::IsNullOrWhiteSpace($oid)) { continue }
                    $upn = [string] $u.domainname
                    $users.Add([pscustomobject]@{
                        ObjectId    = $oid
                        DisplayName = [string] $u.fullname
                        Upn         = $upn
                        Alias       = $(if ($upn -match '^([^@]+)@') { $Matches[1] } else { '' })
                    }) | Out-Null
                }
            }
            $uri = ''
            if ($resp.PSObject.Properties.Name -contains '@odata.nextLink') { $uri = [string] $resp.'@odata.nextLink' }
        }
    }
    catch {
        Write-Log -Level 'WARN' -Message ("Could not read the user directory (systemuser table): {0}. Object IDs will be shown unresolved." -f $_.Exception.Message)
    }

    return $users.ToArray()
}

function Resolve-UserIdentifier {
    <#
        Accepts whatever an administrator has to hand - alias, UPN, display name or object GUID -
        and returns the matching directory entries. Ambiguity is surfaced to the caller rather
        than silently guessing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Value,
        [Parameter(Mandatory = $true)] $Directory
    )

    $needle = $Value.Trim()
    $dir    = @($Directory)

    $guid = [guid]::Empty
    if ([guid]::TryParse($needle, [ref]$guid)) {
        $exact = @($dir | Where-Object { $_.ObjectId -eq $needle })
        if ($exact.Count -gt 0) { return $exact }
        # Unknown to Dataverse but still a valid GUID - let the caller use it verbatim.
        return @([pscustomobject]@{ ObjectId = $needle; DisplayName = '(not in directory)'; Upn = ''; Alias = '' })
    }

    foreach ($test in @(
        { param($u) $u.Upn         -ieq $needle },
        { param($u) $u.Alias       -ieq $needle },
        { param($u) $u.DisplayName -ieq $needle },
        { param($u) $u.Upn         -like "*$needle*" },
        { param($u) $u.DisplayName -like "*$needle*" }
    )) {
        $hit = @($dir | Where-Object { & $test $_ })
        if ($hit.Count -gt 0) { return $hit }
    }

    return @()
}

function Get-LocalTimeString {
    <#
        Renders a UTC timestamp in the configured display time zone. Evidence keeps UTC; humans
        get local time, because an administrator reading a report should not have to convert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] $Utc,
        [Parameter(Mandatory = $true)] $Zone
    )

    if ($null -eq $Utc -or [string]::IsNullOrWhiteSpace([string]$Utc)) { return '' }
    try {
        $dt = ([datetime]$Utc).ToUniversalTime()
        return [TimeZoneInfo]::ConvertTimeFromUtc($dt, $Zone).ToString('yyyy-MM-dd HH:mm:ss')
    }
    catch {
        return [string] $Utc
    }
}

# ---------------------------------------------------------------------------------------------
# Retention / inventory probes
# ---------------------------------------------------------------------------------------------
function Get-TranscriptCoverage {
    <#
        Reports the true retention horizon for the environment: oldest surviving transcript,
        newest transcript, and total count. This is deliberately run BEFORE any export so an
        operator never mistakes "everything the export returned" for "everything that ever
        happened". Anything older than the oldest timestamp has already been removed by the
        Dataverse bulk deletion job and is not recoverable by any means.

        Cost is three tiny queries; it does not read transcript content.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $BaseUrl,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $false)][int] $Retries = 5
    )

    $root = "$BaseUrl/api/data/v9.2/conversationtranscripts"

    $oldest = $null
    $newest = $null
    $total  = $null

    try {
        $a = Invoke-DataverseRequest -Uri ("{0}?`$select=conversationstarttime&`$orderby=conversationstarttime asc&`$top=1" -f $root) -Token $Token -Retries $Retries
        if ($a.PSObject.Properties.Name -contains 'value' -and @($a.value).Count -gt 0) { $oldest = $a.value[0].conversationstarttime }

        $b = Invoke-DataverseRequest -Uri ("{0}?`$select=conversationstarttime&`$orderby=conversationstarttime desc&`$top=1" -f $root) -Token $Token -Retries $Retries
        if ($b.PSObject.Properties.Name -contains 'value' -and @($b.value).Count -gt 0) { $newest = $b.value[0].conversationstarttime }

        $c = Invoke-DataverseRequest -Uri ("{0}?`$select=conversationtranscriptid&`$count=true&`$top=1" -f $root) -Token $Token -Retries $Retries
        if ($c.PSObject.Properties.Name -contains '@odata.count') { $total = [int] $c.'@odata.count' }
    }
    catch {
        Write-Log -Level 'WARN' -Message ("Retention probe failed: {0}" -f $_.Exception.Message)
    }

    $spanDays = $null
    if ($oldest -and $newest) {
        try { $spanDays = [int] ([datetime]$newest - [datetime]$oldest).TotalDays } catch { $spanDays = $null }
    }

    $ageDays = $null
    if ($oldest) {
        try { $ageDays = [int] ((Get-Date).ToUniversalTime() - [datetime]$oldest).TotalDays } catch { $ageDays = $null }
    }

    return [pscustomobject]@{
        OldestUtc       = $oldest
        NewestUtc       = $newest
        TotalTranscripts= $total
        SpanDays        = $spanDays
        OldestAgeDays   = $ageDays
    }
}

function Get-AgentInventory {
    <#
        Lists every agent that still has transcripts, with counts and per-agent date ranges.
        Metadata is a JSON column so BotName cannot be grouped server side; the query pulls only
        the two small columns needed and aggregates client side.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $BaseUrl,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $false)][int] $Retries = 5
    )

    $uri  = "$BaseUrl/api/data/v9.2/conversationtranscripts?`$select=metadata,conversationstarttime&`$orderby=conversationstarttime desc"
    $rows = New-Object System.Collections.Generic.List[object]

    while (-not [string]::IsNullOrWhiteSpace($uri)) {
        $resp = Invoke-DataverseRequest -Uri $uri -Token $Token -Retries $Retries
        if ($resp.PSObject.Properties.Name -contains 'value' -and $null -ne $resp.value) {
            foreach ($r in $resp.value) { $rows.Add($r) | Out-Null }
        }
        $uri = ''
        if ($resp.PSObject.Properties.Name -contains '@odata.nextLink') { $uri = [string] $resp.'@odata.nextLink' }
    }

    $byAgent = @{}
    foreach ($r in $rows) {
        $bn = '(unknown)'
        if (-not [string]::IsNullOrWhiteSpace($r.metadata)) {
            try {
                $m = $r.metadata | ConvertFrom-Json
                if ($m.PSObject.Properties.Name -contains 'BotName' -and $m.BotName) { $bn = [string] $m.BotName }
            } catch { }
        }

        if (-not $byAgent.ContainsKey($bn)) {
            $byAgent[$bn] = [pscustomobject]@{ AgentName = $bn; Count = 0; OldestUtc = $null; NewestUtc = $null }
        }

        $e = $byAgent[$bn]
        $e.Count++
        $t = $r.conversationstarttime
        if ($null -eq $e.OldestUtc -or $t -lt $e.OldestUtc) { $e.OldestUtc = $t }
        if ($null -eq $e.NewestUtc -or $t -gt $e.NewestUtc) { $e.NewestUtc = $t }
    }

    return @($byAgent.Values | Sort-Object -Property Count -Descending)
}

# ---------------------------------------------------------------------------------------------
# Transcript parsing
# ---------------------------------------------------------------------------------------------
function ConvertFrom-TranscriptContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Record
    )

    $activities = @()
    if (-not [string]::IsNullOrWhiteSpace($Record.content)) {
        try {
            $parsed = $Record.content | ConvertFrom-Json
            # Content is either a bare activity array or an object with an 'activities' property.
            if ($parsed -is [System.Array]) {
                $activities = $parsed
            }
            elseif ($parsed.PSObject.Properties.Name -contains 'activities') {
                $activities = @($parsed.activities)
            }
        }
        catch {
            Write-Log -Level 'WARN' -Message ("Could not parse content JSON for transcript {0}: {1}" -f $Record.conversationtranscriptid, $_.Exception.Message)
        }
    }

    $botName  = '(unknown)'
    $botId    = ''
    $batchId  = 0
    if (-not [string]::IsNullOrWhiteSpace($Record.metadata)) {
        try {
            $meta    = $Record.metadata | ConvertFrom-Json
            if ($meta.PSObject.Properties.Name -contains 'BotName') { $botName = $meta.BotName }
            if ($meta.PSObject.Properties.Name -contains 'BotId')   { $botId   = $meta.BotId }
            if ($meta.PSObject.Properties.Name -contains 'BatchId') { $batchId = [int] $meta.BatchId }
        }
        catch {
            Write-Log -Level 'WARN' -Message ("Could not parse metadata JSON for transcript {0}." -f $Record.conversationtranscriptid)
        }
    }

    return [pscustomobject]@{
        TranscriptId  = $Record.conversationtranscriptid
        Name          = $Record.name
        StartTimeUtc  = $Record.conversationstarttime
        BotName       = $botName
        BotId         = $botId
        BatchId       = $batchId
        Activities    = $activities
    }
}

function ConvertTo-UtcDateTime {
    <#
        Parses any timestamp shape the transcript stream produces (ISO 8601 string, offset string,
        or numeric epoch) into a real [datetime] in UTC. Returns $null when the value is missing or
        unparseable. Sorting MUST use this rather than raw strings: transcript rows mix formats, and
        lexical string comparison silently mis-orders them.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] $Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime() }

    $s = [string] $Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }

    $epoch = 0.0
    if ([double]::TryParse($s, [ref] $epoch)) {
        if ($epoch -gt 100000000000) { $epoch = $epoch / 1000 }
        try { return ([datetimeoffset]::FromUnixTimeSeconds([int64] $epoch)).UtcDateTime } catch { return $null }
    }

    $dto = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse($s, [ref] $dto)) { return $dto.UtcDateTime }

    $dt = [datetime]::MinValue
    if ([datetime]::TryParse($s, [ref] $dt)) { return $dt.ToUniversalTime() }

    return $null
}

function Get-TranscriptTurns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Activities
    )

    $turns = New-Object System.Collections.Generic.List[object]

    foreach ($a in $Activities) {
        if ($null -eq $a) { continue }
        if (($a.PSObject.Properties.Name -notcontains 'type') -or ($a.type -ne 'message')) { continue }

        $text = ''
        if ($a.PSObject.Properties.Name -contains 'text' -and $null -ne $a.text) { $text = [string] $a.text }
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $role  = 'AGENT'
        $aadId = ''
        if ($a.PSObject.Properties.Name -contains 'from' -and $null -ne $a.from) {
            if ($a.from.PSObject.Properties.Name -contains 'role' -and $a.from.role -eq 1) { $role = 'USER' }
            if ($a.from.PSObject.Properties.Name -contains 'aadObjectId' -and $null -ne $a.from.aadObjectId) {
                $aadId = [string] $a.from.aadObjectId
            }
        }

        $tsUtc = ''
        if ($a.PSObject.Properties.Name -contains 'timestamp' -and $null -ne $a.timestamp) {
            $rawTs = $a.timestamp
            if ($rawTs -is [string]) {
                $tsUtc = $rawTs
            }
            else {
                # Numeric epoch. Copilot Studio emits seconds; guard against millisecond values.
                $epoch = [double] $rawTs
                if ($epoch -gt 100000000000) { $epoch = $epoch / 1000 }
                $tsUtc = ([datetimeoffset]::FromUnixTimeSeconds([int64] $epoch)).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
        }

        $turns.Add([pscustomobject]@{
            Role          = $role
            AadObjectId   = $aadId
            TimestampUtc  = $tsUtc
            SortUtc       = (ConvertTo-UtcDateTime $tsUtc)
            Seq           = $turns.Count
            Text          = $text
        }) | Out-Null
    }

    # Turns must always read oldest -> newest so the exchange reproduces the order it happened in.
    # Sort on the parsed datetime, never the raw string. Turns with no usable timestamp keep their
    # original stream position via Seq, which is also the tie-breaker for identical timestamps
    # (Copilot Studio frequently stamps a prompt and its answer to the same second).
    $anchor  = [datetime]::MaxValue
    $sorted  = @($turns | Sort-Object -Property @{ Expression = { if ($null -ne $_.SortUtc) { $_.SortUtc } else { $anchor } } }, @{ Expression = { $_.Seq } })

    # Return a plain array. Do NOT comma-wrap: the caller wraps in @(), and ,$arr + @() would
    # collapse the result to a single element and silently lose every turn but one.
    return $sorted
}

function Get-TranscriptTraces {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Activities
    )

    $traces = New-Object System.Collections.Generic.List[object]

    foreach ($a in $Activities) {
        if ($null -eq $a) { continue }
        if (($a.PSObject.Properties.Name -notcontains 'type') -or ($a.type -ne 'trace')) { continue }

        $vt = ''
        if ($a.PSObject.Properties.Name -contains 'valueType' -and $null -ne $a.valueType) { $vt = [string] $a.valueType }

        $traces.Add([pscustomobject]@{
            ValueType = $vt
            Value     = $(if ($a.PSObject.Properties.Name -contains 'value') { $a.value } else { $null })
        }) | Out-Null
    }

    return $traces.ToArray()
}

function Get-OrchestrationSummary {
    <#
        Derives reviewer-facing signals from the trace stream: which tools / connectors / MCP
        servers the agent invoked, whether it consulted knowledge sources, and whether the turn
        errored. None of this is available from Purview Audit or DSPM.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Activities
    )

    $tools      = New-Object System.Collections.Generic.List[string]
    $hadError   = $false
    $usedKnow   = $false
    $planSteps  = 0

    foreach ($a in $Activities) {
        if ($null -eq $a) { continue }
        if (($a.PSObject.Properties.Name -notcontains 'type') -or ($a.type -ne 'trace')) { continue }

        $vt = ''
        if ($a.PSObject.Properties.Name -contains 'valueType' -and $null -ne $a.valueType) { $vt = [string] $a.valueType }

        switch -Wildcard ($vt) {
            'ErrorTraceData'           { $hadError = $true }
            'KnowledgeTraceData'       { $usedKnow = $true }
            'DynamicPlanStepTriggered' { $planSteps++ }
        }

        # Tool / connector / MCP names appear under a few different value shapes depending on
        # the orchestration version, so probe the common ones defensively.
        if ($a.PSObject.Properties.Name -contains 'value' -and $null -ne $a.value) {
            foreach ($prop in 'toolName', 'name', 'actionName', 'stepName', 'displayName') {
                if ($a.value.PSObject.Properties.Name -contains $prop) {
                    $candidate = [string] $a.value.$prop
                    if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $tools.Contains($candidate)) {
                        $tools.Add($candidate) | Out-Null
                    }
                }
            }
        }

        if ($a.PSObject.Properties.Name -contains 'name' -and $null -ne $a.name) {
            $candidate = [string] $a.name
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not $tools.Contains($candidate)) {
                $tools.Add($candidate) | Out-Null
            }
        }
    }

    return [pscustomobject]@{
        Tools             = $tools.ToArray()
        ToolsDisplay      = ($tools.ToArray() -join ', ')
        HadError          = $hadError
        UsedKnowledge     = $usedKnow
        PlanStepCount     = $planSteps
    }
}

function ConvertTo-SafeHtml {
    param([string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $s = $Text -replace '&', '&amp;'
    $s = $s -replace '<', '&lt;'
    $s = $s -replace '>', '&gt;'
    $s = $s -replace '"', '&quot;'
    return $s
}

function Get-DisplayText {
    <#
        Copilot Studio agents are frequently driven by very large machine-generated prompts
        (for example a full HTML email pasted into an autonomous trigger). Rendering those raw
        makes a report unusable, so collapse obvious markup and whitespace noise for display
        while the untouched original stays in the JSON export.
    #>
    param([string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $s = $Text

    # Strip script/style blocks entirely, then remaining tags, then decode the few entities
    # that dominate machine-generated email bodies.
    $s = [regex]::Replace($s, '(?is)<(script|style)\b.*?</\1>', ' ')
    $s = [regex]::Replace($s, '(?is)<!--.*?-->', ' ')
    $s = [regex]::Replace($s, '(?is)<[^>]+>', ' ')
    $s = $s -replace '&nbsp;', ' '
    $s = $s -replace '&amp;', '&'
    $s = $s -replace '&quot;', '"'
    $s = $s -replace '&#39;', "'"
    $s = $s -replace '&lt;', '<'
    $s = $s -replace '&gt;', '>'

    # Collapse runs of whitespace but keep paragraph breaks readable.
    $s = [regex]::Replace($s, '[ \t]+', ' ')
    $s = [regex]::Replace($s, '(\r?\n\s*){3,}', "`n`n")

    return $s.Trim()
}

function Get-Excerpt {
    param(
        [string] $Text,
        [int] $Max = 600
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $flat = [regex]::Replace($Text, '\s+', ' ').Trim()
    if ($flat.Length -le $Max) { return $flat }
    return $flat.Substring(0, $Max) + ' ...'
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------
$runStart = Get-Date
Write-Log -Level 'STEP' -Message '--- Copilot Studio transcript export starting ---'
Write-Log -Message ("Auth method  : {0}" -f $AuthMethod)
Write-Log -Message ("Target tenant: {0}" -f $(if ([string]::IsNullOrWhiteSpace($TenantId)) { '(not specified - supply -TenantId for cross-tenant environments)' } else { $TenantId }))

# -----------------------------------------------------------------------------------------
# Environment resolution. When no URL is supplied, ask the Global Discovery Service which
# environments this identity can reach. An administrator should not have to know the Dataverse
# URL, which is not surfaced anywhere obvious in Copilot Studio.
# -----------------------------------------------------------------------------------------
$discoveredEnvs = $null

if ([string]::IsNullOrWhiteSpace($EnvironmentUrl) -or $ListEnvironments) {

    Write-Log -Level 'STEP' -Message 'No environment URL supplied - discovering Dataverse environments for this identity ...'

    try {
        $discoToken = Get-DataverseToken -Resource 'https://globaldisco.crm.dynamics.com' -SuppliedToken $AccessToken -Tenant $TenantId -Method $AuthMethod
    }
    catch {
        Write-Log -Level 'ERROR' -Message $_.Exception.Message
        return
    }

    try {
        # Wrap in @() so a single-environment result still exposes .Count under Set-StrictMode.
        $discoveredEnvs = @(Get-DataverseEnvironments -Token $discoToken)
    }
    catch {
        Write-Log -Level 'ERROR' -Message $_.Exception.Message
        Write-Log -Message 'If discovery is blocked, supply the URL directly with -EnvironmentUrl. You can copy it from the Power Platform admin center: Environments > <your environment> > Environment URL.'
        return
    }

    if ($discoveredEnvs.Count -eq 0) {
        Write-Log -Level 'ERROR' -Message 'No Dataverse environments are visible to this identity. A Global Administrator is not automatically a Dataverse user - add the account as a user in the target environment, or supply -EnvironmentUrl directly.'
        return
    }

    Write-Host ''
    Write-Host '  -------------------------------------------------------------------' -ForegroundColor Cyan
    Write-Host '   DATAVERSE ENVIRONMENTS VISIBLE TO THIS IDENTITY' -ForegroundColor Cyan
    Write-Host '  -------------------------------------------------------------------' -ForegroundColor Cyan
    Write-Host ('   {0,-34} {1,-16} {2}' -f 'FRIENDLY NAME', 'URL NAME', 'ENVIRONMENT URL') -ForegroundColor DarkGray
    foreach ($e in $discoveredEnvs) {
        Write-Host ('   {0,-34} {1,-16} {2}' -f $e.FriendlyName, $e.UrlName, $e.Url)
    }
    Write-Host '  -------------------------------------------------------------------' -ForegroundColor Cyan
    Write-Host ''

    if ($ListEnvironments) {
        Write-Host '   Listing only - nothing was queried or exported.' -ForegroundColor Yellow
        Write-Host '   Re-run with -EnvironmentUrl <url>, or with -EnvironmentName to select by name.' -ForegroundColor Yellow
        Write-Host ''
        Write-Log -Level 'STEP' -Message '--- Environment listing complete. No files written. ---'
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
        $match = @($discoveredEnvs | Where-Object {
            $_.FriendlyName -like "*$EnvironmentName*" -or $_.UrlName -like "*$EnvironmentName*"
        })
        if ($match.Count -eq 0) {
            Write-Log -Level 'ERROR' -Message ("No environment matched -EnvironmentName '{0}'. See the list above." -f $EnvironmentName)
            return
        }
        if ($match.Count -gt 1) {
            Write-Log -Level 'ERROR' -Message ("-EnvironmentName '{0}' matched {1} environments. Use a more specific name or pass -EnvironmentUrl." -f $EnvironmentName, $match.Count)
            return
        }
        $EnvironmentUrl = $match[0].Url
        Write-Log -Level 'OK' -Message ("Selected by name: {0} -> {1}" -f $match[0].FriendlyName, $EnvironmentUrl)
    }
    elseif ($discoveredEnvs.Count -eq 1) {
        $EnvironmentUrl = $discoveredEnvs[0].Url
        Write-Log -Level 'OK' -Message ("Exactly one environment found; selected automatically: {0} -> {1}" -f $discoveredEnvs[0].FriendlyName, $EnvironmentUrl)
    }
    else {
        Write-Log -Level 'ERROR' -Message ("{0} environments found. Re-run with -EnvironmentName '<friendly or url name>' or -EnvironmentUrl <url> to choose one." -f $discoveredEnvs.Count)
        return
    }
}

Write-Log -Message ("Environment  : {0}" -f $EnvironmentUrl)
Write-Log -Message ("Window (UTC) : {0} to {1}" -f $StartDateUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'), $EndDateUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'))
Write-Log -Message ("Agent filter : {0}" -f $(if ([string]::IsNullOrWhiteSpace($AgentName)) { '(all agents)' } else { $AgentName }))
Write-Log -Message ("User filter  : {0}" -f $(if ([string]::IsNullOrWhiteSpace($User) -and [string]::IsNullOrWhiteSpace($UserObjectId)) { '(all users)' } elseif (-not [string]::IsNullOrWhiteSpace($User)) { $User } else { $UserObjectId }))
Write-Log -Message ("Output       : {0} (format: {1})" -f $OutputFolder, $Format)

try {
    $token = Get-DataverseToken -Resource $EnvironmentUrl -SuppliedToken $AccessToken -Tenant $TenantId -Method $AuthMethod
}
catch {
    Write-Log -Level 'ERROR' -Message $_.Exception.Message
    return
}

$startIso = $StartDateUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
$endIso   = $EndDateUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')

# -----------------------------------------------------------------------------------------
# Directory resolution. Administrators know agents by the friendly name in the Agent Registry
# and users by alias or UPN - not by GUID or Dataverse schema name. Both directories come from
# the same Dataverse token, so no Microsoft Graph consent is required.
# -----------------------------------------------------------------------------------------
Write-Log -Level 'STEP' -Message 'Reading agent and user directories for friendly-name resolution ...'
$botDir  = Get-BotDirectory  -BaseUrl $EnvironmentUrl -Token $token -Retries $MaxRetries
$userDir = @(Get-UserDirectory -BaseUrl $EnvironmentUrl -Token $token -Retries $MaxRetries)
Write-Log -Message ("Directory: {0} agent record(s), {1} user record(s) with an Entra object ID." -f [int]($botDir.Count / 2), $userDir.Count)

# Resolve the user filter to one or more object IDs, and show who matched.
$resolvedUserIds = @()
$userSeed = if (-not [string]::IsNullOrWhiteSpace($User)) { $User } else { $UserObjectId }

if (-not [string]::IsNullOrWhiteSpace($userSeed)) {
    $hits = @(Resolve-UserIdentifier -Value $userSeed -Directory $userDir)

    if ($hits.Count -eq 0) {
        Write-Log -Level 'ERROR' -Message ("No directory user matched '{0}'. Try the alias, the full user principal name, the display name, or the Entra object GUID. The GUID is on the user's Entra profile under Properties > Identity > Object ID." -f $userSeed)
        return
    }

    if ($hits.Count -gt 1) {
        Write-Log -Level 'ERROR' -Message ("'{0}' matched {1} users. Be more specific:" -f $userSeed, $hits.Count)
        foreach ($h in $hits) { Write-Host ("     {0,-28} {1,-46} {2}" -f $h.DisplayName, $h.Upn, $h.ObjectId) }
        return
    }

    $resolvedUserIds = @($hits[0].ObjectId)
    Write-Log -Level 'OK' -Message ("User filter resolved: '{0}' -> {1} ({2}) object ID {3}" -f $userSeed, $hits[0].DisplayName, $hits[0].Upn, $hits[0].ObjectId)
}

# Display time zone for all human-readable timestamps.
try {
    $displayZone = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)
}
catch {
    Write-Log -Level 'WARN' -Message ("Unknown time zone '{0}'; falling back to Eastern Standard Time." -f $TimeZoneId)
    $displayZone = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')
    $TimeZoneId  = 'Eastern Standard Time'
}
$zoneAbbrev = if ($displayZone.IsDaylightSavingTime([datetime]::UtcNow)) { $displayZone.DaylightName } else { $displayZone.StandardName }
# Generic, DST-agnostic label. An export can span both standard and daylight time, so stamping the
# whole report "Eastern Standard Time" while individual rows fall in daylight time is misleading.
$zoneLabel  = ($displayZone.StandardName -replace '\s*Standard Time$', ' Time')
if ([string]::IsNullOrWhiteSpace($zoneLabel)) { $zoneLabel = $TimeZoneId }
Write-Log -Message ("Display time zone: {0}" -f $TimeZoneId)

# -----------------------------------------------------------------------------------------
# Retention horizon probe - always runs, so the operator knows what is actually recoverable
# before interpreting any export as complete.
# -----------------------------------------------------------------------------------------
Write-Log -Level 'STEP' -Message 'Probing retention horizon (how far back transcripts still exist) ...'
$coverage = Get-TranscriptCoverage -BaseUrl $EnvironmentUrl -Token $token -Retries $MaxRetries

if ($null -eq $coverage.OldestUtc) {
    Write-Log -Level 'WARN' -Message 'No transcripts exist in this environment at all. Verify transcript recording is enabled, the environment is correct, and the agent type is supported.'
    return
}

Write-Host ''
Write-Host '  -------------------------------------------------------------------' -ForegroundColor Cyan
Write-Host '   RETENTION HORIZON - what this environment can still produce' -ForegroundColor Cyan
Write-Host '  -------------------------------------------------------------------' -ForegroundColor Cyan
Write-Host ("   Oldest transcript : {0}   ({1})" -f (Get-LocalTimeString -Utc $coverage.OldestUtc -Zone $displayZone), "$($coverage.OldestAgeDays) day(s) old") -ForegroundColor White
Write-Host ("   Newest transcript : {0}" -f (Get-LocalTimeString -Utc $coverage.NewestUtc -Zone $displayZone)) -ForegroundColor White
Write-Host ("   Times shown in    : {0}" -f $zoneAbbrev) -ForegroundColor DarkGray
Write-Host ("   Total transcripts : {0}" -f $coverage.TotalTranscripts) -ForegroundColor White
Write-Host ("   Recoverable span  : {0} day(s)" -f $coverage.SpanDays) -ForegroundColor White
Write-Host '   Anything older than the oldest timestamp has already been purged by the' -ForegroundColor DarkGray
Write-Host '   Dataverse bulk deletion job and cannot be recovered by any tool.' -ForegroundColor DarkGray
Write-Host '  -------------------------------------------------------------------' -ForegroundColor Cyan
Write-Host ''

Write-Log -Message ("Retention: oldest {0}, newest {1}, total {2}, span {3} day(s)." -f $coverage.OldestUtc, $coverage.NewestUtc, $coverage.TotalTranscripts, $coverage.SpanDays)

if ($Discover) {
    Write-Log -Level 'STEP' -Message 'Building per-agent inventory ...'
    $inventory = Get-AgentInventory -BaseUrl $EnvironmentUrl -Token $token -Retries $MaxRetries

    Write-Host '   Transcripts by agent (name as shown in the Agent Registry):' -ForegroundColor White
    Write-Host ('   {0,-40} {1,6}  {2,-21} {3}' -f 'AGENT', 'COUNT', "OLDEST ($zoneAbbrev)", "NEWEST ($zoneAbbrev)") -ForegroundColor DarkGray
    foreach ($a in $inventory) {
        $friendly = $a.AgentName
        $key = $a.AgentName.ToLowerInvariant()
        if ($botDir.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($botDir[$key].DisplayName)) {
            $friendly = $botDir[$key].DisplayName
        }
        Write-Host ('   {0,-40} {1,6}  {2,-21} {3}' -f $friendly, $a.Count,
            (Get-LocalTimeString -Utc $a.OldestUtc -Zone $displayZone),
            (Get-LocalTimeString -Utc $a.NewestUtc -Zone $displayZone))
    }
    Write-Host ''
    Write-Host '   Use any of those names with -AgentName to scope an export, for example:' -ForegroundColor DarkGray
    Write-Host '     -AgentName ''MCP Enterprise Admin Assistant''' -ForegroundColor DarkGray
    Write-Host '   Scope by person with -User, using an alias, UPN, display name or object GUID:' -ForegroundColor DarkGray
    Write-Host '     -User AdilE     -User AdilE@contoso.onmicrosoft.com     -User ''Adil Eli''' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   Discovery only - nothing was exported. Re-run without -Discover to export,' -ForegroundColor Yellow
    Write-Host '   and add -AllHistory to capture the full recoverable span shown above.' -ForegroundColor Yellow
    Write-Host ''
    Write-Log -Level 'STEP' -Message '--- Discovery complete. No files written. ---'
    return
}

# Honor -AllHistory by pulling the lower bound back to the oldest surviving record.
if ($AllHistory) {
    $startIso = ([datetime]$coverage.OldestUtc).ToUniversalTime().AddSeconds(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Log -Level 'OK' -Message ("-AllHistory: window start pulled back to the oldest surviving transcript ({0})." -f $startIso)
}
elseif ([datetime]$startIso -lt [datetime]$coverage.OldestUtc) {
    Write-Log -Level 'WARN' -Message ("Requested start {0} is EARLIER than the oldest surviving transcript {1}. No data exists before that point - it was purged by the retention job, not missed by this query." -f $startIso, $coverage.OldestUtc)
}

$windowLabel = if ($AllHistory) { "$startIso to $endIso (all retained history)" } else { "$startIso to $endIso" }

$select = 'conversationtranscriptid,name,conversationstarttime,content,metadata,schematype,createdon'
$filter = "conversationstarttime ge $startIso and conversationstarttime lt $endIso"
$uri    = "$EnvironmentUrl/api/data/v9.2/conversationtranscripts?`$select=$select&`$filter=$filter&`$orderby=conversationstarttime desc"

Write-Log -Level 'STEP' -Message 'Querying Dataverse conversationtranscripts ...'

$rawRecords = New-Object System.Collections.Generic.List[object]
$page = 0

try {
    while (-not [string]::IsNullOrWhiteSpace($uri)) {
        $page++
        $response = Invoke-DataverseRequest -Uri $uri -Token $token -Retries $MaxRetries

        if ($response.PSObject.Properties.Name -contains 'value' -and $null -ne $response.value) {
            foreach ($r in $response.value) { $rawRecords.Add($r) | Out-Null }
        }

        Write-Log -Message ("Page {0}: cumulative rows = {1}" -f $page, $rawRecords.Count)

        $uri = ''
        if ($response.PSObject.Properties.Name -contains '@odata.nextLink') {
            $uri = [string] $response.'@odata.nextLink'
        }
    }
}
catch {
    Write-Log -Level 'ERROR' -Message $_.Exception.Message
    return
}

Write-Log -Level 'OK' -Message ("Retrieved {0} raw transcript row(s)." -f $rawRecords.Count)

if ($rawRecords.Count -eq 0) {
    Write-Log -Level 'WARN' -Message 'No transcripts found. Verify: correct environment, transcript recording enabled, agent is not a Dataverse for Teams or Microsoft 365 Copilot agent, and the bulk deletion retention job has not already purged the window.'
    return
}

# Parse and merge multi-part rows (records over 1 MB are split, sharing the same Name).
$parsed = @(foreach ($r in $rawRecords) { ConvertFrom-TranscriptContent -Record $r })

$merged = New-Object System.Collections.Generic.List[object]
foreach ($grp in ($parsed | Group-Object -Property Name)) {
    # Wrap in @() so a single-item group is still an array under Set-StrictMode.
    $ordered   = @($grp.Group | Sort-Object -Property BatchId)
    $head      = $ordered[0]
    $allActs   = New-Object System.Collections.Generic.List[object]
    foreach ($part in $ordered) {
        foreach ($a in $part.Activities) { $allActs.Add($a) | Out-Null }
    }

    if ($ordered.Count -gt 1) {
        Write-Log -Message ("Merged {0} split part(s) for conversation {1}." -f $ordered.Count, $head.Name)
    }

    $merged.Add([pscustomobject]@{
        TranscriptId = $head.TranscriptId
        Name         = $head.Name
        StartTimeUtc = $head.StartTimeUtc
        BotName      = $head.BotName
        BotId        = $head.BotId
        Activities   = $allActs
    }) | Out-Null
}

Write-Log -Level 'OK' -Message ("{0} distinct conversation(s) after merge." -f $merged.Count)

# Apply client-side filters.
# Apply client-side filters. Agent and user identity live inside JSON columns, so Dataverse
# cannot filter on them server side; the date window above already bounded the download.
$normalize = { param($s) if ([string]::IsNullOrWhiteSpace($s)) { '' } else { ($s -replace '[\s_\-]', '').ToLowerInvariant() } }
$agentNeedle = & $normalize $AgentName

$conversations = New-Object System.Collections.Generic.List[object]
foreach ($c in $merged) {

    # Resolve the agent's friendly display name from the bot directory, keyed by BotId first
    # (most reliable) then by schema name.
    $agentDisplay = $c.BotName
    foreach ($k in @($c.BotId, $c.BotName)) {
        if ([string]::IsNullOrWhiteSpace($k)) { continue }
        $kk = $k.ToLowerInvariant()
        if ($botDir.ContainsKey($kk) -and -not [string]::IsNullOrWhiteSpace($botDir[$kk].DisplayName)) {
            $agentDisplay = $botDir[$kk].DisplayName
            break
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($agentNeedle)) {
        # Match against the friendly name OR the raw schema name, ignoring spaces, underscores
        # and hyphens, so a name copied from the Agent Registry works as-is.
        $hayFriendly = & $normalize $agentDisplay
        $haySchema   = & $normalize $c.BotName
        if (($hayFriendly -notlike "*$agentNeedle*") -and ($haySchema -notlike "*$agentNeedle*")) { continue }
    }

    $turns = @(Get-TranscriptTurns -Activities $c.Activities)
    if ($turns.Count -eq 0) { continue }

    if ($resolvedUserIds.Count -gt 0) {
        $match = @($turns | Where-Object { $resolvedUserIds -contains $_.AadObjectId })
        if ($match.Count -eq 0) { continue }
    }

    # Collect distinct user object IDs defensively; -ExpandProperty throws on an empty set
    # when ErrorActionPreference is Stop.
    $userTurns    = @($turns | Where-Object { $_.Role -eq 'USER' })
    $participants = @()
    if ($userTurns.Count -gt 0) {
        $ids = New-Object System.Collections.Generic.List[string]
        foreach ($t in $userTurns) {
            if (-not [string]::IsNullOrWhiteSpace($t.AadObjectId) -and -not $ids.Contains($t.AadObjectId)) {
                $ids.Add($t.AadObjectId) | Out-Null
            }
        }
        $participants = @($ids.ToArray())
    }

    # Resolve each participant object ID to a display name and UPN for the report.
    # NOTE: do not name this loop variable $pid - that is a read-only PowerShell automatic
    # variable holding the process ID, and assigning to it throws.
    $participantInfo = New-Object System.Collections.Generic.List[object]
    foreach ($partId in $participants) {
        $u = @($userDir | Where-Object { $_.ObjectId -eq $partId }) | Select-Object -First 1
        $participantInfo.Add([pscustomobject]@{
            ObjectId    = $partId
            DisplayName = $(if ($u) { $u.DisplayName } else { '(not in directory)' })
            Upn         = $(if ($u) { $u.Upn } else { '' })
        }) | Out-Null
    }
    $participantLabel = (($participantInfo | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_.Upn)) { $_.ObjectId } else { "$($_.DisplayName) <$($_.Upn)>" }
    }) -join '; ')

    $orch = Get-OrchestrationSummary -Activities $c.Activities

    # Effective chronological key. Prefer the conversationstarttime column, but fall back to the
    # first turn's timestamp when that column is absent or unparseable on a merged multi-part row.
    # Sorting on a real [datetime] is what fixes the interleaved-date ordering seen when the raw
    # OData order was trusted.
    $sortKey = ConvertTo-UtcDateTime $c.StartTimeUtc
    if ($null -eq $sortKey) {
        $firstStamped = @($turns | Where-Object { $null -ne $_.SortUtc }) | Select-Object -First 1
        if ($firstStamped) { $sortKey = $firstStamped.SortUtc }
    }

    $conversations.Add([pscustomobject]@{
        TranscriptId     = $c.TranscriptId
        ConversationId   = ($c.Name -split '_')[0]
        Name             = $c.Name
        StartTimeUtc     = $c.StartTimeUtc
        SortKeyUtc       = $sortKey
        StartTimeLocal   = (Get-LocalTimeString -Utc $c.StartTimeUtc -Zone $displayZone)
        AgentDisplayName = $agentDisplay
        BotName          = $c.BotName
        BotId            = $c.BotId
        UserObjectIds    = $participants
        Participants     = $participantInfo.ToArray()
        ParticipantLabel = $participantLabel
        TurnCount        = $turns.Count
        UserTurnCount    = $userTurns.Count
        HadError         = $orch.HadError
        UsedKnowledge    = $orch.UsedKnowledge
        PlanStepCount    = $orch.PlanStepCount
        ToolsInvoked     = $orch.ToolsDisplay
        Turns            = $turns
        Traces           = $(if ($IncludeTraces) { @(Get-TranscriptTraces -Activities $c.Activities) } else { @() })
    }) | Out-Null
}

Write-Log -Level 'OK' -Message ("{0} conversation(s) match the supplied filters." -f $conversations.Count)

# Deterministic chronological ordering. The Dataverse $orderby alone is not trustworthy here:
# multi-part transcripts are re-grouped during the merge, and conversationstarttime is a string on
# the wire. Re-sort explicitly on the parsed datetime so the report always reads in true
# chronological order. Conversations that carry no usable timestamp sort to the end regardless of
# direction, with the conversation name as a stable tie-breaker so repeat runs are byte-comparable.
$unstamped = 0
$sortAnchorNew = [datetime]::MinValue
$sortAnchorOld = [datetime]::MaxValue
foreach ($c in $conversations) { if ($null -eq $c.SortKeyUtc) { $unstamped++ } }

if ($SortOrder -eq 'Oldest') {
    $conversations = [System.Collections.Generic.List[object]] @(
        $conversations | Sort-Object -Property `
            @{ Expression = { if ($null -ne $_.SortKeyUtc) { $_.SortKeyUtc } else { $sortAnchorOld } } }, `
            @{ Expression = { $_.Name } }
    )
}
else {
    $conversations = [System.Collections.Generic.List[object]] @(
        $conversations | Sort-Object -Property `
            @{ Expression = { if ($null -ne $_.SortKeyUtc) { $_.SortKeyUtc } else { $sortAnchorNew } }; Descending = $true }, `
            @{ Expression = { $_.Name }; Descending = $false }
    )
}

Write-Log -Message ("Sort order      : conversations {0} first; turns always oldest -> newest within a conversation." -f $SortOrder.ToLowerInvariant())
if ($unstamped -gt 0) {
    Write-Log -Level 'WARN' -Message ("{0} conversation(s) carry no parseable start timestamp and were placed at the end of the ordering." -f $unstamped)
}

# Integrity self-check: a transcript with only one recoverable turn is possible, but if EVERY
# conversation reports exactly one turn that indicates a parsing or collection-flattening bug,
# not real data. Fail loudly rather than shipping a silently truncated export.
$totalTurns = ($conversations | Measure-Object -Property TurnCount -Sum).Sum
$maxTurns   = ($conversations | Measure-Object -Property TurnCount -Maximum).Maximum
Write-Log -Message ("Turn integrity  : {0} total turn(s) across {1} conversation(s); max {2} in a single conversation." -f $totalTurns, $conversations.Count, $maxTurns)

if ($conversations.Count -gt 3 -and $maxTurns -le 1) {
    Write-Log -Level 'ERROR' -Message 'Integrity check failed: every conversation reported a single turn. This indicates a transcript parsing or array-flattening defect, not real data. Aborting rather than writing a truncated export.'
    return
}

if ($conversations.Count -eq 0) {
    Write-Log -Level 'WARN' -Message 'Nothing to export after filtering. Relax -AgentName or -UserObjectId, or widen the date window.'
    return
}

$agentSummary = @($conversations | Group-Object -Property AgentDisplayName | Sort-Object -Property Count -Descending)
Write-Log -Level 'STEP' -Message 'Conversations by agent:'
foreach ($g in $agentSummary) {
    Write-Log -Message ("  {0,-45} {1}" -f $g.Name, $g.Count)
}

# ---------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------
$stampSuffix = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$utf8Bom     = New-Object System.Text.UTF8Encoding($true)

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    if ($PSCmdlet.ShouldProcess($OutputFolder, 'Create output folder')) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
        Write-Log -Level 'OK' -Message "Created output folder: $OutputFolder"
    }
}

$wantJson = ($Format -eq 'Json' -or $Format -eq 'All')
$wantCsv  = ($Format -eq 'Csv'  -or $Format -eq 'All')
$wantHtml = ($Format -eq 'Html' -or $Format -eq 'All')

$written = New-Object System.Collections.Generic.List[string]

if ($wantJson) {
    $jsonPath = Join-Path $OutputFolder ("CopilotStudio-Transcripts-{0}.json" -f $stampSuffix)
    if ($PSCmdlet.ShouldProcess($jsonPath, 'Write JSON transcript export')) {
        $payload = [pscustomobject]@{
            GeneratedUtc     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            EnvironmentUrl   = $EnvironmentUrl
            WindowStartUtc   = $startIso
            WindowEndUtc     = $endIso
            AgentFilter      = $AgentName
            UserFilter       = $UserObjectId
            ConversationCount= $conversations.Count
            SortOrder        = ("Conversations {0} first by start time; turns oldest to newest within each conversation." -f $SortOrder.ToLowerInvariant())
            DisplayTimeZone  = $TimeZoneId
            SourceOfTruth    = 'Dataverse conversationtranscript table (Copilot Studio agent conversation content)'
            AuditJoinKey     = 'Purview Audit UserKey / UserId equals transcript turn AadObjectId'
            Conversations    = $conversations
        }
        $json = $payload | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($jsonPath, $json, $utf8Bom)
        $written.Add($jsonPath) | Out-Null
        Write-Log -Level 'OK' -Message "JSON written: $jsonPath"
    }
}

if ($wantCsv) {
    $csvPath = Join-Path $OutputFolder ("CopilotStudio-Turns-{0}.csv" -f $stampSuffix)
    if ($PSCmdlet.ShouldProcess($csvPath, 'Write CSV turn-level export')) {
        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($c in $conversations) {
            $i = 0
            foreach ($t in $c.Turns) {
                $i++
                $clean = Get-DisplayText $t.Text
                $u = @($userDir | Where-Object { $_.ObjectId -eq $t.AadObjectId }) | Select-Object -First 1
                $rows.Add([pscustomobject]@{
                    ConversationId  = $c.ConversationId
                    TranscriptId    = $c.TranscriptId
                    AgentName       = $c.AgentDisplayName
                    AgentSchemaName = $c.BotName
                    AgentId         = $c.BotId
                    StartTimeLocal  = $c.StartTimeLocal
                    StartTimeUtc    = $c.StartTimeUtc
                    TurnNumber      = $i
                    Role            = $t.Role
                    TimestampLocal  = (Get-LocalTimeString -Utc $t.TimestampUtc -Zone $displayZone)
                    TimestampUtc    = $t.TimestampUtc
                    UserDisplayName = $(if ($u) { $u.DisplayName } else { '' })
                    UserUpn         = $(if ($u) { $u.Upn } else { '' })
                    UserObjectId    = $t.AadObjectId
                    CharCount       = $clean.Length
                    Excerpt         = (Get-Excerpt $clean 300)
                    Text            = ($clean -replace "`r`n", ' ' -replace "`n", ' ')
                }) | Out-Null
            }
        }

        $csvText = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
        [System.IO.File]::WriteAllText($csvPath, $csvText, $utf8Bom)
        $written.Add($csvPath) | Out-Null
        Write-Log -Level 'OK' -Message ("CSV written: {0} ({1} turn row(s))" -f $csvPath, $rows.Count)
    }
}

if ($wantHtml) {
    $htmlPath = Join-Path $OutputFolder ("CopilotStudio-Transcripts-{0}.html" -f $stampSuffix)
    if ($PSCmdlet.ShouldProcess($htmlPath, 'Write HTML review packet')) {

        $agentNames    = @($conversations | Select-Object -ExpandProperty AgentDisplayName -Unique | Sort-Object)
        $agentOptions  = ($agentNames | ForEach-Object { "<option value=""$(ConvertTo-SafeHtml $_)"">$(ConvertTo-SafeHtml $_)</option>" }) -join ''
        $allParts      = @($conversations | ForEach-Object { $_.Participants } | Where-Object { $_ })
        $userIds       = @($allParts | Select-Object -ExpandProperty ObjectId -Unique | Sort-Object)
        $userOptions   = ($userIds | ForEach-Object {
            $oid = $_
            $p = @($allParts | Where-Object { $_.ObjectId -eq $oid }) | Select-Object -First 1
            $lbl = if ($p -and -not [string]::IsNullOrWhiteSpace($p.Upn)) { "$($p.DisplayName) - $($p.Upn)" } else { $oid }
            "<option value=""$(ConvertTo-SafeHtml $oid)"">$(ConvertTo-SafeHtml $lbl)</option>"
        }) -join ''
        $errorCount    = @($conversations | Where-Object { $_.HadError }).Count
        $knowledgeCnt  = @($conversations | Where-Object { $_.UsedKnowledge }).Count
        $userCount     = $userIds.Count
        $turnTotal     = ($conversations | Measure-Object -Property TurnCount -Sum).Sum
        $generatedLcl  = (Get-LocalTimeString -Utc ([datetime]::UtcNow) -Zone $displayZone)
        $agentFilterLbl = if ([string]::IsNullOrWhiteSpace($AgentName)) { 'none' } else { $AgentName }
        $userFilterLbl  = if ([string]::IsNullOrWhiteSpace($userSeed)) { 'none' } else { $userSeed }
        $windowLocal   = "{0} to {1}" -f (Get-LocalTimeString -Utc $startIso -Zone $displayZone), (Get-LocalTimeString -Utc $endIso -Zone $displayZone)
        if ($AllHistory) { $windowLocal += ' (all retained history)' }

        # Build one card per conversation, each containing its own chat thread.
        $cards = foreach ($c in $conversations) {
            $flagBits = New-Object System.Collections.Generic.List[string]
            if ($c.HadError)      { $flagBits.Add('<span class="pill err">Agent error</span>') | Out-Null }
            if ($c.UsedKnowledge) { $flagBits.Add('<span class="pill know">Knowledge used</span>') | Out-Null }
            if ($c.PlanStepCount -gt 0) { $flagBits.Add("<span class=""pill plan"">$($c.PlanStepCount) plan step(s)</span>") | Out-Null }
            if ($c.UserTurnCount -eq 0)  { $flagBits.Add('<span class="pill idle">No user turns</span>') | Out-Null }

            $turnHtml = foreach ($t in $c.Turns) {
                $clean   = Get-DisplayText $t.Text
                $excerpt = Get-Excerpt $clean 700
                $isLong  = $clean.Length -gt 700
                $cls     = if ($t.Role -eq 'USER') { 'turn user' } else { 'turn agent' }

                $who = if ($t.Role -eq 'USER') {
                    $tu = @($userDir | Where-Object { $_.ObjectId -eq $t.AadObjectId }) | Select-Object -First 1
                    if ($tu) { $tu.DisplayName } else { 'User' }
                } else {
                    $c.AgentDisplayName
                }

                $tsLocal = Get-LocalTimeString -Utc $t.TimestampUtc -Zone $displayZone

                $bodyHtml = if ($isLong) {
                    "<div class=""short"">$(ConvertTo-SafeHtml $excerpt)</div>" +
                    "<div class=""full"">$(ConvertTo-SafeHtml $clean)</div>" +
                    "<button class=""more"" onclick=""tog(this)"">Show full text ($($clean.Length) chars)</button>"
                } else {
                    "<div class=""short only"">$(ConvertTo-SafeHtml $clean)</div>"
                }

                "<div class=""$cls""><div class=""hd""><span class=""who"">$(ConvertTo-SafeHtml $who)</span><span class=""ts"" title=""$(ConvertTo-SafeHtml $t.TimestampUtc) UTC"">$(ConvertTo-SafeHtml $tsLocal)</span></div>$bodyHtml</div>"
            }

            $searchBlob = ConvertTo-SafeHtml ((($c.Turns | ForEach-Object { Get-Excerpt (Get-DisplayText $_.Text) 400 }) -join ' ') + ' ' + $c.AgentDisplayName + ' ' + $c.BotName + ' ' + $c.ConversationId + ' ' + $c.ParticipantLabel)

            # yyyy-MM-dd form so the HTML date pickers can compare lexically. Uses the display
            # time zone so a date filter matches what the reader sees on the card.
            $dayKey = ''
            if ($c.StartTimeLocal) { $dayKey = ($c.StartTimeLocal -split ' ')[0] }

            # Numeric sort key for the in-page Newest/Oldest selector. Unstamped conversations get
            # 0 and are pinned to the end by the reorder routine.
            $epochKey = 0
            if ($null -ne $c.SortKeyUtc) { $epochKey = [int64] ([datetimeoffset]::new($c.SortKeyUtc, [timespan]::Zero)).ToUnixTimeSeconds() }

            @"
<section class="conv" data-agent="$(ConvertTo-SafeHtml $c.AgentDisplayName)" data-err="$($c.HadError)" data-user="$($c.UserTurnCount -gt 0)" data-uid="$(ConvertTo-SafeHtml (($c.UserObjectIds) -join '|'))" data-day="$dayKey" data-epoch="$epochKey" data-blob="$searchBlob">
  <div class="chd">
    <div>
      <h2>$(ConvertTo-SafeHtml $c.AgentDisplayName)</h2>
      <div class="meta">$(ConvertTo-SafeHtml $c.StartTimeLocal) $(ConvertTo-SafeHtml $zoneLabel) &middot; $($c.TurnCount) turn(s), $($c.UserTurnCount) from user &middot; $(ConvertTo-SafeHtml $c.ParticipantLabel)</div>
    </div>
    <div class="flags">$([string]::Join(' ', $flagBits))</div>
  </div>
  <div class="ids">
    <span><b>Conversation:</b> $(ConvertTo-SafeHtml $c.ConversationId)</span>
    <span><b>Transcript:</b> $(ConvertTo-SafeHtml $c.TranscriptId)</span>
    <span><b>Agent schema:</b> $(ConvertTo-SafeHtml $c.BotName)</span>
    <span><b>User object ID:</b> $(ConvertTo-SafeHtml (($c.UserObjectIds) -join ', '))</span>
    <span><b>Start (UTC):</b> $(ConvertTo-SafeHtml ([string]$c.StartTimeUtc))</span>
  </div>
  <div class="thread">$([string]::Join('', $turnHtml))</div>
</section>
"@
        }

        $html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Copilot Studio Agent Conversation Report</title>
<style>
:root{--bd:#d8dee4;--mut:#66717b;--acc:#0f6cbd;--bg:#f7f9fb;--ink:#1f2933}
*{box-sizing:border-box}
body{font-family:"Segoe UI",Arial,sans-serif;margin:0;background:var(--bg);color:var(--ink)}
header{background:#fff;border-bottom:1px solid var(--bd);padding:22px 28px}
h1{margin:0 0 6px;font-size:22px;font-weight:600}
.sub{color:var(--mut);font-size:13px;line-height:1.55}
.cards{display:flex;gap:12px;flex-wrap:wrap;padding:18px 28px 0}
.card{background:#fff;border:1px solid var(--bd);border-radius:6px;padding:12px 16px;min-width:130px}
.card .v{font-size:23px;font-weight:600;color:var(--acc)}
.card .k{font-size:11px;color:var(--mut);text-transform:uppercase;letter-spacing:.35px;margin-top:3px}
.note{margin:16px 28px 0;padding:12px 16px;border-radius:6px;font-size:13px;line-height:1.5;background:#f0f9f0;border:1px solid #b7e0b7}
.note.horizon{background:#eaf3fb;border:1px solid #a9cded}
.note code{background:#e3f0e3;padding:1px 5px;border-radius:3px}
.note.horizon code{background:#d7e8f7}
.controls{padding:17px 28px 9px;display:flex;gap:10px;flex-wrap:wrap;align-items:center}
input,select,button{padding:8px 10px;border:1px solid var(--bd);border-radius:4px;font-size:13px;font-family:inherit;background:#fff}
input#q{min-width:340px}
button{cursor:pointer}button:hover{background:#eef3f7}
#count{color:var(--mut);font-size:13px}
.wrap{padding:8px 28px 46px}
.conv{background:#fff;border:1px solid var(--bd);border-radius:8px;margin:14px 0;overflow:hidden}
.conv.hide{display:none}
.chd{display:flex;justify-content:space-between;align-items:flex-start;gap:16px;padding:14px 18px;background:#eef2f5;border-bottom:1px solid var(--bd);flex-wrap:wrap}
.chd h2{margin:0;font-size:15px;font-weight:600;color:#17365D}
.meta{color:var(--mut);font-size:12px;margin-top:3px}
.flags{display:flex;gap:6px;flex-wrap:wrap}
.pill{font-size:11px;padding:3px 9px;border-radius:11px;font-weight:600;white-space:nowrap}
.pill.err{background:#fde7e9;color:#a4262c}
.pill.know{background:#e5f1fb;color:#0f6cbd}
.pill.plan{background:#f3e8fd;color:#6b2fa0}
.pill.idle{background:#eceff1;color:#66717b}
.ids{padding:9px 18px;border-bottom:1px solid var(--bd);font-size:11px;color:var(--mut);display:flex;gap:20px;flex-wrap:wrap;font-family:Consolas,monospace}
.thread{padding:14px 18px}
.turn{border-radius:8px;padding:10px 14px;margin:9px 0;max-width:920px;font-size:13px;line-height:1.55}
.turn.user{background:#dceaf7;border-left:4px solid #0f6cbd}
.turn.agent{background:#f7f8f9;border-left:4px solid #8a8886}
.hd{display:flex;justify-content:space-between;margin-bottom:5px}
.who{font-weight:600;font-size:11px;letter-spacing:.4px;text-transform:uppercase;color:#4a5560}
.ts{font-size:11px;color:var(--mut);font-variant-numeric:tabular-nums}
.short,.full{white-space:pre-wrap;word-break:break-word}
.full{display:none}
.turn.open .short{display:none}
.turn.open .full{display:block}
.more{margin-top:8px;font-size:11px;padding:4px 10px;background:#fff;border:1px solid var(--bd);border-radius:4px}
footer{padding:0 28px 40px;color:var(--mut);font-size:12px;line-height:1.6}
</style></head><body>
<header>
  <h1>Copilot Studio Agent Conversation Report</h1>
  <div class="sub">
    <div>Environment: $(ConvertTo-SafeHtml $EnvironmentUrl)</div>
    <div>Export window: $(ConvertTo-SafeHtml $windowLocal) &nbsp;($(ConvertTo-SafeHtml $zoneLabel))</div>
    <div>Filters applied at export: agent = $(ConvertTo-SafeHtml $agentFilterLbl) &middot; user = $(ConvertTo-SafeHtml $userFilterLbl)</div>
    <div>Sort: conversations $(if ($SortOrder -eq 'Oldest') { 'oldest first' } else { 'newest first' }) by start time; turns within a conversation always oldest to newest. Use the order selector below to flip it.</div>
    <div>Generated: $(ConvertTo-SafeHtml $generatedLcl) $(ConvertTo-SafeHtml $zoneAbbrev) &middot; all times shown in $(ConvertTo-SafeHtml $zoneLabel) (local clock time, DST applied per timestamp); UTC retained in the exports</div>
  </div>
</header>
<div class="cards">
  <div class="card"><div class="v">$($conversations.Count)</div><div class="k">Conversations</div></div>
  <div class="card"><div class="v">$turnTotal</div><div class="k">Total turns</div></div>
  <div class="card"><div class="v">$($agentNames.Count)</div><div class="k">Agents</div></div>
  <div class="card"><div class="v">$userCount</div><div class="k">Distinct users</div></div>
  <div class="card"><div class="v">$knowledgeCnt</div><div class="k">Used knowledge</div></div>
  <div class="card"><div class="v">$errorCount</div><div class="k">Had agent errors</div></div>
</div>
<div class="note horizon">
  <strong>Retention horizon for this environment:</strong> the oldest surviving transcript is
  <code>$(ConvertTo-SafeHtml (Get-LocalTimeString -Utc $coverage.OldestUtc -Zone $displayZone))</code>
  ($($coverage.OldestAgeDays) day(s) old) and the newest is
  <code>$(ConvertTo-SafeHtml (Get-LocalTimeString -Utc $coverage.NewestUtc -Zone $displayZone))</code>,
  giving a recoverable span of <strong>$($coverage.SpanDays) day(s)</strong>
  across <strong>$($coverage.TotalTranscripts)</strong> transcript record(s) in total.
  Conversations older than the oldest timestamp have already been removed by the Dataverse bulk deletion
  job and cannot be recovered by this or any other tool. Treat this report as complete only for the window
  stated above.
</div>
<div class="note">
  <strong>Evidence source:</strong> full prompt and response text read from the Microsoft Dataverse
  <code>conversationtranscript</code> table. This is the authoritative source for custom Copilot Studio
  agents because it captures unconditionally whenever transcript recording is enabled. Microsoft Purview
  Audit records that these interactions occurred but its <code>Messages</code> collection holds message
  identifiers and flags rather than text; Purview DSPM for AI <em>can</em> display prompt and response
  content, but only when several capture gates were met at the time - the interacting user had an Exchange
  Online mailbox, a collection policy with <em>Capture content</em> was in scope, audit ingestion was on,
  and (for non-Microsoft channels) pay-as-you-go billing was enabled. None of those gates apply here.
  Join back to Purview Audit on <code>UserKey</code> / <code>UserId</code> = the user object ID shown on each
  conversation. Agent names are the friendly names from the Microsoft 365 admin center Agent Registry, resolved
  from the Dataverse agent directory; the underlying schema name is shown alongside each conversation.
  Very long machine-generated prompts (for example a full HTML email pasted into an autonomous
  trigger) are shown as readable excerpts with a <em>Show full text</em> control; the untouched original text is
  preserved verbatim in the JSON export for evidence and chain of custody.
  An agent response of <code>REDACTED</code> is expected for SharePoint-grounded answers: Microsoft stores the
  user's question but not the generated answer for that knowledge source.
</div>
<div class="controls">
  <input id="q" type="search" placeholder="Filter by prompt text, answer text, agent, conversation ID...">
  <select id="fAgent"><option value="">All agents</option>$agentOptions</select>
  <select id="fUser"><option value="">All users</option>$userOptions</select>
  <input id="dFrom" type="date" title="Conversations starting on or after this date ($zoneLabel)">
  <input id="dTo" type="date" title="Conversations starting on or before this date ($zoneLabel)">
  <select id="fFlag">
    <option value="">All conversations</option>
    <option value="err">Had agent errors</option>
    <option value="user">Has user turns</option>
  </select>
  <select id="fSort" title="Chronological order of conversations">
    <option value="desc"$(if ($SortOrder -ne 'Oldest') { ' selected' })>Newest first</option>
    <option value="asc"$(if ($SortOrder -eq 'Oldest') { ' selected' })>Oldest first</option>
  </select>
  <button onclick="expandAll()">Expand all text</button>
  <button onclick="resetAll()">Reset filters</button>
  <span id="count"></span>
</div>
<div class="wrap" id="wrap">$([string]::Join('', $cards))</div>
<footer>Use the HTML for review, the CSV for filtering and pivoting, and the JSON for structured evidence and chain of custody. Content is sensitive - handle per your organization's retention and privacy requirements.</footer>
<script>
var q=document.getElementById('q'),ag=document.getElementById('fAgent'),us=document.getElementById('fUser'),
    df=document.getElementById('dFrom'),dt=document.getElementById('dTo'),fl=document.getElementById('fFlag'),
    so=document.getElementById('fSort'),wrap=document.getElementById('wrap'),
    ct=document.getElementById('count');
var defaultSort='$(if ($SortOrder -eq 'Oldest') { 'asc' } else { 'desc' })';
function reorder(){
  var dir=so.value==='asc'?1:-1;
  var rows=Array.prototype.slice.call(wrap.querySelectorAll('.conv'));
  rows.sort(function(a,b){
    var ea=parseInt(a.dataset.epoch||'0',10),eb=parseInt(b.dataset.epoch||'0',10);
    // Conversations with no usable timestamp (epoch 0) always sink to the bottom.
    if(!ea&&!eb)return 0;
    if(!ea)return 1;
    if(!eb)return -1;
    if(ea===eb)return 0;
    return ea<eb?dir:-dir;
  });
  var frag=document.createDocumentFragment();
  rows.forEach(function(r){frag.appendChild(r)});
  wrap.appendChild(frag);
}
function apply(){
  var query=q.value.toLowerCase(),a=ag.value,u=us.value,f=fl.value,
      from=df.value,to=dt.value,shown=0,all=document.querySelectorAll('.conv');
  all.forEach(function(r){
    var okText=!query||(r.dataset.blob||'').toLowerCase().indexOf(query)>-1;
    var okAgent=!a||r.dataset.agent===a;
    var okUser=!u||(r.dataset.uid||'').split('|').indexOf(u)>-1;
    var d=r.dataset.day||'';
    var okFrom=!from||(d&&d>=from);
    var okTo=!to||(d&&d<=to);
    var okFlag=!f||(f==='err'&&r.dataset.err==='True')||(f==='user'&&r.dataset.user==='True');
    var show=okText&&okAgent&&okUser&&okFrom&&okTo&&okFlag;
    r.classList.toggle('hide',!show);
    if(show)shown++;
  });
  ct.textContent=shown+' of '+all.length+' conversations shown';
}
function tog(b){b.parentNode.classList.toggle('open');b.textContent=b.parentNode.classList.contains('open')?'Collapse':'Show full text';}
function expandAll(){document.querySelectorAll('.turn').forEach(function(t){if(t.querySelector('.more'))t.classList.add('open')});}
function resetAll(){q.value='';ag.value='';us.value='';df.value='';dt.value='';fl.value='';so.value=defaultSort;document.querySelectorAll('.turn').forEach(function(t){t.classList.remove('open')});reorder();apply();}
[q,ag,us,df,dt,fl].forEach(function(x){x.addEventListener('input',apply)});
so.addEventListener('change',reorder);
reorder();
apply();
</script></body></html>
"@
        [System.IO.File]::WriteAllText($htmlPath, $html, $utf8Bom)
        $written.Add($htmlPath) | Out-Null
        Write-Log -Level 'OK' -Message "HTML written: $htmlPath"
    }
}

# Log file
$logPath = Join-Path $OutputFolder ("Export-Log-{0}.txt" -f $stampSuffix)
if ($PSCmdlet.ShouldProcess($logPath, 'Write run log')) {
    [System.IO.File]::WriteAllText($logPath, ($script:LogLines -join "`r`n"), $utf8Bom)
    Write-Log -Level 'OK' -Message "Log written: $logPath"
}

$elapsed = (Get-Date) - $runStart
Write-Log -Level 'STEP' -Message ('--- Export complete in {0:N1}s. {1} file(s) written. ---' -f $elapsed.TotalSeconds, $written.Count)

if ($wantHtml) {
    Write-Host ''
    Write-Host '  Open the HTML report to review conversations:' -ForegroundColor White
    Write-Host ("    {0}" -f $htmlPath) -ForegroundColor Cyan
    Write-Host ''
}

# Objects are returned only on request. Emitting them by default floods the console with
# entire transcript bodies and makes the run output unreadable.
if ($PassThru) { $conversations }
