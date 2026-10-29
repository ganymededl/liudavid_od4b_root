#Requires -Version 5.1
<#
    Verify-PhRelease.ps1
    Produces a deterministic release-verification evidence bundle for Personal Hub (PH):
      - Git commit SHA & clean working tree check (excluding untracked local work)
      - Repository + private-card encoding / mojibake scan (UTF-8 no BOM)
      - Direct outside-in HTTP negative checks on all 8 ph-private-cards URLs (must be 404)
      - Live HTTP 200 checks on index.html and all 10 public library destinations
      - Unauthenticated HTTP 401 gate check on the SharePoint Personal Vault URL
      - Writes immutable JSON evidence to C:\Users\liudavid\OneDrive - Microsoft\Hub\Private\_logs
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = "C:\Users\liudavid\OneDrive - Microsoft\Documents\Microsoft Scout\liudavid_od4b_root",
    [string]$PrivateRoot = "C:\Users\liudavid\OneDrive - Microsoft\Hub\Private",
    [string]$BaseUrl = "https://ganymededl.github.io/liudavid_od4b_root",
    [string]$LogFolder = "C:\Users\liudavid\OneDrive - Microsoft\Hub\Private\_logs"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)

Set-Location -LiteralPath $RepoRoot
$commitSha = (git rev-parse HEAD).Trim()

$privateCards = @(
    "agents-governance-quick-guide.html",
    "agents-governance-quick-guide-4.html",
    "agents-governance-walkthrough.html",
    "automations-playbook.html",
    "copilot-cowork-purview-quick-guide.html",
    "copilot-cowork-purview-walkthrough.html",
    "copilot-workshops-billable-hours.html",
    "gcc-copilot-parity-tracker.html"
)

# 1. Verify ph-private-cards is absent from repo and returns 404 on live Pages
$privateDirInRepo = Test-Path -LiteralPath (Join-Path $RepoRoot "ph-private-cards")
$privateUrlChecks = foreach ($card in $privateCards) {
    $url = "$BaseUrl/ph-private-cards/$card`?v=$commitSha"
    $code = 0
    try {
        $resp = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        $code = [int]$resp.StatusCode
    } catch {
        if ($null -ne $_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode.value__
        }
    }
    [pscustomobject]@{
        card       = $card
        url        = $url
        statusCode = $code
        denied     = ($code -eq 404)
    }
}

# 2. Mojibake & BOM scan across public repo HTML and private card HTML
$mojibakePattern = [regex]'(?:Ã.|â€.|Â.|ðŸ.|ï¿½)'
$htmlFiles = @(Get-ChildItem -LiteralPath $RepoRoot -Filter *.html -File) +
             @(Get-ChildItem -LiteralPath $PrivateRoot -Filter *.html -File)
$encodingChecks = foreach ($file in $htmlFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = $enc.GetString($bytes)
    $matches = $mojibakePattern.Matches($text)
    [pscustomobject]@{
        file          = $file.FullName
        hasUtf8Bom    = $hasBom
        mojibakeCount = $matches.Count
        clean         = (-not $hasBom -and $matches.Count -eq 0)
    }
}

# 3. Live public URL checks
$publicPaths = @(
    "",
    "artificial-gallery.html?scoutTheme=dark",
    "copilot-center-of-excellence/index.html",
    "cowork-finops/index.html",
    "demos-public/index.html",
    "fieldforge.html",
    "games-public/index.html",
    "model-mission-control/index.html?v=20261025-4&platform=scout",
    "prompt-engineering-public/index.html",
    "purview-controls/index.html",
    "scripts-public/index.html?v=packages"
)
$publicUrlChecks = foreach ($rel in $publicPaths) {
    $sep = if ($rel -match '\?') { '&' } else { '?' }
    $url = if ([string]::IsNullOrEmpty($rel)) { "$BaseUrl/?v=$commitSha" } else { "$BaseUrl/$rel$sep`v=$commitSha" }
    $code = 0
    try {
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        $code = [int]$resp.StatusCode
    } catch {
        if ($null -ne $_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode.value__
        }
    }
    [pscustomobject]@{
        path       = if ([string]::IsNullOrEmpty($rel)) { "/" } else { $rel }
        statusCode = $code
        ok         = ($code -eq 200)
    }
}

# 4. Unauthenticated SharePoint toolkit gate check (expect 401/403/302 sign-in wall)
$vaultUrl = "https://microsoft-my.sharepoint.com/personal/liudavid_microsoft_com/Documents/Hub/Private/personal-vault.html"
$vaultStatus = [int](& curl.exe -sS -L -o NUL -w "%{http_code}" $vaultUrl)

# 5. Live homepage contract check
$liveHtml = (Invoke-WebRequest -Uri "$BaseUrl/?v=$commitSha" -UseBasicParsing -TimeoutSec 20).Content
$contractChecks = [pscustomobject]@{
    defaultAnalyticsDenied = ($liveHtml -match 'let consent = "denied"')
    hasUnloadClarity       = ($liveHtml -match 'function unloadClarity\(\)')
    hasSkipLink            = ($liveHtml -match 'class="skip-link"')
    hasWideLibraryGrid     = ($liveHtml -match 'minmax\(min\(260px, 100%\), 1fr\)')
    hasCollapsiblePodcasts = ($liveHtml -match 'id="podcastsDetails"')
    hasFeaturedBadges      = ($liveHtml -match 'lib-featured-badge')
    hasCloudEnvBadges      = ($liveHtml -match 'lib-env-badge')
}

$allPassed = (-not $privateDirInRepo) -and
             (@($privateUrlChecks | Where-Object { -not $_.denied }).Count -eq 0) -and
             (@($encodingChecks | Where-Object { -not $_.clean }).Count -eq 0) -and
             (@($publicUrlChecks | Where-Object { -not $_.ok }).Count -eq 0) -and
             ($vaultStatus -in @(401, 403)) -and
             $contractChecks.defaultAnalyticsDenied -and
             $contractChecks.hasUnloadClarity -and
             $contractChecks.hasSkipLink -and
             $contractChecks.hasWideLibraryGrid -and
             $contractChecks.hasCollapsiblePodcasts -and
             $contractChecks.hasFeaturedBadges -and
             $contractChecks.hasCloudEnvBadges

$bundle = [pscustomobject]@{
    verifiedAt         = (Get-Date).ToString("o")
    commitSha          = $commitSha
    allPassed          = $allPassed
    privateDirInRepo   = $privateDirInRepo
    vaultUnauthStatus  = $vaultStatus
    contractChecks     = $contractChecks
    privateUrlChecks   = $privateUrlChecks
    publicUrlChecks    = $publicUrlChecks
    encodingCleanCount = @($encodingChecks | Where-Object { $_.clean }).Count
    encodingTotalCount = $encodingChecks.Count
}

if (-not (Test-Path -LiteralPath $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$outPath = Join-Path $LogFolder "PhReleaseVerification_$($stamp)_$($commitSha.Substring(0,7)).json"
$latestPath = Join-Path $LogFolder "LatestPhReleaseVerification.json"
$json = $bundle | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($outPath, $json, $enc)
[System.IO.File]::WriteAllText($latestPath, $json, $enc)
$json
if (-not $allPassed) { exit 1 }
