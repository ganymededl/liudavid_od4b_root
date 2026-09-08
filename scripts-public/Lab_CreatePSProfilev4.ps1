<#
ALWAYS Run with -Force & then relaunch PowerShell

.SYNOPSIS
    Deploys the LIUDAVID standard PowerShell profile to any machine.
    Run once per machine/user. Safe to re-run; will not overwrite existing profile
    unless -Force is specified.

.PARAMETER Force
    Overwrites existing profile if one already exists.

.EXAMPLE
    .\Deploy-PSProfile.ps1
    .\Deploy-PSProfile.ps1 -Force
#>

param(
    [switch]$Force
)

# ============================================================
# HELPERS (DEPLOY-TIME)
# ============================================================
function Test-IsAdmin {
    try {
        $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p   = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Ensure-PSGalleryTrusted {
    try {
        $repo = Get-PSRepository -Name 'PSGallery' -ErrorAction Stop
        if ($repo.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
        }
    } catch {
        # Non-fatal
    }
}

function Ensure-Module {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [switch]$Update,
        [switch]$AllowClobber
    )

    Ensure-PSGalleryTrusted

    $has = Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue
    if (-not $has) {
        $scope = if (Test-IsAdmin) { 'AllUsers' } else { 'CurrentUser' }
        try {
            Install-Module -Name $Name -Scope $scope -Force -ErrorAction Stop -AllowClobber:$AllowClobber
            Write-Host "[+] Installed module: $Name (Scope=$scope)" -ForegroundColor Green
        } catch {
            Write-Warning "[!] Failed to install module '$Name' (Scope=$scope). Error: $($_.Exception.Message)"
            return $false
        }
    }

    if ($Update) {
        try {
            Update-Module -Name $Name -Force -ErrorAction Stop | Out-Null
            Write-Host "[~] Updated module: $Name" -ForegroundColor Cyan
        } catch {
            # Keep quiet for MSI-installed modules (expected)
            if ($_.Exception.Message -match "was not installed by using Install-Module") {
                Write-Verbose "[Update-Module] '$Name' is MSI-installed; update skipped (expected)."
            } else {
                Write-Warning "[!] Update-Module failed for '$Name'. Continuing with installed version. Error: $($_.Exception.Message)"
            }
        }
    }

    return $true
}

# ============================================================
# DEPLOY-TIME: Bake SPO module install/update into deploy script
# ============================================================
$null = Ensure-Module -Name 'Microsoft.Online.SharePoint.PowerShell' -Update -AllowClobber

# ============================================================
# PROFILE CONTENT - Edit this here-string to update template
# ============================================================
$ProfileContent = @'
#region === PROFILE BOOTSTRAP: Create folders/file if missing ===
$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    Write-Host "Created profile directory: $profileDir" -ForegroundColor Green
}
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    Write-Host "Created profile file: $PROFILE" -ForegroundColor Green
}
#endregion

#region === CHOCOLATEY PATH (safe) ===
$chocoBin = "C:\ProgramData\chocolatey\bin"
if ($env:PATH -notlike "*$chocoBin*") {
    $env:PATH += ";$chocoBin"
}
#endregion

#region === CONSOLE APPEARANCE ===
try {
    $a = Get-Host
    $a.PrivateData.ErrorForegroundColor = 'Green'
} catch {}

try {
    $pshost   = Get-Host
    $pswindow = $pshost.UI.RawUI
    $pswindow.WindowTitle = "LIUDAVID PowerShell Session"

    $newsize        = $pswindow.BufferSize
    $newsize.height = 3000
    $newsize.width  = 150
    $pswindow.BufferSize = $newsize
} catch {}
#endregion

#region === UTILITY FUNCTIONS ===
function New-Shell { Start-Process powershell -Verb runAs }

function edit ($filepath) {
    & "C:\Program Files\Notepad++\notepad++.exe" $filepath
}

function Get-IPInfo ($ipaddress) {
    Invoke-RestMethod -Uri "https://ipinfo.io/$ipaddress" -Method Get
}
#endregion

#region === COLORIZED DIRECTORY LISTING ===
function LL {
    param ($dir = ".", $all = $false)
    $origFg = $host.UI.RawUI.ForegroundColor
    $toList = if ($all) { Get-ChildItem -Force $dir } else { Get-ChildItem $dir }

    foreach ($Item in $toList) {
        switch ($Item.Extension) {
            ".exe" { $host.UI.RawUI.ForegroundColor = "Yellow" }
            ".cmd" { $host.UI.RawUI.ForegroundColor = "Red" }
            ".msh" { $host.UI.RawUI.ForegroundColor = "Red" }
            ".vbs" { $host.UI.RawUI.ForegroundColor = "Red" }
            Default { $host.UI.RawUI.ForegroundColor = $origFg }
        }
        if ($Item.Mode.StartsWith("d")) { $host.UI.RawUI.ForegroundColor = "Green" }
        $Item
    }
    $host.UI.RawUI.ForegroundColor = $origFg
}

function lla { param ($dir = "."); LL $dir $true }
#endregion

#region === MODULE HELPERS (PROFILE RUNTIME) ===
function Test-IsAdmin {
    try {
        $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p   = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Ensure-PSGalleryTrusted {
    try {
        $repo = Get-PSRepository -Name 'PSGallery' -ErrorAction Stop
        if ($repo.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
        }
    } catch {}
}

function Ensure-Module {
    param([Parameter(Mandatory)][string]$Name, [switch]$Update, [switch]$AllowClobber)

    Ensure-PSGalleryTrusted

    $has = Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue
    if (-not $has) {
        $scope = if (Test-IsAdmin) { 'AllUsers' } else { 'CurrentUser' }
        Install-Module -Name $Name -Scope $scope -Force -AllowClobber:$AllowClobber -ErrorAction Stop | Out-Null
        Write-Host "[+] Installed module: $Name (Scope=$scope)" -ForegroundColor Green
    }

    if ($Update) {
        try {
            Update-Module -Name $Name -Force -ErrorAction Stop | Out-Null
            Write-Host "[~] Updated module: $Name" -ForegroundColor Cyan
        } catch {
            if ($_.Exception.Message -match "was not installed by using Install-Module") {
                Write-Verbose "[Update-Module] '$Name' is MSI-installed; update skipped (expected)."
            } else {
                Write-Warning "[!] Update-Module failed for '$Name'. Continuing with installed version. Error: $($_.Exception.Message)"
            }
        }
    }

    return $true
}
#endregion

#region === SPO (CBA ONLY, NO BROWSER, NO FALLBACK) ===
function Ensure-SPOModule {
    $name = 'Microsoft.Online.SharePoint.PowerShell'
    $mods = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending

    if (-not $mods) {
        try {
            Install-Module $name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            $mods = Get-Module -ListAvailable -Name $name | Sort-Object Version -Descending
        } catch {
            Write-Warning "[SPO] Module not installed and install failed: $($_.Exception.Message)"
            return $false
        }
    }

    $latest = $mods | Select-Object -First 1
    try {
        Import-Module $latest.Path -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Warning "[SPO] Import failed from '$($latest.Path)': $($_.Exception.Message)"
        return $false
    }
}

function Get-CertByThumbprint {
    param([Parameter(Mandatory)][string]$Thumbprint)

    foreach ($p in @("Cert:\CurrentUser\My\$Thumbprint","Cert:\LocalMachine\My\$Thumbprint")) {
        $c = Get-Item -Path $p -ErrorAction SilentlyContinue
        if ($c -and $c.HasPrivateKey) { return $c }
    }
    throw "Certificate with thumbprint [$Thumbprint] not found (or missing private key) in CurrentUser\My or LocalMachine\My."
}

function Connect-SPO-Contoso {
    if (-not (Ensure-SPOModule)) { throw "SPO module unavailable (import failed)." }

    $cert = Get-CertByThumbprint -Thumbprint $MCapsConfig.CertThumbprint
    Set-Variable -Name SPO_Contoso -Scope Global -Value (
        Connect-SPOService `
            -Url $MCapsConfig.SPOAdminUrl `
            -ClientId $MCapsConfig.AppId `
            -Tenant $MCapsConfig.TenantId `
            -Certificate $cert
    )
    Write-Host "Connected to SPO (app-only): $($MCapsConfig.SPOAdminUrl)" -ForegroundColor Cyan
}

function Connect-SPO-Source {
    if (-not (Ensure-SPOModule)) { throw "SPO module unavailable (import failed)." }

    $cert = Get-CertByThumbprint -Thumbprint $SourceConfig.CertThumbprint
    Set-Variable -Name SPO_Source -Scope Global -Value (
        Connect-SPOService `
            -Url $SourceConfig.SPOAdminUrl `
            -ClientId $SourceConfig.AppId `
            -Tenant $SourceConfig.TenantId `
            -Certificate $cert
    )
    Write-Host "Connected to SPO (app-only): $($SourceConfig.SPOAdminUrl)" -ForegroundColor Cyan
}

function Connect-SPO-Target {
    if (-not (Ensure-SPOModule)) { throw "SPO module unavailable (import failed)." }

    $cert = Get-CertByThumbprint -Thumbprint $TargetConfig.CertThumbprint
    Set-Variable -Name SPO_Target -Scope Global -Value (
        Connect-SPOService `
            -Url $TargetConfig.SPOAdminUrl `
            -ClientId $TargetConfig.AppId `
            -Tenant $TargetConfig.TenantId `
            -Certificate $cert
    )
    Write-Host "Connected to SPO (app-only): $($TargetConfig.SPOAdminUrl)" -ForegroundColor Cyan
}
#endregion

#region === GRAPH MODULE CHECK ===
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Warning "Microsoft.Graph not installed. Run: Install-Module Microsoft.Graph -Scope CurrentUser"
}
#endregion

#region === TENANT CONFIGS ===
$MCapsConfig = @{
    TenantId       = "83d06137-87cd-4597-ae4d-cb4b3ccfe3aa"
    AppId          = "00f25d7b-a6af-48df-98eb-e926d31e312f"
    CertThumbprint = "999107225014D0FA9D2BD727563BBC94C868B174"
    TenantName     = "Contoso MNgEN"
    SPOAdminUrl    = "https://MngEnvMCAP750904-admin.sharepoint.com"
    OrgDomain      = "MngEnvMCAP750904.onmicrosoft.com"
}

$SourceConfig = @{
    TenantId       = "e01e38dc-b7c2-44d9-ac9d-83ecb1363783"
    AppId          = "1f8e23cd-bccf-4688-9f05-493e9daa90aa"
    CertThumbprint = "1AF00BACA71D82AE4BAE8E81ACDDB80FD51FFD88"
    TenantName     = "itchyfeetnyc"
    SPOAdminUrl    = "https://itchyfeetnyc-admin.sharepoint.com"
    OrgDomain      = "itchyfeetnyc.onmicrosoft.com"
}

$TargetConfig = @{
    TenantId       = "e9346e66-6d2c-424c-a82c-0238f302c985"
    AppId          = "868cedc8-7b53-4e39-8279-e84aeb5b0201"
    CertThumbprint = "79686F97A9BA3540CEF255E23A0B84836BCA060E"
    TenantName     = "GOV254909"
    SPOAdminUrl    = "https://GOV254909-admin.sharepoint.com"
    OrgDomain      = "GOV254909.onmicrosoft.com"
}
#endregion

#region === CONNECT FUNCTIONS - IDENTITY (Graph-first; AzureAD optional) ===
function Connect-Identity {
    param([Parameter(Mandatory)][hashtable]$Cfg)

    Ensure-Module -Name 'Microsoft.Graph.Authentication' | Out-Null
    Connect-MgGraph -ClientId $Cfg.AppId `
                    -TenantId $Cfg.TenantId `
                    -CertificateThumbprint $Cfg.CertThumbprint `
                    -NoWelcome -ErrorAction Stop | Out-Null
    Write-Host "Connected to Microsoft Graph: $($Cfg.TenantName)" -ForegroundColor Green

    if (Get-Command Connect-AzureAD -ErrorAction SilentlyContinue) {
        try {
            Connect-AzureAD -TenantId $Cfg.TenantId `
                            -ApplicationId $Cfg.AppId `
                            -CertificateThumbprint $Cfg.CertThumbprint
            Write-Host "Connected to AzureAD module (optional): $($Cfg.TenantName)" -ForegroundColor Cyan
        } catch {
            Write-Warning "[!] Connect-AzureAD failed (optional) for $($Cfg.TenantName): $($_.Exception.Message)"
        }
    } else {
        Write-Warning "AzureAD module not found; skipping Connect-AzureAD. (Graph connection is established.)"
    }
}
#endregion

#region === CONNECT FUNCTIONS - EXO / TEAMS / SCC / PnP ===
function Connect-EXO {
    param([Parameter(Mandatory)][hashtable]$Cfg)
    Ensure-Module -Name 'ExchangeOnlineManagement' -Update -AllowClobber | Out-Null
    Connect-ExchangeOnline -AppId $Cfg.AppId `
                           -CertificateThumbprint $Cfg.CertThumbprint `
                           -Organization $Cfg.OrgDomain `
                           -ErrorAction Stop | Out-Null
    Write-Host "Connected to EXO: $($Cfg.TenantName)" -ForegroundColor Green
}

function Connect-Teams {
    param([Parameter(Mandatory)][hashtable]$Cfg)
    Ensure-Module -Name 'MicrosoftTeams' -Update | Out-Null
    Connect-MicrosoftTeams -CertificateThumbprint $Cfg.CertThumbprint `
                           -ApplicationId $Cfg.AppId `
                           -TenantId $Cfg.TenantId `
                           -ErrorAction Stop | Out-Null
    Write-Host "Connected to Teams: $($Cfg.TenantName)" -ForegroundColor Green
}

function Connect-SCC {
    param([Parameter(Mandatory)][hashtable]$Cfg)
    Ensure-Module -Name 'ExchangeOnlineManagement' -Update -AllowClobber | Out-Null
    Connect-IPPSSession -CertificateThumbprint $Cfg.CertThumbprint `
                        -AppId $Cfg.AppId `
                        -Organization $Cfg.OrgDomain `
                        -ErrorAction Stop | Out-Null
    Write-Host "Connected to SCC/Purview: $($Cfg.TenantName)" -ForegroundColor Green
}

function Connect-PnP {
    param([Parameter(Mandatory)][hashtable]$Cfg)
    Ensure-Module -Name 'PnP.PowerShell' -Update -AllowClobber | Out-Null
    Connect-PnPOnline -Url $Cfg.SPOAdminUrl `
                      -ClientId $Cfg.AppId `
                      -Thumbprint $Cfg.CertThumbprint `
                      -Tenant $Cfg.OrgDomain `
                      -ErrorAction Stop
    Write-Host "Connected to PnP: $($Cfg.TenantName)" -ForegroundColor Green
}
#endregion

#region === TENANT-SPECIFIC WRAPPERS ===
function Connect-AAD-Contoso   { Connect-Identity -Cfg $MCapsConfig }
function Connect-EXO-Contoso   { Connect-EXO      -Cfg $MCapsConfig }
function Connect-PnP-Contoso   { Connect-PnP      -Cfg $MCapsConfig }
function Connect-Teams-Contoso { Connect-Teams    -Cfg $MCapsConfig }
function Connect-SCC-Contoso   { Connect-SCC      -Cfg $MCapsConfig }

function Connect-AAD-Source    { Connect-Identity -Cfg $SourceConfig }
function Connect-EXO-Source    { Connect-EXO      -Cfg $SourceConfig }
function Connect-PnP-Source    { Connect-PnP      -Cfg $SourceConfig }
function Connect-Teams-Source  { Connect-Teams    -Cfg $SourceConfig }
function Connect-SCC-Source    { Connect-SCC      -Cfg $SourceConfig }

function Connect-AAD-Target    { Connect-Identity -Cfg $TargetConfig }
function Connect-EXO-Target    { Connect-EXO      -Cfg $TargetConfig }
function Connect-PnP-Target    { Connect-PnP      -Cfg $TargetConfig }
function Connect-Teams-Target  { Connect-Teams    -Cfg $TargetConfig }
function Connect-SCC-Target    { Connect-SCC      -Cfg $TargetConfig }

function Connect-All-Contoso {
    Write-Host "Connecting all services for CONTOSO ($($MCapsConfig.TenantName))..." -ForegroundColor Yellow
    Connect-AAD-Contoso
    Connect-EXO-Contoso
    Connect-SPO-Contoso
    Connect-Teams-Contoso
    Write-Host "All CONTOSO connections established." -ForegroundColor Green
}

function Connect-All-Source {
    Write-Host "Connecting all services for SOURCE ($($SourceConfig.TenantName))..." -ForegroundColor Yellow
    Connect-AAD-Source
    Connect-EXO-Source
    Connect-SPO-Source
    Connect-Teams-Source
    Write-Host "All SOURCE connections established." -ForegroundColor Green
}

function Connect-All-Target {
    Write-Host "Connecting all services for TARGET ($($TargetConfig.TenantName))..." -ForegroundColor Yellow
    Connect-AAD-Target
    Connect-EXO-Target
    Connect-SPO-Target
    Connect-Teams-Target
    Write-Host "All TARGET connections established." -ForegroundColor Green
}
#endregion

#region === QUICK REFERENCE ===
function Show-TenantInfo {

    Write-Host "`n=== $($MCapsConfig.TenantName.ToUpper()) ===" -ForegroundColor Magenta
    Write-Host "  Tenant : $($MCapsConfig.TenantId)"
    Write-Host "  AppId  : $($MCapsConfig.AppId)"
    Write-Host "  Cert TP: $($MCapsConfig.CertThumbprint)"
    Write-Host "  SPO URL: $($MCapsConfig.SPOAdminUrl)"
    Write-Host "  OrgDom : $($MCapsConfig.OrgDomain)"

    Write-Host "`n=== $($SourceConfig.TenantName.ToUpper()) ===" -ForegroundColor Cyan
    Write-Host "  Tenant : $($SourceConfig.TenantId)"
    Write-Host "  AppId  : $($SourceConfig.AppId)"
    Write-Host "  Cert TP: $($SourceConfig.CertThumbprint)"
    Write-Host "  SPO URL: $($SourceConfig.SPOAdminUrl)"
    Write-Host "  OrgDom : $($SourceConfig.OrgDomain)"

    Write-Host "`n=== $($TargetConfig.TenantName.ToUpper()) ===" -ForegroundColor Yellow
    Write-Host "  Tenant : $($TargetConfig.TenantId)"
    Write-Host "  AppId  : $($TargetConfig.AppId)"
    Write-Host "  Cert TP: $($TargetConfig.CertThumbprint)"
    Write-Host "  SPO URL: $($TargetConfig.SPOAdminUrl)"
    Write-Host "  OrgDom : $($TargetConfig.OrgDomain)"

    Write-Host ""
}
    
#endregion

#region === DEFAULT STARTING DIRECTORY (NO THROW) ===
function Set-DefaultWorkDir {
    $primary  = 'C:\Intune\Scripts'
    $fallback = Join-Path $HOME 'Intune\Scripts'

    try {
        if (-not (Test-Path $primary -PathType Container)) {
            New-Item -Path $primary -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Set-Location -Path $primary -ErrorAction Stop
        return
    } catch {
        try {
            if (-not (Test-Path $fallback -PathType Container)) {
                New-Item -Path $fallback -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            Set-Location -Path $fallback -ErrorAction Stop
            Write-Warning "Could not use '$primary' (likely permission). Using '$fallback' instead."
        } catch {
            Write-Warning "Could not set a default working directory. Error: $($_.Exception.Message)"
        }
    }
}
#endregion

Clear-Host
Show-TenantInfo
Set-DefaultWorkDir
'@

# ============================================================
# DEPLOYMENT LOGIC
# ============================================================
$profileTargets = @()
$profileTargets += $PROFILE
$profileTargets += $PROFILE.CurrentUserAllHosts

$pwshConfigRoot = Join-Path $HOME 'Documents\PowerShell'
$profileTargets += (Join-Path $pwshConfigRoot 'profile.ps1')
$profileTargets += (Join-Path $pwshConfigRoot 'Microsoft.PowerShell_profile.ps1')

$profileTargets = $profileTargets | Where-Object { $_ } | Select-Object -Unique

foreach ($targetProfile in $profileTargets) {
    $targetDir = Split-Path $targetProfile -Parent

    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Write-Host "[+] Created profile directory: $targetDir" -ForegroundColor Green
    }

    if ((Test-Path $targetProfile) -and -not $Force) {
        Write-Host "[!] Profile already exists at: $targetProfile" -ForegroundColor Yellow
        Write-Host "    Use -Force to overwrite. Skipping this one." -ForegroundColor Yellow
        continue
    }

    if ((Test-Path $targetProfile) -and $Force) {
        $backup = "$targetProfile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -Path $targetProfile -Destination $backup
        Write-Host "[~] Existing profile backed up to: $backup" -ForegroundColor Cyan
    }

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Set-Content -Path $targetProfile -Value $ProfileContent -Encoding utf8BOM
    } else {
        Set-Content -Path $targetProfile -Value $ProfileContent -Encoding UTF8
    }

    Write-Host "[+] LIUDAVID profile deployed to: $targetProfile" -ForegroundColor Green
}

Write-Host "[+] Reload current host profile with: . `$PROFILE" -ForegroundColor Green

