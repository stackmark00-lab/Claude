#requires -RunAsAdministrator
Write-Host "=== OneDrive Removal ===" -ForegroundColor Cyan

# Check admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-Error "Must run as Administrator"; exit 1
}

# Phase 1: Check
Write-Host "`n[1/3] Checking..." -ForegroundColor Yellow
$procs = Get-Process -Name "*onedrive*", "*filecoauth*" -EA 0
$appx = Get-AppxPackage -Name "*OneDrive*" -EA 0
$svcs = Get-Service -Name "*onedrive*" -EA 0
$progs = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA 0 | Where-Object { $_.DisplayName -match 'OneDrive' }

if (-not ($procs -or $appx -or $svcs -or $progs)) {
    Write-Host "[✓] Clean - No OneDrive found" -ForegroundColor Green
    exit 0
}

# Phase 2: Remove
Write-Host "[2/3] Removing..." -ForegroundColor Yellow
$procs | Stop-Process -Force -EA 0
$svcs | ForEach-Object { Stop-Service -Name $_.Name -Force -EA 0; Set-Service -Name $_.Name -StartupType Disabled -EA 0 }
$appx | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -EA 0; Remove-AppxPackage -Package $_.PackageFullName -Force -EA 0 }
Get-AppxProvisionedPackage -Online -EA 0 | Where-Object { $_.DisplayName -match 'OneDrive' } | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -EA 0 }
$progs | ForEach-Object { if ($_.PSChildName) { msiexec.exe /x $_.PSChildName /quiet /norestart 2>$null } }

@("$env:LOCALAPPDATA\Microsoft\OneDrive", "$env:APPDATA\Microsoft\OneDrive", "$env:ProgramFiles\Microsoft OneDrive", "$env:ProgramFiles(x86)\Microsoft OneDrive", "$env:ProgramData\Microsoft OneDrive", "$env:USERPROFILE\OneDrive") |
    ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force -EA 0 } }

@('HKCU:\Software\Microsoft\OneDrive', 'HKLM:\Software\Microsoft\OneDrive', 'HKLM:\Software\WOW6432Node\Microsoft\OneDrive') |
    ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force -EA 0 } }

Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name "OneDrive" -EA 0
Remove-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -Name "OneDrive" -EA 0

$regPath = "HKLM:\Software\Policies\Microsoft\Windows\OneDrive"
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -EA 0

Write-Host "[✓] Removed" -ForegroundColor Green

# Phase 3: Verify
Write-Host "[3/3] Verifying..." -ForegroundColor Yellow
$remaining = (Get-AppxPackage -Name "*OneDrive*" -EA 0) -or (Get-Process -Name "onedrive", "filecoauth" -EA 0) -or (Get-Service -Name "*OneDrive*" -EA 0) -or (Test-Path "$env:ProgramFiles\Microsoft OneDrive")

if ($remaining) {
    Write-Host "[!] Reboot required - Exit 3010" -ForegroundColor Yellow
    exit 3010
} else {
    Write-Host "[✓] Success - Ready for Qualys re-scan" -ForegroundColor Green
    exit 0
}
