Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $RepoRoot
try {
  if ((Test-Path (Join-Path $RepoRoot ".git\rebase-merge")) -or (Test-Path (Join-Path $RepoRoot ".git\rebase-apply"))) {
    git rebase --quit
  }

  git pull --rebase

  $status = git status --porcelain -- data/pocketcasts-starred.json
  if (-not $status) {
    Write-Host "No Pocket Casts feed changes to publish."
    exit 0
  }

  git add --sparse data/pocketcasts-starred.json
  $staged = git diff --name-only --cached -- data/pocketcasts-starred.json
  if (-not $staged) {
    throw "Pocket Casts JSON is modified but was not staged. Sparse checkout may be blocking the path."
  }
  git commit -m "chore: refresh Pocket Casts starred feed"
  git push origin main
  Write-Host "Published Pocket Casts Starred feed to main."
}
finally {
  Pop-Location
}
