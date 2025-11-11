#requires -RunAsAdministrator
<#
.SYNOPSIS
OneDrive Complete Removal - Check and Remove in one script
.NOTES
Exit codes: 0=removed, 3010=reboot needed, 1=error
#>

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
if (-not $isAdmin) { Write-Error "Must run as Administrator"; exit 1 }

Write-Host "=== OneDrive Complete Removal ===" -ForegroundColor Cyan

# ============== PHASE 1: CHECK WHAT EXISTS ==============
Write-Host "`n[PHASE 1] Checking for OneDrive traces..." -ForegroundColor Yellow

$foundItems = @()

# Check processes
$procs = Get-Process -Name "*onedrive*", "*filecoauth*" -ErrorAction SilentlyContinue
if ($procs) {
    Write-Host "  [!] Processes found: $($procs.Count)"
    $procs | ForEach-Object { Write-Host "      - $($_.Name) (PID: $($_.Id))"; $foundItems += $_ }
}

# Check services
$svcs = Get-Service -Name "*onedrive*" -ErrorAction SilentlyContinue
if ($svcs) {
    Write-Host "  [!] Services found: $($svcs.Count)"
    $svcs | ForEach-Object { Write-Host "      - $($_.DisplayName)"; $foundItems += $_ }
}

# Check AppX packages (CRITICAL)
$appx = Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue
if ($appx) {
    Write-Host "  [!] AppX packages found: $($appx.Count)"
    $appx | ForEach-Object { Write-Host "      - $($_.Name) (Version: $($_.Version))"; $foundItems += $_ }
}

# Check installed programs
$progs = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'OneDrive' }
if ($progs) {
    Write-Host "  [!] Installed programs found: $($progs.Count)"
    $progs | ForEach-Object { Write-Host "      - $($_.DisplayName) ($($_.DisplayVersion))"; $foundItems += $_ }
}

# Check file paths
$filePaths = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive",
    "$env:APPDATA\Microsoft\OneDrive",
    "$env:ProgramFiles\Microsoft OneDrive",
    "$env:ProgramFiles(x86)\Microsoft OneDrive",
    "$env:ProgramData\Microsoft OneDrive",
    "$env:USERPROFILE\OneDrive"
)
$existingPaths = @()
$filePaths | ForEach-Object {
    if (Test-Path $_) {
        Write-Host "  [!] File path found: $_"
        $existingPaths += $_
    }
}

# Check registry keys
$regKeys = @(
    'HKCU:\Software\Microsoft\OneDrive',
    'HKLM:\Software\Microsoft\OneDrive',
    'HKLM:\Software\WOW6432Node\Microsoft\OneDrive'
)
$existingKeys = @()
$regKeys | ForEach-Object {
    if (Test-Path $_) {
        Write-Host "  [!] Registry key found: $_"
        $existingKeys += $_
    }
}

if ($foundItems.Count -eq 0 -and $existingPaths.Count -eq 0 -and $existingKeys.Count -eq 0) {
    Write-Host "  [✓] No OneDrive traces found - System is clean" -ForegroundColor Green
    exit 0
}

# ============== PHASE 2: REMOVE EVERYTHING ==============
Write-Host "`n[PHASE 2] Removing OneDrive..." -ForegroundColor Yellow

# Kill processes
if ($procs) {
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "  [✓] Killed processes"
}

# Stop and disable services
if ($svcs) {
    $svcs | ForEach-Object {
        Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
    }
    Write-Host "  [✓] Stopped/disabled services"
}

# Remove AppX packages (CRITICAL)
if ($appx) {
    Write-Host "  [*] Removing AppX packages..."
    foreach ($package in $appx) {
        try {
            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction SilentlyContinue
            Write-Host "      [✓] Removed: $($package.Name)"
        } catch {
            Write-Host "      [!] Failed: $($package.Name)"
        }
    }
}

# Remove provisioned packages
Write-Host "  [*] Removing provisioned packages..."
$provisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'OneDrive' }
if ($provisionedPackages) {
    foreach ($package in $provisionedPackages) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction SilentlyContinue
            Write-Host "      [✓] Removed: $($package.DisplayName)"
        } catch {
            Write-Host "      [!] Failed: $($package.DisplayName)"
        }
    }
} else {
    Write-Host "      [✓] No provisioned packages found"
}

# Uninstall via registry
if ($progs) {
    Write-Host "  [*] Running MSI uninstallers..."
    foreach ($app in $progs) {
        if ($app.PSChildName) {
            msiexec.exe /x $app.PSChildName /quiet /norestart 2>$null
            Write-Host "      [✓] Uninstalled: $($app.DisplayName)"
        }
    }
}

# Delete file paths
if ($existingPaths.Count -gt 0) {
    Write-Host "  [*] Deleting file paths..."
    foreach ($path in $existingPaths) {
        try {
            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "      [✓] Deleted: $path"
        } catch {
            Write-Host "      [!] Failed to delete: $path"
        }
    }
}

# Clean registry
if ($existingKeys.Count -gt 0) {
    Write-Host "  [*] Cleaning registry..."
    foreach ($key in $existingKeys) {
        try {
            Remove-Item $key -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "      [✓] Removed: $key"
        } catch {
            Write-Host "      [!] Failed to remove: $key"
        }
    }
}

# Remove from startup
Write-Host "  [*] Removing from startup..."
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name "OneDrive" -ErrorAction SilentlyContinue
Remove-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name "OneDrive" -ErrorAction SilentlyContinue
Write-Host "      [✓] Removed startup entries"

# Disable via Group Policy
Write-Host "  [*] Disabling OneDrive policy..."
$regPath = "HKLM:\Software\Policies\Microsoft\Windows\OneDrive"
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
Set-ItemProperty -Path $regPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Write-Host "      [✓] Disabled via policy"

# ============== PHASE 3: FINAL VERIFICATION ==============
Write-Host "`n[PHASE 3] Final verification..." -ForegroundColor Yellow

$appxRemaining = Get-AppxPackage -Name "*OneDrive*" -ErrorAction SilentlyContinue
$procRemaining = Get-Process -Name "onedrive", "filecoauth" -ErrorAction SilentlyContinue
$svcRemaining = Get-Service -Name "*OneDrive*" -ErrorAction SilentlyContinue
$fileRemaining = $false
$regRemaining = $false

foreach ($path in $filePaths) {
    if (Test-Path $path) {
        $fileRemaining = $true
        Write-Host "  [!] File path still exists: $path"
    }
}

foreach ($key in $regKeys) {
    if (Test-Path $key) {
        $regRemaining = $true
        Write-Host "  [!] Registry key still exists: $key"
    }
}

if ($appxRemaining) {
    Write-Host "  [!] AppX packages still present:" -ForegroundColor Red
    $appxRemaining | ForEach-Object { Write-Host "      - $($_.Name)" }
}

if ($procRemaining) {
    Write-Host "  [!] Processes still running:" -ForegroundColor Red
    $procRemaining | ForEach-Object { Write-Host "      - $($_.Name)" }
}

if ($svcRemaining) {
    Write-Host "  [!] Services still present:" -ForegroundColor Red
    $svcRemaining | ForEach-Object { Write-Host "      - $($_.DisplayName)" }
}

# Final result
Write-Host ""
if ($appxRemaining -or $procRemaining -or $svcRemaining -or $fileRemaining -or $regRemaining) {
    Write-Host "[!] OneDrive still detected - REBOOT REQUIRED" -ForegroundColor Yellow
    Write-Host "    After reboot, run this script again or check with Qualys" -ForegroundColor Yellow
    exit 3010
} else {
    Write-Host "[✓] OneDrive completely removed successfully!" -ForegroundColor Green
    Write-Host "    System is ready for Qualys re-scan" -ForegroundColor Green
    exit 0
}
