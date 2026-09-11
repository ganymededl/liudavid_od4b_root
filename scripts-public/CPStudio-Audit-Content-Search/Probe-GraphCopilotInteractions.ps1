<#
    Probe: does Microsoft Graph return the full PROMPT and RESPONSE text for first-party
    Microsoft 365 Copilot agent interactions (e.g. the Microsoft 365 Admin agent)?

    Purview DSPM Activity Explorer renders the user's prompt but has no Response field at all for
    these agents, so this tests the documented programmatic alternative:
        GET /beta/copilot/users/{userId}/interactionHistory/getAllEnterpriseInteractions

    Read-only. Device code sign-in. No modules required.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $TenantId,
    [Parameter(Mandatory = $true)][string] $UserUpn,
    [Parameter(Mandatory = $false)][int]   $Hours = 24,
    [Parameter(Mandatory = $false)][string] $OutputFolder = 'C:\Scout_Output\FirstParty-Agent-Audit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'   # Microsoft Graph PowerShell, pre-consented
$scope    = 'https://graph.microsoft.com/AiEnterpriseInteraction.Read.All offline_access openid profile'
$authority = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0"

Write-Host ''
Write-Host '  Requesting device code for Microsoft Graph ...' -ForegroundColor Cyan

$code = Invoke-RestMethod -Method Post -Uri "$authority/devicecode" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{ client_id = $clientId; scope = $scope } -UseBasicParsing

Write-Host ''
Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
Write-Host ("   1. Open : {0}" -f $code.verification_uri) -ForegroundColor White
Write-Host ("   2. Code : {0}" -f $code.user_code) -ForegroundColor Green
Write-Host '  -------------------------------------------------------------------' -ForegroundColor Yellow
Write-Host ''

$token   = $null
$expires = (Get-Date).AddSeconds([int]$code.expires_in)
$interval = 5
if (($code.PSObject.Properties.Name -contains 'interval') -and $code.interval) { $interval = [int]$code.interval }

while ((Get-Date) -lt $expires -and $null -eq $token) {
    Start-Sleep -Seconds $interval
    try {
        $r = Invoke-RestMethod -Method Post -Uri "$authority/token" `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{
                grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                client_id   = $clientId
                device_code = $code.device_code
            } -UseBasicParsing
        $token = $r.access_token
    }
    catch {
        $body = ''
        if ($null -ne $_.ErrorDetails) { $body = [string]$_.ErrorDetails.Message }
        if ($body -notmatch 'authorization_pending' -and $body -notmatch 'slow_down') {
            Write-Host "  Sign-in failed: $body" -ForegroundColor Red
            return
        }
        if ($body -match 'slow_down') { $interval += 5 }
    }
}

if ($null -eq $token) { Write-Host '  Timed out.' -ForegroundColor Red; return }
Write-Host '  Signed in.' -ForegroundColor Green

# Confirm the scope actually landed in the token.
$parts = $token.Split('.')
$p = $parts[1].Replace('-','+').Replace('_','/')
switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
Write-Host ("  Token scopes: {0}" -f $claims.scp) -ForegroundColor DarkGray

$headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
$since   = (Get-Date).ToUniversalTime().AddHours(-$Hours).ToString('yyyy-MM-ddTHH:mm:ssZ')

$uri = "https://graph.microsoft.com/beta/copilot/users/$UserUpn/interactionHistory/getAllEnterpriseInteractions?`$filter=createdDateTime gt $since&`$top=50"
Write-Host ''
Write-Host "  GET $uri" -ForegroundColor DarkGray

$all = New-Object System.Collections.Generic.List[object]
$page = 0
try {
    while (-not [string]::IsNullOrWhiteSpace($uri)) {
        $page++
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -UseBasicParsing -TimeoutSec 120
        if ($resp.PSObject.Properties.Name -contains 'value') {
            foreach ($i in $resp.value) { $all.Add($i) | Out-Null }
        }
        Write-Host ("  Page {0}: cumulative {1} interaction(s)" -f $page, $all.Count) -ForegroundColor Gray
        $uri = ''
        if ($resp.PSObject.Properties.Name -contains '@odata.nextLink') { $uri = [string]$resp.'@odata.nextLink' }
        if ($page -ge 10) { break }
    }
}
catch {
    Write-Host ''
    Write-Host ("  REQUEST FAILED: {0}" -f $_.Exception.Message) -ForegroundColor Red
    if ($null -ne $_.ErrorDetails) { Write-Host ("  Detail: {0}" -f $_.ErrorDetails.Message) -ForegroundColor DarkRed }
    return
}

Write-Host ''
Write-Host ("  TOTAL: {0} interaction(s) in the last {1}h" -f $all.Count, $Hours) -ForegroundColor Green

if ($all.Count -eq 0) { Write-Host '  Nothing returned.' -ForegroundColor Yellow; return }

# What shape did we get? This is the whole point of the probe.
Write-Host ''
Write-Host '  --- PROPERTIES ON THE FIRST ITEM ---' -ForegroundColor Cyan
$all[0].PSObject.Properties.Name | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor Gray }

Write-Host ''
Write-Host '  --- INTERACTION TYPES PRESENT ---' -ForegroundColor Cyan
$all | Group-Object -Property interactionType | ForEach-Object {
    Write-Host ("    {0,-16} {1}" -f $_.Name, $_.Count) -ForegroundColor Gray
}

Write-Host ''
Write-Host '  --- APP CLASS / AGENT ATTRIBUTION ---' -ForegroundColor Cyan
$all | Group-Object -Property appClass | ForEach-Object {
    Write-Host ("    {0,-30} {1}" -f $_.Name, $_.Count) -ForegroundColor Gray
}

Write-Host ''
Write-Host '  --- SAMPLE: FIRST 6 TURNS (does RESPONSE body text come back?) ---' -ForegroundColor Cyan
foreach ($i in ($all | Sort-Object createdDateTime | Select-Object -First 6)) {
    $type = if ($i.PSObject.Properties.Name -contains 'interactionType') { $i.interactionType } else { '?' }
    $body = ''
    if ($i.PSObject.Properties.Name -contains 'body' -and $null -ne $i.body -and
        $i.body.PSObject.Properties.Name -contains 'content') { $body = [string]$i.body.content }
    $clean = ($body -replace '<[^>]+>', ' ' -replace '\s+', ' ').Trim()
    $excerpt = if ($clean.Length -gt 220) { $clean.Substring(0,220) + ' ...' } else { $clean }

    $colour = if ($type -eq 'userPrompt') { 'White' } else { 'Cyan' }
    Write-Host ''
    Write-Host ("    [{0}] {1}  chars={2}" -f $type, $i.createdDateTime, $clean.Length) -ForegroundColor $colour
    Write-Host ("      {0}" -f $excerpt) -ForegroundColor Gray
}

if (-not (Test-Path -LiteralPath $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$jsonPath = Join-Path $OutputFolder "GraphInteractions-RAW-$stamp.json"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($jsonPath, ($all | ConvertTo-Json -Depth 12), $utf8Bom)
Write-Host ''
Write-Host ("  Raw JSON written: {0}" -f $jsonPath) -ForegroundColor Green
