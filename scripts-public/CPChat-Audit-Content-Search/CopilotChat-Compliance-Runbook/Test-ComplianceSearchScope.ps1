<#
.SYNOPSIS
    Validates that every mailbox you intend to put in a Content Search actually exists,
    BEFORE the search is created.

.DESCRIPTION
    New-ComplianceSearch accepts -ExchangeLocation values that do not resolve to a real
    mailbox. It does not error, it does not warn - the location simply contributes zero
    items. The resulting export looks perfectly healthy and is quietly missing that user's
    entire history.

    This was a real failure in the pilot: the search was scoped to
    "aadi.kapoor@contoso.onmicrosoft.com" while the account's actual UPN was
    "AadiK@contoso.onmicrosoft.com". The export came back with only the admin's mailbox and
    nothing indicated a problem.

    Run this first. It resolves each address against Exchange Online and refuses to emit a
    location list unless every entry resolves.

.PARAMETER Mailbox
    One or more UPNs, aliases, display names, or SMTP addresses to validate.

.PARAMETER MailboxFile
    Optional text file with one identity per line (blank lines and # comments ignored).

.EXAMPLE
    Connect-IPPSSession
    Connect-ExchangeOnline
    .\Test-ComplianceSearchScope.ps1 -Mailbox AadiK@contoso.onmicrosoft.com,admin@contoso.onmicrosoft.com
#>
[CmdletBinding()]
param (
    [string[]] $Mailbox,
    [string]   $MailboxFile
)

$ErrorActionPreference = 'Stop'

if ($MailboxFile) {
    if (-not (Test-Path $MailboxFile)) { Write-Error "Mailbox file not found: $MailboxFile" }
    $Mailbox = @($Mailbox) + @(Get-Content $MailboxFile |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })
}
$Mailbox = @($Mailbox | Where-Object { $_ } | Select-Object -Unique)
if ($Mailbox.Count -eq 0) { Write-Error 'Supply at least one identity via -Mailbox or -MailboxFile.' }

if (-not (Get-Command Get-Recipient -ErrorAction SilentlyContinue)) {
    Write-Error 'Get-Recipient is unavailable. Run Connect-ExchangeOnline first.'
}

$results = foreach ($id in $Mailbox) {
    $r = $null
    try { $r = Get-Recipient -Identity $id -ErrorAction Stop } catch { }
    if ($r) {
        [pscustomobject]@{
            Requested    = $id
            Resolved     = $true
            ResolvedUpn  = $r.PrimarySmtpAddress
            DisplayName  = $r.DisplayName
            Type         = $r.RecipientTypeDetails
            ExactMatch   = ($id -ieq [string]$r.PrimarySmtpAddress)
        }
    } else {
        [pscustomobject]@{
            Requested = $id; Resolved = $false; ResolvedUpn = $null
            DisplayName = $null; Type = $null; ExactMatch = $false
        }
    }
}

$results | Format-Table Requested, Resolved, ResolvedUpn, DisplayName, Type -AutoSize

$bad = @($results | Where-Object { -not $_.Resolved })
$renamed = @($results | Where-Object { $_.Resolved -and -not $_.ExactMatch })

if ($renamed.Count -gt 0) {
    Write-Host ''
    Write-Host "$($renamed.Count) identity/identities resolved to a different primary address - use the resolved value:" -ForegroundColor Yellow
    $renamed | ForEach-Object { Write-Host ("  {0}  ->  {1}" -f $_.Requested, $_.ResolvedUpn) -ForegroundColor Yellow }
}

if ($bad.Count -gt 0) {
    Write-Host ''
    Write-Host "$($bad.Count) identity/identities DID NOT RESOLVE. A Content Search scoped to these will silently return nothing for them:" -ForegroundColor Red
    $bad | ForEach-Object { Write-Host "  $($_.Requested)" -ForegroundColor Red }
    Write-Host ''
    Write-Error 'Fix the mailbox list before creating the Content Search.'
}

$locations = ($results | Select-Object -ExpandProperty ResolvedUpn) -join ','
Write-Host ''
Write-Host "All $($results.Count) mailbox(es) resolved. Use this for -ExchangeLocation:" -ForegroundColor Green
Write-Host ''
Write-Host "  -ExchangeLocation `"$locations`"" -ForegroundColor Cyan
Write-Host ''
return $locations
