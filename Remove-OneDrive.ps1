#requires -RunAsAdministrator
<#
.SYNOPSIS
Force-remove Microsoft OneDrive (v25 and below) safely
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

# Uninstall via registry
$uninstallers = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'OneDrive' }

foreach ($app in $uninstallers) {
    if ($app.PSChildName) {
        msiexec.exe /x $app.PSChildName /quiet /norestart
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

# Check if traces remain
$remains = (Get-Process -Name "onedrive" -ErrorAction SilentlyContinue) -or (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive") -or (Test-Path "$env:ProgramFiles\Microsoft OneDrive")

if ($remains) {
    Write-Host "[!] Reboot recommended" -ForegroundColor Yellow
    exit 3010
} else {
    Write-Host "[✓] OneDrive removed successfully" -ForegroundColor Green
    exit 0
}
