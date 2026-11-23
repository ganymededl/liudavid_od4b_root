param(
  [string]$TaskName = "PH-PocketCasts-Starred-Sync",
  [string]$At = "06:30"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Runner = (Resolve-Path (Join-Path $PSScriptRoot "run-pocketcasts-starred-sync.ps1")).Path
$PowerShellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
$Argument = "-NoProfile -ExecutionPolicy Bypass -File `"$Runner`""

$action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $Argument -WorkingDirectory (Split-Path $Runner -Parent)
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "Registered task '$TaskName' at $At (daily)."
Write-Host "Manual run: schtasks /Run /TN `"$TaskName`""
