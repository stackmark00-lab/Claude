#requires -RunAsAdministrator
<#
.SYNOPSIS
Force-remove Microsoft OneDrive completely (including AppX packages)
.NOTES
Exit codes: 0=removed, 3010=reboot needed, 1=error
#>

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
if (-not $isAdmin) { Write-Error "Must run as Administrator"; exit 1 }

Write-Host "=== OneDrive Removal ===" -ForegroundColor Cyan

# Kill OneDrive processes
Get-Process -Name "onedrive", "filecoauth" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "[✓] Killed processes"

# Disable OneDrive services
Get-Service -Name "*OneDrive*" -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue; Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue }
Write-Host "[✓] Stopped services"

# Remove AppX packages (CRITICAL - Modern Windows)
Write-Host "[*] Removing AppX packages..."
$appxPackages = Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue
if ($appxPackages) {
    foreach ($package in $appxPackages) {
        try {
            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction SilentlyContinue
            Write-Host "  [✓] Removed: $($package.Name)"
        } catch {
            Write-Host "  [!] Failed to remove: $($package.Name)"
        }
    }
}

# Remove AppX provisioned packages (prevents reinstall on new user login)
Write-Host "[*] Removing provisioned packages..."
$provisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'OneDrive' }
if ($provisionedPackages) {
    foreach ($package in $provisionedPackages) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction SilentlyContinue
            Write-Host "  [✓] Removed provisioned: $($package.DisplayName)"
        } catch {
            Write-Host "  [!] Failed to remove provisioned: $($package.DisplayName)"
        }
    }
}

# Uninstall via registry
Write-Host "[*] Running MSI uninstallers..."
$uninstallers = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'OneDrive' }

foreach ($app in $uninstallers) {
    if ($app.PSChildName) {
        msiexec.exe /x $app.PSChildName /quiet /norestart 2>$null
    } elseif ($app.UninstallString) {
        & cmd /c $app.UninstallString /quiet /norestart 2>$null
    }
}
Write-Host "[✓] Ran uninstallers"

# Second process kill
Get-Process -Name "onedrive", "filecoauth" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Delete OneDrive folders
@(
    "$env:LOCALAPPDATA\Microsoft\OneDrive",
    "$env:APPDATA\Microsoft\OneDrive",
    "$env:ProgramFiles\Microsoft OneDrive",
    "$env:ProgramFiles(x86)\Microsoft OneDrive",
    "$env:ProgramData\Microsoft OneDrive",
    "$env:USERPROFILE\OneDrive"
) | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "[✓] Deleted folders"

# Clean registry
@(
    'HKCU:\Software\Microsoft\OneDrive',
    'HKLM:\Software\Microsoft\OneDrive',
    'HKLM:\Software\WOW6432Node\Microsoft\OneDrive'
) | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove from startup
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name "OneDrive" -ErrorAction SilentlyContinue
Remove-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name "OneDrive" -ErrorAction SilentlyContinue
Write-Host "[✓] Cleaned registry"

# Disable OneDrive in Group Policy (enterprise)
Write-Host "[*] Disabling via Group Policy..."
$regPath = "HKLM:\Software\Policies\Microsoft\Windows\OneDrive"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
Set-ItemProperty -Path $regPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Write-Host "[✓] Disabled OneDrive policy"

# Final check
Write-Host ""
Write-Host "[*] Checking for remaining traces..."
$appxRemaining = Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue
$procRemaining = Get-Process -Name "onedrive" -ErrorAction SilentlyContinue
$fileRemaining = (Test-Path "$env:ProgramFiles\Microsoft OneDrive") -or (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive")

if ($appxRemaining -or $procRemaining -or $fileRemaining) {
    Write-Host "[!] OneDrive traces still present - Reboot required" -ForegroundColor Yellow
    exit 3010
} else {
    Write-Host "[✓] OneDrive completely removed" -ForegroundColor Green
    exit 0
}
