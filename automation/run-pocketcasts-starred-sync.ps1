Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$AutomationRoot = (Resolve-Path $PSScriptRoot).Path
$OutputFile = Join-Path $RepoRoot "data\pocketcasts-starred.json"

Push-Location $RepoRoot
try {
  npm --prefix $AutomationRoot run sync:pocketcasts -- --output $OutputFile --headless
}
finally {
  Pop-Location
}

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "publish-pocketcasts-starred.ps1")
