#requires -RunAsAdministrator
<#
.SYNOPSIS
Diagnostic script to find all OneDrive traces on system
.NOTES
Run as Administrator to find where OneDrive is hiding
#>

Write-Host "=== OneDrive Diagnostic ===" -ForegroundColor Cyan
Write-Host ""

# Check processes
Write-Host "1. Processes:" -ForegroundColor Yellow
$procs = Get-Process -Name "*onedrive*", "*filecoauth*" -ErrorAction SilentlyContinue
if ($procs) {
    $procs | Select-Object Name, Id, Path
} else {
    Write-Host "  [✓] No OneDrive processes found"
}

# Check services
Write-Host "`n2. Services:" -ForegroundColor Yellow
$svcs = Get-Service -Name "*onedrive*" -ErrorAction SilentlyContinue
if ($svcs) {
    $svcs | Select-Object Name, DisplayName, Status
} else {
    Write-Host "  [✓] No OneDrive services found"
}

# Check AppX packages (MODERN WINDOWS)
Write-Host "`n3. AppX Packages:" -ForegroundColor Yellow
$appx = Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue
if ($appx) {
    Write-Host "  [!] FOUND AppX packages:"
    $appx | Select-Object Name, Version, InstallLocation
} else {
    Write-Host "  [✓] No AppX packages found"
}

# Check installed programs (Registry)
Write-Host "`n4. Installed Programs:" -ForegroundColor Yellow
$progs = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'OneDrive' }
if ($progs) {
    Write-Host "  [!] FOUND installed programs:"
    $progs | Select-Object DisplayName, DisplayVersion, InstallLocation
} else {
    Write-Host "  [✓] No OneDrive programs in registry"
}

# Check file paths
Write-Host "`n5. File Paths:" -ForegroundColor Yellow
@(
    "$env:LOCALAPPDATA\Microsoft\OneDrive",
    "$env:APPDATA\Microsoft\OneDrive",
    "$env:ProgramFiles\Microsoft OneDrive",
    "$env:ProgramFiles(x86)\Microsoft OneDrive",
    "$env:ProgramData\Microsoft OneDrive",
    "$env:USERPROFILE\OneDrive"
) | ForEach-Object {
    if (Test-Path $_) {
        Write-Host "  [!] FOUND: $_"
    }
}

# Check registry keys
Write-Host "`n6. Registry Keys:" -ForegroundColor Yellow
@(
    'HKCU:\Software\Microsoft\OneDrive',
    'HKLM:\Software\Microsoft\OneDrive',
    'HKLM:\Software\WOW6432Node\Microsoft\OneDrive'
) | ForEach-Object {
    if (Test-Path $_) {
        Write-Host "  [!] FOUND: $_"
    }
}

Write-Host "`n=== End Diagnostic ===" -ForegroundColor Cyan
