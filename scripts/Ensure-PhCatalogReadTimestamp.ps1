#Requires -Version 5.1
<#
    Ensure-PhCatalogReadTimestamp.ps1  (PH Weekly Card Timestamp Guard)
    Refreshes/validates the "Catalog read" marker on Personal Hub (PH) cards.
    Emits a JSON summary (stdout) plus a CSV + JSON run log. HTML is written
    as UTF-8 WITHOUT BOM on both PowerShell 5.1 and 7 (web-safe, no mojibake).

    PARAMETERS
      -Root <path>          PH card folder. Default: private OneDrive Hub\Private folder (outside public GitHub Pages)
      -StaleAfterDays <int> Age (days) before a marker is "stale". Default 10.
      -LogFolder <path>     Run-log output folder. Default: <Root>\_logs (outside public GitHub Pages)
      -Backup               Write <card>.<stamp>.bak before overwriting.
      -Rollback             Restore newest .bak for each card, then exit.
      -WhatIf               Preview writes; change nothing.
      -Force                Suppress the interactive banner.
      -Help                 Print this reference and exit (no file access).
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$Root = "C:\Users\liudavid\OneDrive - Microsoft\Hub\Private",
    [ValidateRange(1, 3650)][int]$StaleAfterDays = 10,
    [string]$LogFolder = "C:\Users\liudavid\OneDrive - Microsoft\Hub\Private\_logs",
    [switch]$Backup,
    [switch]$Rollback,
    [switch]$Force,
    [switch]$Help
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($Help) {
@"
Ensure-PhCatalogReadTimestamp.ps1  (PH Weekly Card Timestamp Guard)
  -Root <path>          PH card folder (default: C:\Users\liudavid\OneDrive - Microsoft\Hub\Private)
  -StaleAfterDays <int> Staleness threshold in days (default: 10)
  -LogFolder <path>     Run-log folder (default: <Root>\_logs)
  -Backup               Write <card>.<stamp>.bak before overwrite
  -Rollback             Restore newest .bak for each card, then exit
  -WhatIf               Preview writes only
  -Force                Suppress interactive banner
  -Help                 Print this and exit (no file access)
"@ | Write-Output
    return
}

function Write-Banner {
    if ($Force -or -not [Environment]::UserInteractive) { return }
    Write-Host "=================================================================="
    Write-Host " Ensure-PhCatalogReadTimestamp.ps1  (PH Weekly Card Timestamp Guard)"
    Write-Host "   PREVIEW  : -WhatIf    (shows writes, changes nothing)"
    Write-Host "   ROLLBACK : -Rollback  (restore newest .bak for each card)"
    Write-Host "   BACKUP   : -Backup    (<card>.<stamp>.bak before overwrite)"
    Write-Host "   HELP     : -Help      (print params and exit, no file access)"
    Write-Host "=================================================================="
}

# Engine-independent UTF-8 (no BOM) + pinned culture so writer and reader agree.
$enc     = New-Object System.Text.UTF8Encoding($false)
$culture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')

function Read-TextFile  { param([string]$Path) [System.IO.File]::ReadAllText($Path, $enc) }
function Write-TextFile { param([string]$Path, [string]$Text) [System.IO.File]::WriteAllText($Path, $Text, $enc) }

function TryParse-CatalogReadFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, "Catalog read:\s*([^|<]+)")
    if (-not $m.Success) { return $null }
    $raw = $m.Groups[1].Value.Trim()
    [datetime]$parsed = [datetime]::MinValue
    $styleLocal = [System.Globalization.DateTimeStyles]::AssumeLocal
    if ([datetime]::TryParseExact($raw, "MMMM d, yyyy 'at' h:mm tt", $culture, $styleLocal, [ref]$parsed)) { return $parsed }
    if ([datetime]::TryParse($raw, $culture, $styleLocal, [ref]$parsed)) { return $parsed }
    return $null
}

$now             = Get-Date
$utcIso          = $now.ToUniversalTime().ToString("o")
$localDate       = $now.ToString("yyyy-MM-dd")
$displayRead     = $now.ToString("MMMM d, yyyy 'at' h:mm tt", $culture)
$displayLine     = "Catalog read: $displayRead | PH weekly automation"
$lineHtml        = '<p class="meta" data-ph-catalog-read>' + $displayLine + '</p>'
$staleCutoff     = $now.AddDays(-1 * [Math]::Abs($StaleAfterDays))
$staleCutoffUtc  = $staleCutoff.ToUniversalTime()

$cards = @(
    "agents-governance-quick-guide.html",
    "agents-governance-quick-guide-4.html",
    "agents-governance-walkthrough.html",
    "automations-playbook.html",
    "copilot-cowork-purview-quick-guide.html",
    "copilot-cowork-purview-walkthrough.html",
    "copilot-workshops-billable-hours.html",
    "gcc-copilot-parity-tracker.html"
)

Write-Banner

if ($Rollback) {
    foreach ($card in $cards) {
        $path = Join-Path $Root $card
        $bak = Get-ChildItem -LiteralPath $Root -Filter ($card + ".*.bak") -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if ($null -ne $bak) {
            if ($PSCmdlet.ShouldProcess($path, "Restore from $($bak.Name)")) {
                Copy-Item -LiteralPath $bak.FullName -Destination $path -Force
                Write-Host "Restored $card from $($bak.Name)"
            }
        } else {
            Write-Warning "No backup found for $card"
        }
    }
    return
}

$markerRx = [regex]'(?is)<p[^>]*\bdata-ph-catalog-read\b[^>]*>.*?</p>'
$h1Rx     = [regex]'(?i)</h1>'
$bodyRx   = [regex]'(?i)<body[^>]*>'
$readRx   = [regex]'"readAt":"([^"]+)"'
$dateRx   = [regex]'"date":"[^"]+"'

$results = New-Object System.Collections.Generic.List[object]

foreach ($card in $cards) {
    $path        = Join-Path $Root $card
    $issueReason = New-Object System.Collections.Generic.List[string]
    $hadIssue    = $false
    $fixed       = $false
    $updated     = $false

    if (-not (Test-Path -LiteralPath $path)) {
        $results.Add([pscustomobject]@{
            file       = $card
            exists     = $false
            updated    = $false
            issueFound = $true
            issueFixed = $false
            issueReason = "file not found (manual fix required)"
        })
        continue
    }

    try {
        $original = Read-TextFile -Path $path
        $content  = $original

        if ($card -eq "copilot-workshops-billable-hours.html") {
            $rm = $readRx.Match($content)
            if (-not $rm.Success) {
                $hadIssue = $true
                [void]$issueReason.Add("missing readAt (manual fix required)")
            } else {
                [datetime]$parsedReadAt = [datetime]::MinValue
                $roundtrip = [System.Globalization.DateTimeStyles]::RoundtripKind
                if ([datetime]::TryParse($rm.Groups[1].Value, $culture, $roundtrip, [ref]$parsedReadAt)) {
                    if ($parsedReadAt.ToUniversalTime() -lt $staleCutoffUtc) {
                        $hadIssue = $true
                        [void]$issueReason.Add("stale readAt")
                    }
                } else {
                    $hadIssue = $true
                    [void]$issueReason.Add("invalid readAt")
                }
                $content = $readRx.Replace($content, { param($x) '"readAt":"' + $utcIso + '"' }, 1)
                if ($dateRx.IsMatch($content)) {
                    $content = $dateRx.Replace($content, { param($x) '"date":"' + $localDate + '"' }, 1)
                }
                if ($hadIssue) { $fixed = $true }
            }
        } else {
            $mk = $markerRx.Match($content)
            if ($mk.Success) {
                $existingRead = TryParse-CatalogReadFromText $mk.Value
                if ($null -eq $existingRead) {
                    $hadIssue = $true
                    [void]$issueReason.Add("invalid catalog-read marker")
                } elseif ($existingRead -lt $staleCutoff) {
                    $hadIssue = $true
                    [void]$issueReason.Add("stale catalog-read marker")
                }
                $content = $markerRx.Replace($content, { param($x) $lineHtml }, 1)
                if ($hadIssue) { $fixed = $true }
            } elseif ($h1Rx.IsMatch($content)) {
                $hadIssue = $true
                [void]$issueReason.Add("missing catalog-read marker")
                $content = $h1Rx.Replace($content, { param($x) $x.Value + "`r`n" + $lineHtml }, 1)
                $fixed = $true
            } elseif ($bodyRx.IsMatch($content)) {
                $hadIssue = $true
                [void]$issueReason.Add("missing catalog-read marker")
                $content = $bodyRx.Replace($content, { param($x) $x.Value + "`r`n" + $lineHtml }, 1)
                $fixed = $true
            } else {
                $hadIssue = $true
                [void]$issueReason.Add("no insertion point (manual fix required)")
            }
        }

        if ($content -ne $original) {
            if ($PSCmdlet.ShouldProcess($path, "Update catalog-read timestamp")) {
                if ($Backup) {
                    $bakPath = Join-Path $Root ($card + "." + $now.ToString("yyyyMMdd-HHmmss") + ".bak")
                    [System.IO.File]::WriteAllText($bakPath, $original, $enc)
                }
                Write-TextFile -Path $path -Text $content
                $updated = $true
            }
        }
    } catch {
        $hadIssue = $true
        [void]$issueReason.Add("io error: " + $_.Exception.Message)
    }

    $results.Add([pscustomobject]@{
        file       = $card
        exists     = $true
        updated    = $updated
        issueFound = $hadIssue
        issueFixed = $fixed
        issueReason = ($issueReason -join "; ")
    })
}

$issues     = @($results | Where-Object { $_.issueFound })
$unresolved = @($results | Where-Object { $_.issueFound -and -not $_.issueFixed })
$payload = [pscustomobject]@{
    checkedAt       = $now.ToString("o")
    root            = $Root
    staleAfterDays  = $StaleAfterDays
    whatIf          = [bool]$WhatIfPreference
    issueFound      = ($issues.Count -gt 0)
    issueCount      = $issues.Count
    fixedCount      = @($results | Where-Object { $_.updated }).Count
    unresolvedCount = $unresolved.Count
    needsManualFix  = ($unresolved.Count -gt 0)
    cards           = $results
}

if (-not $WhatIfPreference) {
    try {
        if (-not (Test-Path -LiteralPath $LogFolder)) {
            New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
        }
        $stamp = $now.ToString("yyyyMMdd-HHmmss")
        # CSV/JSON logs use Set-Content/Export-Csv UTF8 (BOM on 5.1) per house standard.
        $results | Export-Csv -LiteralPath (Join-Path $LogFolder "PhCatalogGuard_$stamp.csv") -NoTypeInformation -Encoding UTF8
        $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $LogFolder "PhCatalogGuard_$stamp.json") -Encoding UTF8
    } catch {
        Write-Warning ("Logging failed: " + $_.Exception.Message)
    }
}

$payload | ConvertTo-Json -Depth 6
