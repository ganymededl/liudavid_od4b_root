Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $RepoRoot
try {
  git pull --rebase

  $status = git status --porcelain -- data/pocketcasts-starred.json
  if (-not $status) {
    Write-Host "No Pocket Casts feed changes to publish."
    exit 0
  }

  git add data/pocketcasts-starred.json
  git commit -m "chore: refresh Pocket Casts starred feed"
  git push origin main
  Write-Host "Published Pocket Casts Starred feed to main."
}
finally {
  Pop-Location
}
