<#
.SYNOPSIS
    Preflight readiness survey for a Copilot Studio agent interaction audit.

.DESCRIPTION
    Run this BEFORE Export-CopilotStudioTranscripts.ps1.

    A Microsoft 365 Global Administrator is NOT automatically able to read Copilot Studio
    conversation transcripts. Microsoft documents that tenant-level admin roles do not grant
    Dataverse data access, and that the Environment Maker role does not grant transcript access
    either. In a tenant with more than one Dataverse environment this becomes the single biggest
    reason an audit "returns nothing": the operator is querying an environment they are not a
    provisioned user in, or holds no role that can read the ConversationTranscript table.

    This script answers, in one pass and without changing anything:

      1. How many Dataverse environments exist in this tenant?          (admin inventory)
      2. Which of them can the signed-in identity actually reach?       (discovery inventory)
      3. In each reachable environment, what roles does the identity
         hold, and can it ACTUALLY read ConversationTranscript?         (live read probe)
      4. Which environments will never hold transcripts regardless of
         permissions - Developer environments and Dataverse for Teams?  (SKU inventory)
      5. How far back does each environment's data actually go?         (retention probe)
      6. Which Microsoft Purview role groups is the identity missing
         for the Purview-side evidence paths?                           (optional)

    It then prints a prioritised remediation playbook: exactly which environments to fix, and
    exactly what to grant, in order.

    The permission verdict is based on a REAL QUERY, not on inspecting role names. Role names are
    reported for context, but the pass/fail is whatever the Web API actually returned. That is the
    only trustworthy test.

.PARAMETER TenantId
    Entra tenant GUID to sign in against. Required for -AuthMethod DeviceCode, which is the
    default and the right choice for any tenant that is not your own corporate tenant.

.PARAMETER AuthMethod
    Auto, AzureCli, DeviceCode, or Token. Defaults to DeviceCode because this script is normally
    run against a customer or lab tenant, and DeviceCode leaves the local Azure CLI context alone.

.PARAMETER AccessToken
    Pre-acquired bearer token. Only used with -AuthMethod Token. Must be for the Power Platform
    BAP audience (https://service.powerapps.com/); per-environment tokens cannot be reused here.

.PARAMETER EnvironmentUrl
    Optional. Restrict the survey to a single environment URL instead of every environment in the
    tenant. Useful for a fast re-check after remediation.

.PARAMETER IncludeInaccessible
    Include environments the identity cannot reach in the detailed per-environment section.
    They are always counted in the summary; this switch adds them to the detail table.

.PARAMETER SkipRetentionProbe
    Skip the oldest/newest transcript probe. Faster on tenants with many environments, at the cost
    of not knowing how far back each environment can actually produce evidence.

.PARAMETER CheckPurviewRoles
    Also check Microsoft Purview role group membership for the signed-in identity. Requires the
    ExchangeOnlineManagement module and triggers a second interactive sign-in for Security and
    Compliance PowerShell. Skipped by default because it is a separate consent prompt.

.PARAMETER GrantSelfTranscriptViewer
    Attempt to assign the Bot Transcript Viewer security role to the signed-in identity in every
    environment where the identity is provisioned but lacks transcript read. This is the only
    write action this script can perform and it honours -WhatIf and -Confirm. It requires the
    identity to already hold System Administrator in that environment; it cannot bootstrap access
    to an environment the identity is not a user in.

.PARAMETER OutputFolder
    Folder for the readiness report. Defaults to C:\Scout_Output\CopilotStudio-Transcripts.

.PARAMETER Format
    Console, Html, or All. Defaults to All.

.PARAMETER MaxRetries
    Retry budget per HTTP call for transient failures. Defaults to 5, exponential backoff.

.PARAMETER Force
    Suppress the quick-reference banner.

.PARAMETER Help
    Show the quick reference and exit without signing in.

.EXAMPLE
    .\Test-CopilotAuditReadiness.ps1 -TenantId <tenant GUID>

    Full tenant survey. One device code sign-in. Writes an HTML readiness report.

.EXAMPLE
    .\Test-CopilotAuditReadiness.ps1 -TenantId <tenant GUID> -CheckPurviewRoles

    Also checks Purview role group membership. Prompts a second time for Security and
    Compliance PowerShell.

.EXAMPLE
    .\Test-CopilotAuditReadiness.ps1 -TenantId <tenant GUID> -GrantSelfTranscriptViewer -WhatIf

    Shows exactly which role assignments would be made, without making them.

.NOTES
    Read-only by default. The single write path is -GrantSelfTranscriptViewer.

    Facts this script encodes, from Microsoft Learn (verified 2026-09):
      - Conversation transcripts are NOT written for Microsoft 365 Copilot agents, for Microsoft
        Dataverse for Teams environments, or for agents deployed in Developer environments.
      - The documented least-privilege role for reading transcripts is Bot Transcript Viewer.
        Environment Maker does not grant it.
      - Tenant-level admin roles do not automatically grant Dataverse data access; the identity
        must exist as an enabled user in the environment and hold a security role there.
      - Default Dataverse retention is 30 days, enforced by a bulk deletion job. An administrator
        can change it. It is not a fixed platform limit, so it must be measured per environment.
      - Every environment stores its own transcripts. There is no tenant-wide transcript table.
#>

# The script itself is read-only, so writing its own report must never prompt. The one genuine
# write path (Grant-TranscriptViewerRole) declares ConfirmImpact = 'High' on its own function and
# still prompts. Setting High here instead would suppress the report write on any non-interactive
# run, because ShouldProcess would auto-decline with no console to answer the prompt.
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $false)]
    [string] $TenantId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'AzureCli', 'DeviceCode', 'Token')]
    [string] $AuthMethod = 'DeviceCode',

    [Parameter(Mandatory = $false)]
    [string] $AccessToken,

    [Parameter(Mandatory = $false)]
    [string] $EnvironmentUrl,

    [Parameter(Mandatory = $false)]
    [switch] $IncludeInaccessible,

    [Parameter(Mandatory = $false)]
    [switch] $SkipRetentionProbe,

    [Parameter(Mandatory = $false)]
    [switch] $CheckPurviewRoles,

    [Parameter(Mandatory = $false)]
    [switch] $GrantSelfTranscriptViewer,

    [Parameter(Mandatory = $false)]
    [string] $OutputFolder = 'C:\Scout_Output\CopilotStudio-Transcripts',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Console', 'Html', 'All')]
    [string] $Format = 'All',

    [Parameter(Mandatory = $false)]
    [int] $MaxRetries = 5,

    [Parameter(Mandatory = $false)]
    [string] $TimeZoneId = 'Eastern Standard Time',

    [Parameter(Mandatory = $false)]
    [switch] $Force,

    [Parameter(Mandatory = $false)]
    [switch] $Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:LogLines   = New-Object System.Collections.Generic.List[string]
$script:RunStart   = Get-Date

# Azure CLI public client. Pre-consented in every tenant, so no app registration is needed.
$script:PublicClientId     = '51f81489-12ee-4a9e-aaae-a2591f45987d'
$script:CachedRefreshToken = $null
# Must be initialised at script scope: Set-StrictMode makes a first read of an unset variable fatal.
$script:PollNoticeShown    = $false

# Power Platform BAP admin audience. This is what lets a tenant admin enumerate EVERY environment,
# including the ones they are not a Dataverse user in - which is the whole point of this script.
$script:BapResource = 'https://service.powerapps.com/'
$script:BapRoot     = 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments'
$script:BapApiVer   = '2021-04-01'
$script:DiscoResource = 'https://globaldisco.crm.dynamics.com/'
$script:DiscoUri      = 'https://globaldisco.crm.dynamics.com/api/discovery/v2.0/Instances'

# Purview role groups that matter for the non-Dataverse evidence paths.
$script:PurviewRoleGroups = @(
    [pscustomobject]@{ Name = 'Content Explorer Content Viewer'; Why = 'Documented as required to VIEW prompt and response content. Necessary but NOT sufficient - it authorizes viewing, it does not cause capture.' }
    [pscustomobject]@{ Name = 'Microsoft Purview Data Security AI Content Viewer'; Why = 'Newer least-privilege alternative to Content Explorer Content Viewer, scoped to AI interactions only.' }
    [pscustomobject]@{ Name = 'Content Explorer List Viewer';    Why = 'Item and location LIST view only. This is NOT the role that surfaces AI prompt text.' }
    [pscustomobject]@{ Name = 'eDiscovery Manager';              Why = 'Required for the eDiscovery path. Copilot Studio prompts/responses ARE mailbox-backed as IPM.SkypeTeams.Message.Copilot.Studio.*, so eDiscovery can return them when Purview captured them.' }
    [pscustomobject]@{ Name = 'Compliance Administrator';        Why = 'Broad Purview configuration, including DSPM for AI setup and collection policies.' }
    [pscustomobject]@{ Name = 'Compliance Data Administrator';   Why = 'Data-facing compliance operations without full Compliance Administrator.' }
    [pscustomobject]@{ Name = 'Audit Manager';                   Why = 'Required to configure audit retention policies.' }
    [pscustomobject]@{ Name = 'Audit Reader';                    Why = 'Required to search the unified audit log.' }
)

# Documented gates that determine whether Purview ever CAPTURES prompt/response text for a
# Copilot Studio agent. A role group grants the right to view content that exists; none of these
# are role problems, which is why an administrator holding every role can still see nothing.
$script:PurviewCaptureGates = @(
    [pscustomobject]@{
        Gate  = 'Global Administrator is not enough'
        Fact  = 'Microsoft''s DSPM permissions table explicitly marks Global Administrator as NOT able to view prompts and responses. Only Content Explorer Content Viewer or Microsoft Purview Data Security AI Content Viewer grant it.'
        Check = 'Purview portal > Settings > Roles and scopes > Role groups. Re-open the browser session after any change; role propagation is not immediate.'
    }
    [pscustomobject]@{
        Gate  = 'Interacting user must have an Exchange Online mailbox'
        Fact  = 'Microsoft: "When a user doesn''t have a mailbox hosted in Exchange Online, no prompt or response is displayed." Purview stores the compliance copy in a hidden folder in the INTERACTING user''s mailbox. Anonymous web-chat users and service identities have no mailbox, so their content can never display.'
        Check = 'Get-EXOMailbox <interacting user UPN> | Format-List PrimarySmtpAddress,RecipientTypeDetails. Check the user who sent the prompt, not the administrator reading the report.'
    }
    [pscustomobject]@{
        Gate  = 'Collection policy must have Capture content enabled'
        Fact  = 'Microsoft: "For collection policies, no prompt or response is displayed if the option to capture content isn''t selected in the policy." Capture also requires the Content contains classifiers condition set to All.'
        Check = 'Purview portal > Collection policies. Verify scope, Capture content ON, classifiers = All, policy deployed. Allow 24 hours after a change.'
    }
    [pscustomobject]@{
        Gate  = 'Non-Microsoft channels require Purview pay-as-you-go billing'
        Fact  = 'Microsoft: "Managing these AI interactions for Copilot Studio agents published to non-Microsoft channels requires you to enable pay-as-you-go billing in your organization." Demo website, custom website, Direct Line and similar channels fall here. Microsoft channels (Teams, M365 Copilot) do not.'
        Check = 'Confirm the tenant is linked to an active Azure subscription and Purview PAYG is enabled. This is separate from Copilot Studio message capacity and from M365 Copilot licensing.'
    }
    [pscustomobject]@{
        Gate  = 'Unified audit ingestion must have been ON at the time of the interaction'
        Fact  = 'Enabling audit is prospective. It does not reconstruct interactions that were never captured, even though the Dataverse transcript for those same interactions still exists.'
        Check = 'Get-AdminAuditLogConfig | Format-List UnifiedAuditLogIngestionEnabled  (must be True)'
    }
    [pscustomobject]@{
        Gate  = 'Known issue: text can legitimately be blank or split'
        Fact  = 'Microsoft: "The AI interaction event doesn''t always display text for the prompt and response. Sometimes, the prompt and response spans consecutive entries."'
        Check = 'Open the immediately preceding and following AI interaction records in a narrow time window before concluding the content is missing.'
    }
)

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Message,
        [Parameter(Mandatory = $false)][ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')][string] $Level = 'INFO'
    )

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $line  = "[{0}] [{1,-5}] {2}" -f $stamp, $Level, $Message
    $script:LogLines.Add($line) | Out-Null

    switch ($Level) {
        'OK'    { Write-Host $line -ForegroundColor Green }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'STEP'  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line -ForegroundColor Gray }
    }
}

function Show-Banner {
    Write-Host ''
    Write-Host '  ===================================================================' -ForegroundColor Cyan
    Write-Host '   COPILOT STUDIO AUDIT READINESS - PREFLIGHT SURVEY' -ForegroundColor Cyan
    Write-Host '  ===================================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '   Run this BEFORE Export-CopilotStudioTranscripts.ps1.' -ForegroundColor White
    Write-Host ''
    Write-Host '   Being a Global Administrator does not grant Dataverse data access.' -ForegroundColor Yellow
    Write-Host '   This survey tells you, per environment, whether you can actually' -ForegroundColor Gray
    Write-Host '   read agent transcripts - by running a real query, not by guessing' -ForegroundColor Gray
    Write-Host '   from role names.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '   TYPICAL RUN' -ForegroundColor White
    Write-Host '     .\Test-CopilotAuditReadiness.ps1 -TenantId <tenant GUID>' -ForegroundColor Green
    Write-Host ''
    Write-Host '   ALSO CHECK PURVIEW ROLE GROUPS (second sign-in prompt)' -ForegroundColor White
    Write-Host '     .\Test-CopilotAuditReadiness.ps1 -TenantId <guid> -CheckPurviewRoles' -ForegroundColor Green
    Write-Host ''
    Write-Host '   PREVIEW A SELF-GRANT WITHOUT MAKING IT' -ForegroundColor White
    Write-Host '     .\Test-CopilotAuditReadiness.ps1 -TenantId <guid> `' -ForegroundColor Green
    Write-Host '         -GrantSelfTranscriptViewer -WhatIf' -ForegroundColor Green
    Write-Host ''
    Write-Host '   Read-only unless you pass -GrantSelfTranscriptViewer.' -ForegroundColor Gray
    Write-Host '   Suppress this banner with -Force.  Full help: -Help or Get-Help.' -ForegroundColor DarkGray
    Write-Host '  ===================================================================' -ForegroundColor Cyan
    Write-Host ''
}

if ($Help) { Show-Banner; return }
if (-not $Force) { Show-Banner }

# -------------------------------------------------------------------------------------------
# Token plumbing
# -------------------------------------------------------------------------------------------
function ConvertFrom-JwtPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Token)

    try {
        $parts = $Token.Split('.')
        if ($parts.Count -lt 2) { return $null }
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } 1 { return $null } }
        $bytes = [Convert]::FromBase64String($payload)
        return ([Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json)
    }
    catch { return $null }
}

function Get-TokenIdentityInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Token)

    $claims = ConvertFrom-JwtPayload -Token $Token
    if ($null -eq $claims) {
        return [pscustomobject]@{ Upn = '(undecodable)'; TenantId = '(undecodable)'; Audience = '(undecodable)'; ObjectId = '' }
    }

    $upn = '(unknown)'
    foreach ($c in @('upn', 'preferred_username', 'unique_name', 'email', 'appid')) {
        if (($claims.PSObject.Properties.Name -contains $c) -and -not [string]::IsNullOrWhiteSpace($claims.$c)) {
            $upn = [string] $claims.$c
            break
        }
    }

    $tid = '(unknown)'
    if (($claims.PSObject.Properties.Name -contains 'tid') -and -not [string]::IsNullOrWhiteSpace($claims.tid)) { $tid = [string] $claims.tid }

    $aud = '(unknown)'
    if (($claims.PSObject.Properties.Name -contains 'aud') -and -not [string]::IsNullOrWhiteSpace($claims.aud)) { $aud = [string] $claims.aud }

    $oid = ''
    if (($claims.PSObject.Properties.Name -contains 'oid') -and -not [string]::IsNullOrWhiteSpace($claims.oid)) { $oid = [string] $claims.oid }

    return [pscustomobject]@{ Upn = $upn; TenantId = $tid; Audience = $aud; ObjectId = $oid }
}

function Get-TokenByDeviceCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Resource,
        [Parameter(Mandatory = $true)][string] $Tenant
    )

    $authority = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0"
    $scope     = "$Resource.default offline_access openid profile"
    if (-not $Resource.EndsWith('/')) { $scope = "$Resource/.default offline_access openid profile" }

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
    Write-Host  '   3. Sign in as a Global Administrator or Power Platform Administrator' -ForegroundColor White
    Write-Host  '      in the TARGET tenant.' -ForegroundColor Gray
    Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ''

    $interval = 5
    if (($codeResponse.PSObject.Properties.Name -contains 'interval') -and $codeResponse.interval) { $interval = [int] $codeResponse.interval }

    $expires = (Get-Date).AddSeconds([int] $codeResponse.expires_in)

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
            if ($tokenResponse.PSObject.Properties.Name -contains 'refresh_token') {
                $script:CachedRefreshToken = [string] $tokenResponse.refresh_token
            }
            return $tokenResponse.access_token
        }
        catch {
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
            if ([string]::IsNullOrWhiteSpace($oauthError) -and $errBody -match '"error"\s*:\s*"([a-z_]+)"') { $oauthError = $Matches[1] }

            $keepPolling = $false
            if ($oauthError -eq 'authorization_pending') { $keepPolling = $true }
            elseif ($oauthError -eq 'slow_down') { $interval += 5; $keepPolling = $true }
            elseif ($oauthError -eq 'authorization_declined') { throw 'Device code sign-in was declined in the browser.' }
            elseif ($oauthError -eq 'expired_token') { throw 'Device code expired before sign-in completed. Re-run the script.' }
            else { throw "Device code sign-in failed. OAuth error: '$oauthError'. Detail: $errBody" }

            if (-not $keepPolling) { break }
            if (-not $script:PollNoticeShown) {
                Write-Log -Message 'Waiting for sign-in to complete in the browser ...'
                $script:PollNoticeShown = $true
            }
        }
    }

    throw 'Device code sign-in did not complete before the code expired.'
}

function Get-TokenByRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Resource,
        [Parameter(Mandatory = $true)][string] $Tenant,
        [Parameter(Mandatory = $true)][string] $RefreshToken
    )

    $scope = "$Resource.default offline_access openid profile"
    if (-not $Resource.EndsWith('/')) { $scope = "$Resource/.default offline_access openid profile" }

    try {
        $resp = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{
                grant_type    = 'refresh_token'
                client_id     = $script:PublicClientId
                refresh_token = $RefreshToken
                scope         = $scope
            } -UseBasicParsing -TimeoutSec 60

        if ($resp.PSObject.Properties.Name -contains 'refresh_token') {
            $script:CachedRefreshToken = [string] $resp.refresh_token
        }
        return [string] $resp.access_token
    }
    catch { return $null }
}

function Get-TokenByAzureCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Resource,
        [Parameter(Mandatory = $false)][string] $Tenant
    )

    $az = Get-Command az -ErrorAction SilentlyContinue
    if ($null -eq $az) { throw 'Azure CLI (az) is not installed or not on PATH.' }

    $res  = $Resource.TrimEnd('/')
    $args = @('account', 'get-access-token', '--resource', $res, '-o', 'json')
    if (-not [string]::IsNullOrWhiteSpace($Tenant)) { $args += @('--tenant', $Tenant) }

    $raw = & az @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI token acquisition failed: $raw" }

    try { return ([string]::Join('', $raw) | ConvertFrom-Json).accessToken }
    catch { throw "Could not parse the Azure CLI token response: $raw" }
}

function Get-ResourceToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Resource,
        [Parameter(Mandatory = $false)][string] $Tenant,
        [Parameter(Mandatory = $false)][string] $Method = 'DeviceCode',
        [Parameter(Mandatory = $false)][string] $SuppliedToken
    )

    if (-not [string]::IsNullOrWhiteSpace($script:CachedRefreshToken) -and -not [string]::IsNullOrWhiteSpace($Tenant) -and $Method -ne 'Token') {
        $silent = Get-TokenByRefresh -Resource $Resource -Tenant $Tenant -RefreshToken $script:CachedRefreshToken
        if (-not [string]::IsNullOrWhiteSpace($silent)) { return $silent }
    }

    switch ($Method) {
        'Token' {
            if ([string]::IsNullOrWhiteSpace($SuppliedToken)) { throw '-AuthMethod Token requires -AccessToken.' }
            return $SuppliedToken
        }
        'DeviceCode' {
            if ([string]::IsNullOrWhiteSpace($Tenant)) { throw '-AuthMethod DeviceCode requires -TenantId.' }
            return (Get-TokenByDeviceCode -Resource $Resource -Tenant $Tenant)
        }
        'AzureCli' { return (Get-TokenByAzureCli -Resource $Resource -Tenant $Tenant) }
        default {
            if (-not [string]::IsNullOrWhiteSpace($SuppliedToken)) { return $SuppliedToken }
            try { return (Get-TokenByAzureCli -Resource $Resource -Tenant $Tenant) }
            catch {
                if ([string]::IsNullOrWhiteSpace($Tenant)) { throw 'Azure CLI failed and no -TenantId was supplied for device code fallback.' }
                return (Get-TokenByDeviceCode -Resource $Resource -Tenant $Tenant)
            }
        }
    }
}

# -------------------------------------------------------------------------------------------
# Throttle-safe HTTP with a structured result instead of a thrown exception, so one bad
# environment never aborts a tenant-wide survey.
# -------------------------------------------------------------------------------------------
function Invoke-RestProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Uri,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $false)][string] $Method = 'Get',
        [Parameter(Mandatory = $false)] $Body,
        [Parameter(Mandatory = $false)][int] $Retries = 5,
        [Parameter(Mandatory = $false)][int] $TimeoutSec = 90
    )

    $headers = @{
        'Authorization'    = "Bearer $Token"
        'Accept'           = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $params = @{
                Uri             = $Uri
                Headers         = $headers
                Method          = $Method
                UseBasicParsing = $true
                TimeoutSec      = $TimeoutSec
            }
            if ($null -ne $Body) {
                $params['Body']        = ($Body | ConvertTo-Json -Depth 6 -Compress)
                $params['ContentType'] = 'application/json'
            }
            $data = Invoke-RestMethod @params
            return [pscustomobject]@{ Ok = $true; Status = 200; Data = $data; Error = '' }
        }
        catch {
            $status     = $null
            $retryAfter = $null
            if ($null -ne $_.Exception.Response) {
                try { $status = [int] $_.Exception.Response.StatusCode } catch { $status = $null }
                try { $retryAfter = $_.Exception.Response.Headers['Retry-After'] } catch { $retryAfter = $null }
            }

            $isTransient = ($status -in 429, 500, 502, 503, 504) -or ($null -eq $status)

            if (-not $isTransient -or $attempt -gt $Retries) {
                return [pscustomobject]@{
                    Ok     = $false
                    Status = $(if ($null -eq $status) { 0 } else { $status })
                    Data   = $null
                    Error  = $_.Exception.Message
                }
            }

            $delay = [math]::Min(60, [math]::Pow(2, $attempt))
            if ($retryAfter -and ($retryAfter -as [int])) { $delay = [int] $retryAfter }
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-LocalTimeString {
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
    catch { return [string] $Utc }
}

function ConvertTo-SafeHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return ($Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
}

# -------------------------------------------------------------------------------------------
# Environment inventory
# -------------------------------------------------------------------------------------------
function Get-AllEnvironmentsAdmin {
    <#
        Enumerates EVERY Dataverse environment in the tenant using the Power Platform admin
        (BAP) surface. This is deliberately different from Global Discovery: discovery only
        returns environments the identity is already a user in, so on its own it can never tell
        an administrator what they are missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $false)][int] $Retries = 5
    )

    $uri  = "{0}?api-version={1}" -f $script:BapRoot, $script:BapApiVer
    $res  = Invoke-RestProbe -Uri $uri -Token $Token -Retries $Retries -TimeoutSec 180

    if (-not $res.Ok) {
        Write-Log -Level 'WARN' -Message ("Power Platform admin environment list unavailable (HTTP {0}). Falling back to Global Discovery only, which cannot show environments you lack access to. Detail: {1}" -f $res.Status, $res.Error)
        return @()
    }

    $out = New-Object System.Collections.Generic.List[object]
    if ($null -eq $res.Data -or ($res.Data.PSObject.Properties.Name -notcontains 'value')) { return @() }

    foreach ($e in $res.Data.value) {
        $props = $null
        if ($e.PSObject.Properties.Name -contains 'properties') { $props = $e.properties }
        if ($null -eq $props) { continue }

        $display = ''
        if ($props.PSObject.Properties.Name -contains 'displayName') { $display = [string] $props.displayName }

        $sku = ''
        if ($props.PSObject.Properties.Name -contains 'environmentSku') { $sku = [string] $props.environmentSku }

        $instanceUrl = ''
        $uniqueName  = ''
        if (($props.PSObject.Properties.Name -contains 'linkedEnvironmentMetadata') -and $null -ne $props.linkedEnvironmentMetadata) {
            $lem = $props.linkedEnvironmentMetadata
            if ($lem.PSObject.Properties.Name -contains 'instanceApiUrl' -and -not [string]::IsNullOrWhiteSpace($lem.instanceApiUrl)) {
                $instanceUrl = ([string] $lem.instanceApiUrl).TrimEnd('/')
            }
            elseif ($lem.PSObject.Properties.Name -contains 'instanceUrl' -and -not [string]::IsNullOrWhiteSpace($lem.instanceUrl)) {
                $instanceUrl = ([string] $lem.instanceUrl).TrimEnd('/')
            }
            if ($lem.PSObject.Properties.Name -contains 'uniqueName') { $uniqueName = [string] $lem.uniqueName }
        }

        $created = ''
        if ($props.PSObject.Properties.Name -contains 'createdTime') { $created = [string] $props.createdTime }

        $region = ''
        if ($props.PSObject.Properties.Name -contains 'azureRegion') { $region = [string] $props.azureRegion }

        $out.Add([pscustomobject]@{
            EnvironmentId = [string] $e.name
            DisplayName   = $display
            Sku           = $sku
            UniqueName    = $uniqueName
            InstanceUrl   = $instanceUrl
            AzureRegion   = $region
            CreatedUtc    = $created
            HasDataverse  = -not [string]::IsNullOrWhiteSpace($instanceUrl)
        }) | Out-Null
    }

    return @($out.ToArray() | Sort-Object DisplayName)
}

function Get-DiscoverableEnvironments {
    <#
        Environments the signed-in identity is already a provisioned Dataverse user in.
        The set difference against the admin inventory is the actionable finding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $false)][int] $Retries = 5
    )

    $res = Invoke-RestProbe -Uri $script:DiscoUri -Token $Token -Retries $Retries
    if (-not $res.Ok) {
        Write-Log -Level 'WARN' -Message ("Global Discovery unavailable (HTTP {0}). Detail: {1}" -f $res.Status, $res.Error)
        return @()
    }

    $out = New-Object System.Collections.Generic.List[object]
    if ($null -ne $res.Data -and ($res.Data.PSObject.Properties.Name -contains 'value')) {
        foreach ($i in $res.Data.value) {
            $url = ''
            if ($i.PSObject.Properties.Name -contains 'ApiUrl' -and -not [string]::IsNullOrWhiteSpace($i.ApiUrl)) { $url = ([string] $i.ApiUrl).TrimEnd('/') }
            elseif ($i.PSObject.Properties.Name -contains 'Url' -and -not [string]::IsNullOrWhiteSpace($i.Url)) { $url = ([string] $i.Url).TrimEnd('/') }
            if ([string]::IsNullOrWhiteSpace($url)) { continue }

            $out.Add([pscustomobject]@{
                FriendlyName = $(if ($i.PSObject.Properties.Name -contains 'FriendlyName') { [string] $i.FriendlyName } else { '' })
                UrlName      = $(if ($i.PSObject.Properties.Name -contains 'UrlName') { [string] $i.UrlName } else { '' })
                Url          = $url
            }) | Out-Null
        }
    }
    return @($out.ToArray())
}

# -------------------------------------------------------------------------------------------
# Per-environment readiness probe
# -------------------------------------------------------------------------------------------
function Test-EnvironmentReadiness {
    <#
        The verdict here is driven by a REAL read against ConversationTranscript. Role names are
        collected for context and for the remediation text, but they never decide pass or fail -
        a custom role, a team-granted role, or an inherited privilege can all produce access that
        a role-name check would miss, and a role can exist without the privilege actually applying.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Environment,
        [Parameter(Mandatory = $true)][string] $Tenant,
        [Parameter(Mandatory = $true)][string] $Method,
        [Parameter(Mandatory = $false)][int] $Retries = 5,
        [Parameter(Mandatory = $false)][switch] $SkipRetention,
        [Parameter(Mandatory = $false)] $Zone
    )

    $r = [ordered]@{
        DisplayName        = $Environment.DisplayName
        EnvironmentId      = $Environment.EnvironmentId
        Sku                = $Environment.Sku
        InstanceUrl        = $Environment.InstanceUrl
        Reachable          = $false
        UserProvisioned    = $false
        SystemUserId       = ''
        Roles              = @()
        IsSystemAdmin      = $false
        HasTranscriptRole  = $false
        TranscriptRoleId   = ''
        CanReadTranscripts = $false
        TranscriptStatus   = 0
        CanReadBots        = $false
        AgentCount         = 0
        TranscriptCount    = 0
        OldestUtc          = $null
        NewestUtc          = $null
        SpanDays           = 0
        SupportsTranscripts= $true
        Blockers           = @()
        Notes              = @()
    }

    # Environment types that never write conversation transcripts, per Microsoft Learn. Detecting
    # this from the SKU avoids sending an admin on a permissions goose chase for data that will
    # never exist.
    if ($r.Sku -eq 'Developer') {
        $r.SupportsTranscripts = $false
        $r.Notes += 'Developer environment. Microsoft documents that transcripts are not stored for agents deployed in developer environments, regardless of permissions.'
    }
    elseif ($r.Sku -eq 'Teams') {
        $r.SupportsTranscripts = $false
        $r.Notes += 'Microsoft Dataverse for Teams environment. Microsoft documents that conversation transcripts are not written for these environments.'
    }

    if (-not $Environment.HasDataverse) {
        $r.Notes += 'No Dataverse database in this environment. Nothing to audit here.'
        $r.SupportsTranscripts = $false
        return [pscustomobject] $r
    }

    $envUrl = $Environment.InstanceUrl
    $token  = $null
    try { $token = Get-ResourceToken -Resource "$envUrl/" -Tenant $Tenant -Method $Method }
    catch {
        $r.Blockers += ("Could not obtain a token for this environment: {0}" -f $_.Exception.Message)
        return [pscustomobject] $r
    }
    if ([string]::IsNullOrWhiteSpace($token)) {
        $r.Blockers += 'Could not obtain a token for this environment.'
        return [pscustomobject] $r
    }

    $api = "$envUrl/api/data/v9.2"

    # 1. WhoAmI - proves the identity is a provisioned, enabled Dataverse user here.
    $who = Invoke-RestProbe -Uri "$api/WhoAmI" -Token $token -Retries $Retries
    if ($who.Ok) {
        $r.Reachable       = $true
        $r.UserProvisioned = $true
        if ($who.Data.PSObject.Properties.Name -contains 'UserId') { $r.SystemUserId = [string] $who.Data.UserId }
    }
    else {
        $r.TranscriptStatus = $who.Status
        if ($who.Status -eq 403) {
            $r.Blockers += 'The signed-in identity is not a provisioned, enabled user in this environment (WhoAmI returned HTTP 403). A Global Administrator is not automatically a Dataverse user. Add the account to this environment first.'
        }
        elseif ($who.Status -eq 401) {
            $r.Blockers += 'HTTP 401 acquiring access to this environment. The token audience or tenant does not match. Re-run with -AuthMethod DeviceCode and the correct -TenantId.'
        }
        else {
            $r.Blockers += ("Environment unreachable (HTTP {0}): {1}" -f $who.Status, $who.Error)
        }
        return [pscustomobject] $r
    }

    # 2. Security roles held - context for the remediation text only.
    if (-not [string]::IsNullOrWhiteSpace($r.SystemUserId)) {
        $roleRes = Invoke-RestProbe -Uri ("{0}/systemusers({1})/systemuserroles_association?`$select=name,roleid" -f $api, $r.SystemUserId) -Token $token -Retries $Retries
        if ($roleRes.Ok -and $null -ne $roleRes.Data -and ($roleRes.Data.PSObject.Properties.Name -contains 'value')) {
            $names = @()
            foreach ($role in $roleRes.Data.value) {
                if ($role.PSObject.Properties.Name -contains 'name') { $names += [string] $role.name }
            }
            $r.Roles         = @($names | Sort-Object -Unique)
            $r.IsSystemAdmin = @($r.Roles | Where-Object { $_ -eq 'System Administrator' }).Count -gt 0
            $r.HasTranscriptRole = @($r.Roles | Where-Object { $_ -like '*Transcript Viewer*' }).Count -gt 0
        }
        else {
            $r.Notes += 'Could not read the role assignments for this identity. Role context is unavailable, but the transcript read probe below is still authoritative.'
        }
    }

    # 3. Does the Bot Transcript Viewer role exist here, and what is its ID (needed to grant it)?
    $btvRes = Invoke-RestProbe -Uri ("{0}/roles?`$select=roleid,name&`$filter=name eq 'Bot Transcript Viewer'" -f $api) -Token $token -Retries $Retries
    if ($btvRes.Ok -and $null -ne $btvRes.Data -and ($btvRes.Data.PSObject.Properties.Name -contains 'value')) {
        $first = @($btvRes.Data.value) | Select-Object -First 1
        if ($first -and ($first.PSObject.Properties.Name -contains 'roleid')) { $r.TranscriptRoleId = [string] $first.roleid }
    }

    # 4. THE TRUTH TEST. Everything above is context; this is the verdict.
    $probe = Invoke-RestProbe -Uri ("{0}/conversationtranscripts?`$select=conversationtranscriptid&`$top=1" -f $api) -Token $token -Retries $Retries
    $r.TranscriptStatus = $probe.Status
    if ($probe.Ok) {
        $r.CanReadTranscripts = $true
    }
    else {
        if ($probe.Status -eq 403) {
            $r.Blockers += 'Read on the ConversationTranscript table is denied (HTTP 403). Assign the Bot Transcript Viewer security role to this identity in this environment. Environment Maker does not grant it.'
        }
        elseif ($probe.Status -eq 404) {
            $r.Blockers += 'The ConversationTranscript table was not found in this environment. Copilot Studio has most likely never been provisioned here.'
            $r.SupportsTranscripts = $false
        }
        else {
            $r.Blockers += ("ConversationTranscript read failed (HTTP {0}): {1}" -f $probe.Status, $probe.Error)
        }
    }

    # 5. Agent inventory - tells the admin whether this environment is even interesting.
    $botRes = Invoke-RestProbe -Uri ("{0}/bots?`$select=name,schemaname&`$top=250" -f $api) -Token $token -Retries $Retries
    if ($botRes.Ok -and $null -ne $botRes.Data -and ($botRes.Data.PSObject.Properties.Name -contains 'value')) {
        $r.CanReadBots = $true
        $r.AgentCount  = @($botRes.Data.value).Count
    }
    else {
        $r.Notes += 'Could not read the agent (bot) table, so agent friendly names will not resolve in the export. Grant read on the Bot table if friendly names matter.'
    }

    # 6. Retention horizon - measured, never assumed. The 30-day default is configurable.
    if ($r.CanReadTranscripts -and -not $SkipRetention) {
        $oldest = Invoke-RestProbe -Uri ("{0}/conversationtranscripts?`$select=conversationstarttime&`$orderby=conversationstarttime asc&`$top=1" -f $api) -Token $token -Retries $Retries
        $newest = Invoke-RestProbe -Uri ("{0}/conversationtranscripts?`$select=conversationstarttime&`$orderby=conversationstarttime desc&`$top=1" -f $api) -Token $token -Retries $Retries
        $count  = Invoke-RestProbe -Uri ("{0}/conversationtranscripts?`$select=conversationtranscriptid&`$count=true&`$top=1" -f $api) -Token $token -Retries $Retries

        if ($oldest.Ok -and $null -ne $oldest.Data -and ($oldest.Data.PSObject.Properties.Name -contains 'value')) {
            $o = @($oldest.Data.value) | Select-Object -First 1
            if ($o -and ($o.PSObject.Properties.Name -contains 'conversationstarttime')) { $r.OldestUtc = $o.conversationstarttime }
        }
        if ($newest.Ok -and $null -ne $newest.Data -and ($newest.Data.PSObject.Properties.Name -contains 'value')) {
            $n = @($newest.Data.value) | Select-Object -First 1
            if ($n -and ($n.PSObject.Properties.Name -contains 'conversationstarttime')) { $r.NewestUtc = $n.conversationstarttime }
        }
        if ($count.Ok -and $null -ne $count.Data -and ($count.Data.PSObject.Properties.Name -contains '@odata.count')) {
            $r.TranscriptCount = [int] $count.Data.'@odata.count'
        }

        if ($null -ne $r.OldestUtc -and $null -ne $r.NewestUtc) {
            try { $r.SpanDays = [int] ((([datetime]$r.NewestUtc) - ([datetime]$r.OldestUtc)).TotalDays) } catch { $r.SpanDays = 0 }
        }

        if ($r.TranscriptCount -eq 0 -and $null -eq $r.OldestUtc) {
            $r.Notes += 'Read access works but this environment currently holds ZERO transcripts. Either no agent has been used here, transcript recording is turned off for the environment, or the retention job has purged everything. Check the Power Platform admin center setting "Allow conversation transcripts and their associated metadata to be saved in Dataverse".'
        }
    }

    return [pscustomobject] $r
}

function Grant-TranscriptViewerRole {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)] $Result,
        [Parameter(Mandatory = $true)][string] $Tenant,
        [Parameter(Mandatory = $true)][string] $Method,
        [Parameter(Mandatory = $false)][int] $Retries = 5
    )

    if ([string]::IsNullOrWhiteSpace($Result.TranscriptRoleId)) {
        Write-Log -Level 'WARN' -Message ("{0}: Bot Transcript Viewer role not found in this environment; nothing to assign." -f $Result.DisplayName)
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($Result.SystemUserId)) {
        Write-Log -Level 'WARN' -Message ("{0}: identity is not a provisioned user here; add the user to the environment first." -f $Result.DisplayName)
        return $false
    }
    if (-not $Result.IsSystemAdmin) {
        Write-Log -Level 'WARN' -Message ("{0}: the signed-in identity does not hold System Administrator here, so it cannot assign roles to itself. Use the Power Platform admin center." -f $Result.DisplayName)
        return $false
    }

    $target = "{0} -> assign 'Bot Transcript Viewer' to {1}" -f $Result.DisplayName, $Result.SystemUserId
    if (-not $PSCmdlet.ShouldProcess($target, 'Assign Dataverse security role')) { return $false }

    $envUrl = $Result.InstanceUrl
    $token  = Get-ResourceToken -Resource "$envUrl/" -Tenant $Tenant -Method $Method
    $uri    = "{0}/api/data/v9.2/systemusers({1})/systemuserroles_association/`$ref" -f $envUrl, $Result.SystemUserId
    $body   = @{ '@odata.id' = ("{0}/api/data/v9.2/roles({1})" -f $envUrl, $Result.TranscriptRoleId) }

    $res = Invoke-RestProbe -Uri $uri -Token $token -Method 'Post' -Body $body -Retries $Retries
    if ($res.Ok) {
        Write-Log -Level 'OK' -Message ("{0}: Bot Transcript Viewer assigned." -f $Result.DisplayName)
        return $true
    }

    Write-Log -Level 'ERROR' -Message ("{0}: role assignment failed (HTTP {1}): {2}" -f $Result.DisplayName, $res.Status, $res.Error)
    return $false
}

function Connect-PurviewCompliance {
    <#
        Connects to Security and Compliance PowerShell, working around the two failures that make
        this step fail most often on a real admin workstation:

        1. "Method not found: ...Microsoft.Identity.Client.Broker.BrokerExtension.WithBroker(...)"
           This is an MSAL assembly version conflict, not a credential problem. It happens when an
           older Microsoft.Identity.Client.dll is already loaded into the session - commonly by an
           older ExchangeOnlineManagement version, or by the Az or Microsoft.Graph modules - and
           the newer broker code path cannot bind against it. The fix is to stop using the Windows
           broker (WAM) for this connection: Connect-IPPSSession -DisableWAM.

        2. Multiple ExchangeOnlineManagement versions installed side by side. PowerShell will
           happily import an older one. This function always imports the highest version explicitly.

        Returns $true on a usable session.
    #>
    [CmdletBinding()]
    param()

    $mod = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
           Sort-Object -Property Version -Descending |
           Select-Object -First 1

    if ($null -eq $mod) {
        Write-Log -Level 'WARN' -Message 'ExchangeOnlineManagement module is not installed, so Purview role groups cannot be checked.'
        Write-Log -Message '  Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force'
        return $false
    }

    $loaded = @(Get-Module -Name ExchangeOnlineManagement)
    if ($loaded.Count -gt 0 -and @($loaded | Where-Object { $_.Version -ne $mod.Version }).Count -gt 0) {
        Write-Log -Level 'WARN' -Message ("An older ExchangeOnlineManagement ({0}) is already loaded. Removing it so version {1} can be used." -f ($loaded[0].Version), $mod.Version)
        Remove-Module ExchangeOnlineManagement -Force -ErrorAction SilentlyContinue
    }

    try {
        Import-Module $mod.Path -ErrorAction Stop -WarningAction SilentlyContinue -Force | Out-Null
        Write-Log -Message ("Using ExchangeOnlineManagement {0}" -f $mod.Version)
    }
    catch {
        Write-Log -Level 'WARN' -Message ("Could not import ExchangeOnlineManagement: {0}" -f $_.Exception.Message)
        return $false
    }

    $supportsDisableWam = $false
    try { $supportsDisableWam = (Get-Command Connect-IPPSSession -ErrorAction Stop).Parameters.ContainsKey('DisableWAM') } catch { $supportsDisableWam = $false }

    # Attempt order: broker first (best single sign-on experience), then explicitly without the
    # broker. The second attempt is what recovers the WithBroker / "Method not found" failure.
    $attempts = New-Object System.Collections.Generic.List[object]
    $attempts.Add([pscustomobject]@{ Label = 'standard sign-in'; Splat = @{} }) | Out-Null
    if ($supportsDisableWam) {
        $attempts.Add([pscustomobject]@{ Label = 'sign-in with -DisableWAM (bypasses the Windows broker)'; Splat = @{ DisableWAM = $true } }) | Out-Null
    }

    foreach ($a in $attempts) {
        try {
            Write-Log -Level 'STEP' -Message ("Connecting to Security and Compliance PowerShell - {0}. A sign-in prompt is expected." -f $a.Label)
            $splat = $a.Splat.Clone()
            $splat['ErrorAction']   = 'Stop'
            $splat['WarningAction'] = 'SilentlyContinue'
            $splat['ShowBanner']    = $false
            Connect-IPPSSession @splat | Out-Null

            # Prove the session actually works rather than trusting a silent return.
            Get-RoleGroup -ResultSize 1 -ErrorAction Stop | Out-Null
            Write-Log -Level 'OK' -Message 'Connected to Security and Compliance PowerShell.'
            return $true
        }
        catch {
            $msg = $_.Exception.Message

            $isBrokerFault = ($msg -match 'WithBroker') -or
                             ($msg -match 'Method not found') -or
                             ($msg -match 'Microsoft\.Identity\.Client') -or
                             ($msg -match 'BrokerOptions')

            if ($isBrokerFault -and $a.Splat.Count -eq 0 -and $supportsDisableWam) {
                Write-Log -Level 'WARN' -Message 'MSAL broker (WAM) assembly conflict detected. Retrying without the broker ...'
                continue
            }

            Write-Log -Level 'WARN' -Message ("Could not connect to Security and Compliance PowerShell: {0}" -f $msg)

            if ($isBrokerFault) {
                Write-Host ''
                Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
                Write-Host '   MSAL BROKER (WAM) ASSEMBLY CONFLICT' -ForegroundColor Yellow
                Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
                Write-Host '   This is a module/assembly version conflict, NOT a credential or' -ForegroundColor White
                Write-Host '   permissions problem. An older Microsoft.Identity.Client.dll is' -ForegroundColor Gray
                Write-Host '   already loaded in this session. Try, in order:' -ForegroundColor Gray
                Write-Host ''
                Write-Host '   1. Close this window and run the check in a FRESH shell' -ForegroundColor White
                Write-Host '      (do not import Az or Microsoft.Graph first).' -ForegroundColor Gray
                Write-Host ''
                Write-Host '   2. Remove the older module versions, keeping only the newest:' -ForegroundColor White
                Write-Host '      Get-Module -ListAvailable ExchangeOnlineManagement |' -ForegroundColor Green
                Write-Host '          Sort-Object Version -Descending | Select-Object -Skip 1 |' -ForegroundColor Green
                Write-Host '          ForEach-Object { Uninstall-Module ExchangeOnlineManagement -RequiredVersion $_.Version -Force }' -ForegroundColor Green
                Write-Host ''
                Write-Host '   3. Update and retry:' -ForegroundColor White
                Write-Host '      Update-Module ExchangeOnlineManagement -Force' -ForegroundColor Green
                Write-Host ''
                Write-Host '   4. Connect manually, then re-run this script:' -ForegroundColor White
                Write-Host '      Connect-IPPSSession -DisableWAM' -ForegroundColor Green
                Write-Host ''
                Write-Host '   The Purview check is OPTIONAL. Dataverse readiness above is' -ForegroundColor Gray
                Write-Host '   unaffected and is the authoritative evidence path.' -ForegroundColor Gray
                Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
                Write-Host ''
            }
            return $false
        }
    }

    return $false
}

function Test-PurviewRoleGroupMembership {
    <#
        Purview role groups are not exposed through Microsoft Graph. This uses Security and
        Compliance PowerShell, which triggers its own sign-in, so it is opt-in.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string] $Upn)

    $out = New-Object System.Collections.Generic.List[object]

    # Reuse an existing session if one is already open, so a manual Connect-IPPSSession by the
    # operator (the documented workaround for a broker conflict) is honoured instead of re-prompting.
    $alreadyConnected = $false
    try {
        if (Get-Command Get-RoleGroup -ErrorAction SilentlyContinue) {
            Get-RoleGroup -ResultSize 1 -ErrorAction Stop | Out-Null
            $alreadyConnected = $true
            Write-Log -Level 'OK' -Message 'Reusing the existing Security and Compliance PowerShell session.'
        }
    }
    catch { $alreadyConnected = $false }

    if (-not $alreadyConnected) {
        if (-not (Connect-PurviewCompliance)) { return @() }
    }

    foreach ($rg in $script:PurviewRoleGroups) {
        $isMember = $false
        $exists   = $true
        try {
            $members = Get-RoleGroupMember -Identity $rg.Name -ErrorAction Stop
            foreach ($m in @($members)) {
                $candidates = @()
                foreach ($p in @('PrimarySmtpAddress', 'WindowsLiveID', 'Name', 'DisplayName', 'Alias')) {
                    if ($m.PSObject.Properties.Name -contains $p -and -not [string]::IsNullOrWhiteSpace([string]$m.$p)) { $candidates += [string] $m.$p }
                }
                if (@($candidates | Where-Object { $_ -ieq $Upn }).Count -gt 0) { $isMember = $true; break }
            }
        }
        catch {
            $exists = $false
        }

        $out.Add([pscustomobject]@{
            RoleGroup = $rg.Name
            Exists    = $exists
            IsMember  = $isMember
            Why       = $rg.Why
        }) | Out-Null
    }

    if (-not $alreadyConnected) {
        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch { }
    }

    return @($out.ToArray())
}

# -------------------------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------------------------
Write-Log -Level 'STEP' -Message '--- Copilot Studio audit readiness survey starting ---'
Write-Log -Message ("Auth method  : {0}" -f $AuthMethod)
if (-not [string]::IsNullOrWhiteSpace($TenantId)) { Write-Log -Message ("Target tenant: {0}" -f $TenantId) }

try   { $displayZone = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId) }
catch {
    Write-Log -Level 'WARN' -Message ("Unknown time zone '{0}'; falling back to Eastern Standard Time." -f $TimeZoneId)
    $displayZone = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')
    $TimeZoneId  = 'Eastern Standard Time'
}
$zoneLabel = ($displayZone.StandardName -replace '\s*Standard Time$', ' Time')

if ($AuthMethod -eq 'DeviceCode' -and [string]::IsNullOrWhiteSpace($TenantId)) {
    Write-Log -Level 'ERROR' -Message '-AuthMethod DeviceCode requires -TenantId <tenant GUID>. Find it in Entra admin center > Overview > Tenant ID.'
    return
}

# One interactive sign-in. Everything else is redeemed silently from the refresh token.
$bapToken = $null
try { $bapToken = Get-ResourceToken -Resource $script:BapResource -Tenant $TenantId -Method $AuthMethod -SuppliedToken $AccessToken }
catch {
    Write-Log -Level 'ERROR' -Message ("Sign-in failed: {0}" -f $_.Exception.Message)
    return
}

$identity = Get-TokenIdentityInfo -Token $bapToken
Write-Log -Level 'OK' -Message ("Signed in as    : {0}" -f $identity.Upn)
Write-Log -Message           ("Token tenant    : {0}" -f $identity.TenantId)
Write-Log -Message           ("Object ID       : {0}" -f $identity.ObjectId)

if ([string]::IsNullOrWhiteSpace($TenantId)) { $TenantId = $identity.TenantId }

Write-Log -Level 'STEP' -Message 'Enumerating every Dataverse environment in the tenant (Power Platform admin surface) ...'
$adminEnvs = @(Get-AllEnvironmentsAdmin -Token $bapToken -Retries $MaxRetries)
Write-Log -Level 'OK' -Message ("Admin inventory : {0} environment(s)." -f $adminEnvs.Count)

Write-Log -Level 'STEP' -Message 'Enumerating environments this identity is already a Dataverse user in (Global Discovery) ...'
$discoToken = $null
try { $discoToken = Get-ResourceToken -Resource $script:DiscoResource -Tenant $TenantId -Method $AuthMethod }
catch { Write-Log -Level 'WARN' -Message ("Could not acquire a Global Discovery token: {0}" -f $_.Exception.Message) }

$discoEnvs = @()
if (-not [string]::IsNullOrWhiteSpace($discoToken)) {
    $discoEnvs = @(Get-DiscoverableEnvironments -Token $discoToken -Retries $MaxRetries)
}
Write-Log -Level 'OK' -Message ("Discovery inventory: {0} environment(s) reachable by this identity." -f $discoEnvs.Count)

# If the admin surface was unavailable, fall back to discovery so the run still produces value.
if ($adminEnvs.Count -eq 0 -and $discoEnvs.Count -gt 0) {
    Write-Log -Level 'WARN' -Message 'Using the discovery inventory only. Environments this identity cannot reach will be invisible in this report.'
    $adminEnvs = @($discoEnvs | ForEach-Object {
        [pscustomobject]@{
            EnvironmentId = ''
            DisplayName   = $(if ([string]::IsNullOrWhiteSpace($_.FriendlyName)) { $_.UrlName } else { $_.FriendlyName })
            Sku           = '(unknown)'
            UniqueName    = $_.UrlName
            InstanceUrl   = $_.Url
            AzureRegion   = ''
            CreatedUtc    = ''
            HasDataverse  = $true
        }
    })
}

if ($adminEnvs.Count -eq 0) {
    Write-Log -Level 'ERROR' -Message 'No environments could be enumerated by either surface. Confirm the identity holds Global Administrator or Power Platform Administrator in this tenant.'
    return
}

# Optional narrowing.
$targets = $adminEnvs
if (-not [string]::IsNullOrWhiteSpace($EnvironmentUrl)) {
    $needle  = $EnvironmentUrl.TrimEnd('/').ToLowerInvariant()
    $targets = @($adminEnvs | Where-Object { $_.InstanceUrl -and $_.InstanceUrl.ToLowerInvariant() -eq $needle })
    if ($targets.Count -eq 0) {
        Write-Log -Level 'ERROR' -Message ("No environment in this tenant matches {0}." -f $EnvironmentUrl)
        return
    }
    Write-Log -Message ("Narrowed to a single environment: {0}" -f $targets[0].DisplayName)
}

$withDataverse = @($targets | Where-Object { $_.HasDataverse })
Write-Log -Message ("{0} of {1} environment(s) have a Dataverse database and will be probed." -f $withDataverse.Count, $targets.Count)

Write-Log -Level 'STEP' -Message 'Probing each environment (WhoAmI, roles, ConversationTranscript read, agents, retention) ...'
$results = New-Object System.Collections.Generic.List[object]
$idx = 0
foreach ($envItem in $targets) {
    $idx++
    Write-Log -Message ("[{0}/{1}] {2}" -f $idx, $targets.Count, $envItem.DisplayName)
    $res = Test-EnvironmentReadiness -Environment $envItem -Tenant $TenantId -Method $AuthMethod `
                                     -Retries $MaxRetries -SkipRetention:$SkipRetentionProbe -Zone $displayZone
    $results.Add($res) | Out-Null
}

# Optional self-grant.
$granted = 0
if ($GrantSelfTranscriptViewer) {
    Write-Log -Level 'STEP' -Message 'Attempting to assign Bot Transcript Viewer where it is missing ...'
    foreach ($res in $results) {
        if ($res.UserProvisioned -and -not $res.CanReadTranscripts -and $res.SupportsTranscripts) {
            if (Grant-TranscriptViewerRole -Result $res -Tenant $TenantId -Method $AuthMethod -Retries $MaxRetries) { $granted++ }
        }
    }
    if ($granted -gt 0) {
        Write-Log -Level 'OK' -Message ("{0} role assignment(s) made. Re-run this survey to confirm the read probe now passes." -f $granted)
    }
}

# Optional Purview role check.
$purview = @()
if ($CheckPurviewRoles) {
    $purview = @(Test-PurviewRoleGroupMembership -Upn $identity.Upn)
}

# -------------------------------------------------------------------------------------------
# Verdict
# -------------------------------------------------------------------------------------------
$ready        = @($results | Where-Object { $_.CanReadTranscripts })
$blockedPerm  = @($results | Where-Object { $_.SupportsTranscripts -and -not $_.CanReadTranscripts -and $_.UserProvisioned })
$blockedUser  = @($results | Where-Object { $_.SupportsTranscripts -and -not $_.UserProvisioned -and $_.InstanceUrl })
$notSupported = @($results | Where-Object { -not $_.SupportsTranscripts })
$withData     = @($ready | Where-Object { $_.TranscriptCount -gt 0 })

Write-Host ''
Write-Host '  ===================================================================' -ForegroundColor Cyan
Write-Host '   READINESS VERDICT' -ForegroundColor Cyan
Write-Host '  ===================================================================' -ForegroundColor Cyan
Write-Host ("   Signed in as            : {0}" -f $identity.Upn) -ForegroundColor White
Write-Host ("   Environments in tenant  : {0}" -f $targets.Count) -ForegroundColor White
Write-Host ("   Auditable now           : {0}" -f $ready.Count) -ForegroundColor $(if ($ready.Count -gt 0) { 'Green' } else { 'Red' })
Write-Host ("     ... holding data      : {0}" -f $withData.Count) -ForegroundColor Gray
Write-Host ("   Blocked - missing role  : {0}" -f $blockedPerm.Count) -ForegroundColor $(if ($blockedPerm.Count -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host ("   Blocked - not a user    : {0}" -f $blockedUser.Count) -ForegroundColor $(if ($blockedUser.Count -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host ("   Cannot hold transcripts : {0}" -f $notSupported.Count) -ForegroundColor Gray
Write-Host '  ===================================================================' -ForegroundColor Cyan
Write-Host ''

if ($Format -in @('Console', 'All')) {
    $rows = foreach ($res in $results) {
        if (-not $IncludeInaccessible -and -not $res.Reachable -and -not $res.SupportsTranscripts) { continue }
        $verdict =
            if (-not $res.SupportsTranscripts)   { 'N/A - no transcripts' }
            elseif ($res.CanReadTranscripts)     { 'READY' }
            elseif (-not $res.UserProvisioned)   { 'BLOCKED - not a user' }
            else                                 { 'BLOCKED - no role' }

        [pscustomobject]@{
            Environment = $(if ($res.DisplayName.Length -gt 34) { $res.DisplayName.Substring(0, 31) + '...' } else { $res.DisplayName })
            Sku         = $res.Sku
            Verdict     = $verdict
            Agents      = $res.AgentCount
            Transcripts = $res.TranscriptCount
            SpanDays    = $res.SpanDays
        }
    }
    if (@($rows).Count -gt 0) { $rows | Format-Table -AutoSize | Out-String | Write-Host }
}

# Remediation playbook, ordered by what unblocks the most.
Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
Write-Host '   REMEDIATION PLAYBOOK' -ForegroundColor Yellow
Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow

$step = 0
if ($blockedUser.Count -gt 0) {
    $step++
    Write-Host ("   {0}. ADD YOURSELF AS A USER in {1} environment(s):" -f $step, $blockedUser.Count) -ForegroundColor White
    foreach ($b in $blockedUser) { Write-Host ("      - {0}  ({1})" -f $b.DisplayName, $b.InstanceUrl) -ForegroundColor Gray }
    Write-Host '      Power Platform admin center > Environments > <env> > Settings >' -ForegroundColor DarkGray
    Write-Host '      Users + permissions > Users > Add user. A Global Administrator is NOT' -ForegroundColor DarkGray
    Write-Host '      automatically a Dataverse user. The account must also be licensed.' -ForegroundColor DarkGray
    Write-Host ''
}
if ($blockedPerm.Count -gt 0) {
    $step++
    Write-Host ("   {0}. ASSIGN 'Bot Transcript Viewer' in {1} environment(s):" -f $step, $blockedPerm.Count) -ForegroundColor White
    foreach ($b in $blockedPerm) { Write-Host ("      - {0}  ({1})" -f $b.DisplayName, $b.InstanceUrl) -ForegroundColor Gray }
    Write-Host '      Power Platform admin center > Environments > <env> > Settings >' -ForegroundColor DarkGray
    Write-Host '      Users + permissions > Users > <you> > Manage security roles.' -ForegroundColor DarkGray
    Write-Host '      Environment Maker does NOT grant transcript access.' -ForegroundColor DarkGray
    Write-Host '      Or re-run this script with -GrantSelfTranscriptViewer (needs System Administrator).' -ForegroundColor DarkGray
    Write-Host ''
}
$emptyReady = @($ready | Where-Object { $_.TranscriptCount -eq 0 })
if ($emptyReady.Count -gt 0) {
    $step++
    Write-Host ("   {0}. CHECK TRANSCRIPT RECORDING in {1} readable but empty environment(s):" -f $step, $emptyReady.Count) -ForegroundColor White
    foreach ($b in $emptyReady) { Write-Host ("      - {0}" -f $b.DisplayName) -ForegroundColor Gray }
    Write-Host '      Power Platform admin center > Environments > <env> > Settings >' -ForegroundColor DarkGray
    Write-Host '      Product > Features > "Allow conversation transcripts and their associated' -ForegroundColor DarkGray
    Write-Host '      metadata to be saved in Dataverse". On by default. Disabling takes up to' -ForegroundColor DarkGray
    Write-Host '      24 hours to take effect, and turning it back on is not retroactive.' -ForegroundColor DarkGray
    Write-Host ''
}
if ($CheckPurviewRoles -and @($purview).Count -gt 0) {
    $missing = @($purview | Where-Object { -not $_.IsMember })
    if ($missing.Count -gt 0) {
        $step++
        Write-Host ("   {0}. PURVIEW ROLE GROUPS you are NOT a member of ({1}):" -f $step, $missing.Count) -ForegroundColor White
        foreach ($m in $missing) { Write-Host ("      - {0}" -f $m.RoleGroup) -ForegroundColor Gray }
        Write-Host '      Purview portal > Settings > Roles and scopes > Role groups.' -ForegroundColor DarkGray
        Write-Host '      NOTE: these unblock the Purview evidence paths only. They do NOT' -ForegroundColor DarkGray
        Write-Host '      affect Dataverse transcript export, and membership in Content Explorer' -ForegroundColor DarkGray
        Write-Host '      Content Viewer is frequently NOT sufficient to surface Copilot Studio' -ForegroundColor DarkGray
        Write-Host '      prompt and response text in DSPM. See the runbook.' -ForegroundColor DarkGray
        Write-Host ''
    }
}
if ($step -eq 0) {
    Write-Host '   Nothing to remediate. Every environment that can hold transcripts is readable.' -ForegroundColor Green
    Write-Host ''
}

if ($ready.Count -gt 0) {
    Write-Host '  -------------------------------------------------------------------' -ForegroundColor Green
    Write-Host '   READY TO EXPORT - run these now' -ForegroundColor Green
    Write-Host '  -------------------------------------------------------------------' -ForegroundColor Green
    foreach ($res in ($ready | Sort-Object -Property TranscriptCount -Descending)) {
        Write-Host ("   # {0}  ({1} transcript(s), {2} day span)" -f $res.DisplayName, $res.TranscriptCount, $res.SpanDays) -ForegroundColor Gray
        Write-Host ("   .\Export-CopilotStudioTranscripts.ps1 -EnvironmentUrl {0} ``" -f $res.InstanceUrl) -ForegroundColor Cyan
        Write-Host ("       -TenantId {0} -AuthMethod DeviceCode -AllHistory" -f $TenantId) -ForegroundColor Cyan
        Write-Host ''
    }
}

# -------------------------------------------------------------------------------------------
# HTML report
# -------------------------------------------------------------------------------------------
$stampSuffix = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$utf8Bom     = New-Object System.Text.UTF8Encoding($true)
$written     = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    if ($PSCmdlet.ShouldProcess($OutputFolder, 'Create output folder')) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
}

if ($Format -in @('Html', 'All')) {
    $htmlPath = Join-Path $OutputFolder ("CopilotStudio-Readiness-{0}.html" -f $stampSuffix)
    if ($PSCmdlet.ShouldProcess($htmlPath, 'Write readiness report')) {

        $envRows = foreach ($res in ($results | Sort-Object -Property @{ Expression = { $_.CanReadTranscripts }; Descending = $true }, @{ Expression = { $_.TranscriptCount }; Descending = $true }, DisplayName)) {
            $cls = 'bad'; $verdict = 'BLOCKED - no role'
            if (-not $res.SupportsTranscripts) { $cls = 'na';  $verdict = 'Not applicable' }
            elseif ($res.CanReadTranscripts)   { $cls = 'good'; $verdict = 'READY' }
            elseif (-not $res.UserProvisioned) { $cls = 'bad'; $verdict = 'BLOCKED - not a Dataverse user' }

            $detail = New-Object System.Collections.Generic.List[string]
            foreach ($b in @($res.Blockers)) { $detail.Add("<div class=""blk"">$(ConvertTo-SafeHtml $b)</div>") | Out-Null }
            foreach ($n in @($res.Notes))    { $detail.Add("<div class=""nte"">$(ConvertTo-SafeHtml $n)</div>") | Out-Null }
            if (@($res.Roles).Count -gt 0) {
                $detail.Add("<div class=""rol""><b>Roles held:</b> $(ConvertTo-SafeHtml (($res.Roles) -join ', '))</div>") | Out-Null
            }

            $span = ''
            if ($null -ne $res.OldestUtc) {
                $span = "{0} to {1} ({2} day span)" -f (Get-LocalTimeString -Utc $res.OldestUtc -Zone $displayZone), (Get-LocalTimeString -Utc $res.NewestUtc -Zone $displayZone), $res.SpanDays
            }

            @"
<tr class="$cls">
  <td><b>$(ConvertTo-SafeHtml $res.DisplayName)</b><div class="url">$(ConvertTo-SafeHtml $res.InstanceUrl)</div></td>
  <td>$(ConvertTo-SafeHtml $res.Sku)</td>
  <td class="vd">$verdict</td>
  <td class="num">$($res.AgentCount)</td>
  <td class="num">$($res.TranscriptCount)</td>
  <td>$(ConvertTo-SafeHtml $span)</td>
  <td>$([string]::Join('', $detail))</td>
</tr>
"@
        }

        $purviewSection = ''
        $gateRows = foreach ($g in $script:PurviewCaptureGates) {
            "<tr><td><b>$(ConvertTo-SafeHtml $g.Gate)</b></td><td>$(ConvertTo-SafeHtml $g.Fact)</td><td><code>$(ConvertTo-SafeHtml $g.Check)</code></td></tr>"
        }
        $gateSection = @"
<h2>Why Purview can show nothing even when every role is held</h2>
<div class="note warn">
  This is the single most misread part of Copilot Studio auditing. A Purview role group grants the
  right to <em>view</em> content that already exists. It does not cause Purview to <em>capture</em>
  anything. Microsoft's own DSPM permissions table marks <strong>Global Administrator as NOT able to
  view prompts and responses</strong>, and the DSPM known-issues page lists three separate conditions
  under which prompt and response text is legitimately blank. Meanwhile the Dataverse
  <code>conversationtranscript</code> row for that same interaction still exists and is fully readable.
  That asymmetry is expected behaviour, not a bug, and it is the reason this toolkit treats Dataverse
  as the authoritative source.
</div>
<table>
  <thead><tr><th>Gate</th><th>What Microsoft documents</th><th>How to check it</th></tr></thead>
  <tbody>$([string]::Join('', $gateRows))</tbody>
</table>
"@
        if ($CheckPurviewRoles -and @($purview).Count -gt 0) {
            $pRows = foreach ($p in $purview) {
                $pc = if ($p.IsMember) { 'good' } else { 'bad' }
                $ps = if (-not $p.Exists) { 'Role group not found' } elseif ($p.IsMember) { 'Member' } else { 'NOT a member' }
                "<tr class=""$pc""><td><b>$(ConvertTo-SafeHtml $p.RoleGroup)</b></td><td class=""vd"">$ps</td><td>$(ConvertTo-SafeHtml $p.Why)</td></tr>"
            }
            $purviewSection = @"
<h2>Microsoft Purview role groups</h2>
<div class="note warn">
  These unblock the <em>Purview</em> evidence paths only and have no effect on the Dataverse
  transcript export. Holding every one of them still does not guarantee prompt and response text
  appears - see the capture gates below.
</div>
<table>
  <thead><tr><th>Role group</th><th>Status</th><th>Why it matters</th></tr></thead>
  <tbody>$([string]::Join('', $pRows))</tbody>
</table>
"@
        }

        $html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Copilot Studio Audit Readiness</title>
<style>
:root{--bd:#d8dee4;--mut:#66717b;--acc:#0f6cbd;--bg:#f7f9fb;--ink:#1f2933}
*{box-sizing:border-box}
body{font-family:"Segoe UI",Arial,sans-serif;margin:0;background:var(--bg);color:var(--ink)}
header{background:#fff;border-bottom:1px solid var(--bd);padding:22px 28px}
h1{margin:0 0 6px;font-size:22px;font-weight:600}
h2{margin:26px 28px 10px;font-size:17px;font-weight:600}
.sub{color:var(--mut);font-size:13px;line-height:1.55}
.cards{display:flex;gap:12px;flex-wrap:wrap;padding:18px 28px 0}
.card{background:#fff;border:1px solid var(--bd);border-radius:6px;padding:12px 16px;min-width:150px}
.card .v{font-size:23px;font-weight:600;color:var(--acc)}
.card .k{font-size:11px;color:var(--mut);text-transform:uppercase;letter-spacing:.35px;margin-top:3px}
.card.ok .v{color:#137333}.card.no .v{color:#b3261e}
.note{margin:16px 28px 0;padding:12px 16px;border-radius:6px;font-size:13px;line-height:1.55;background:#eaf3fb;border:1px solid #a9cded}
.note.warn{background:#fdf3e3;border-color:#e8c98a}
.note code{background:#dbe9f5;padding:1px 5px;border-radius:3px}
table{width:calc(100% - 56px);margin:0 28px;border-collapse:collapse;background:#fff;border:1px solid var(--bd);border-radius:6px;overflow:hidden;font-size:13px}
th{background:#f2f5f8;text-align:left;padding:9px 12px;font-size:11px;text-transform:uppercase;letter-spacing:.35px;color:var(--mut);border-bottom:1px solid var(--bd)}
td{padding:10px 12px;border-bottom:1px solid #eef1f4;vertical-align:top}
td.num{text-align:right;font-variant-numeric:tabular-nums}
td.vd{font-weight:600;white-space:nowrap}
tr.good td.vd{color:#137333}tr.bad td.vd{color:#b3261e}tr.na td.vd{color:var(--mut)}
tr.good{background:#f4fbf5}tr.bad{background:#fdf6f5}
.url{color:var(--mut);font-size:11px;margin-top:2px;word-break:break-all}
.blk{color:#b3261e;margin-bottom:5px}
.nte{color:#7a5c00;margin-bottom:5px}
.rol{color:var(--mut);font-size:11.5px}
ol.play{margin:0 28px;padding:14px 18px 14px 38px;background:#fff;border:1px solid var(--bd);border-radius:6px;font-size:13px;line-height:1.65}
ol.play li{margin-bottom:12px}
code{font-family:Consolas,monospace;font-size:12px}
pre{background:#1f2933;color:#e8edf2;padding:12px 14px;border-radius:5px;overflow-x:auto;font-size:12px;margin:8px 0 0}
footer{padding:26px 28px 40px;color:var(--mut);font-size:12px;line-height:1.6}
</style></head><body>
<header>
  <h1>Copilot Studio Audit Readiness</h1>
  <div class="sub">
    <div>Signed in as: $(ConvertTo-SafeHtml $identity.Upn) &middot; tenant $(ConvertTo-SafeHtml $identity.TenantId)</div>
    <div>Generated: $(ConvertTo-SafeHtml (Get-LocalTimeString -Utc ([datetime]::UtcNow) -Zone $displayZone)) $(ConvertTo-SafeHtml $zoneLabel)</div>
    <div>Verdicts are based on a live read against the ConversationTranscript table in each environment, not on inspecting role names.</div>
  </div>
</header>
<div class="cards">
  <div class="card"><div class="v">$($targets.Count)</div><div class="k">Environments</div></div>
  <div class="card ok"><div class="v">$($ready.Count)</div><div class="k">Auditable now</div></div>
  <div class="card"><div class="v">$($withData.Count)</div><div class="k">Holding data</div></div>
  <div class="card no"><div class="v">$($blockedPerm.Count)</div><div class="k">Missing role</div></div>
  <div class="card no"><div class="v">$($blockedUser.Count)</div><div class="k">Not a user</div></div>
  <div class="card"><div class="v">$($notSupported.Count)</div><div class="k">Cannot hold transcripts</div></div>
</div>
<div class="note">
  <strong>Why a Global Administrator can still get nothing:</strong> Microsoft documents that
  tenant-level admin roles do not automatically grant Microsoft Dataverse data access, and that the
  Environment Maker role does not grant transcript access. The documented least-privilege role for
  reading agent transcripts is <code>Bot Transcript Viewer</code>, and it must be held
  <em>per environment</em>. There is no tenant-wide transcript table - every environment stores its
  own, so a complete tenant audit means running the export once per environment listed as READY below.
</div>
<div class="note warn">
  <strong>Environments that can never hold transcripts:</strong> Microsoft documents that conversation
  transcripts are not written for Microsoft 365 Copilot agents, for Microsoft Dataverse for Teams
  environments, or for agents deployed in <strong>Developer</strong> environments. Those are marked
  <em>Not applicable</em> below and no amount of permission granting will change that.
</div>
<h2>Environment readiness</h2>
<table>
  <thead><tr><th>Environment</th><th>SKU</th><th>Verdict</th><th>Agents</th><th>Transcripts</th><th>Retention actually available</th><th>Findings</th></tr></thead>
  <tbody>$([string]::Join('', $envRows))</tbody>
</table>
$purviewSection
$gateSection
<h2>Remediation playbook</h2>
<ol class="play">
  <li><b>Add the auditing identity as a Dataverse user</b> in every environment you intend to audit.
      Power Platform admin center &gt; Environments &gt; &lt;env&gt; &gt; Settings &gt; Users + permissions &gt; Users &gt; Add user.
      The account must be licensed. Being a Global Administrator is not enough.</li>
  <li><b>Assign the <code>Bot Transcript Viewer</code> security role</b> to that identity in each environment.
      Same path &gt; Users &gt; &lt;identity&gt; &gt; Manage security roles. Environment Maker does not grant it.</li>
  <li><b>Confirm transcript recording is on</b> for the environment:
      Settings &gt; Product &gt; Features &gt; "Allow conversation transcripts and their associated metadata to be
      saved in Dataverse". On by default. Disabling takes up to 24 hours to take effect and is not
      retroactive when re-enabled.</li>
  <li><b>Decide how far back you need evidence</b> before you need it. Default Dataverse retention is
      30 days, enforced by the bulk deletion job named "Bulk Delete Conversation Transcript Records
      Older Than 1 Month". An administrator can cancel that job and create one with a longer window.
      Anything already purged is unrecoverable by any tool.</li>
  <li><b>Re-run this survey</b> to confirm the read probe now passes, then run the export per environment.</li>
</ol>
<h2>Next command</h2>
<pre>$(ConvertTo-SafeHtml (($ready | ForEach-Object { ".\Export-CopilotStudioTranscripts.ps1 -EnvironmentUrl $($_.InstanceUrl) ``" + [Environment]::NewLine + "    -TenantId $TenantId -AuthMethod DeviceCode -AllHistory" }) -join ([Environment]::NewLine + [Environment]::NewLine)))</pre>
<footer>
  Readiness verdicts reflect this identity at this moment. Re-run after any role change.
  This report names environments and roles; handle it per your organization's privacy requirements.
</footer>
</body></html>
"@
        [System.IO.File]::WriteAllText($htmlPath, $html, $utf8Bom)
        $written.Add($htmlPath) | Out-Null
        Write-Log -Level 'OK' -Message "Readiness report written: $htmlPath"
    }
}

$logPath = Join-Path $OutputFolder ("Readiness-Log-{0}.txt" -f $stampSuffix)
if ($PSCmdlet.ShouldProcess($logPath, 'Write run log')) {
    [System.IO.File]::WriteAllText($logPath, ($script:LogLines -join "`r`n"), $utf8Bom)
}

$elapsed = (Get-Date) - $script:RunStart
Write-Log -Level 'STEP' -Message ('--- Readiness survey complete in {0:N1}s ---' -f $elapsed.TotalSeconds)
