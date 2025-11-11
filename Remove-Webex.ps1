<#
    Remove-Webex.ps1
    Purpose: Remove Cisco Webex ONLY (safely, protects AnyConnect)
    Version: 2.3 Compact (Fixed)
    Exit codes: 0=success, 3010=reboot needed, 1=error
#>

param()

$Global:RebootRecommended = $false
$LogRoot = "C:\ProgramData\WebexRemoval"
$LogFile = Join-Path $LogRoot ("WebexRemoval_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

$KillMatch = 'webex|ciscocollabhost|ptone|ptoneclk|atmgr|ciscowebex|wxm|wbx|webexservice|webexmngr|webexupdater|intgservices|wbxservice'
$SvcMatch = 'webex|ciscocollabhost|webexservice|wbxservice'
$ExcludedServices = @('vpnagent','anyconnect','acvpnagent','ctrlpvtagent')

$RegUninstallPaths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$Folders = @(
  "$env:LOCALAPPDATA\Webex", "$env:APPDATA\Webex",
  "$env:ProgramFiles\Webex", "$env:ProgramFiles(x86)\Webex",
  "$env:ProgramFiles\Cisco Webex", "$env:ProgramFiles(x86)\Cisco Webex",
  "$env:ProgramFiles\Cisco\Webex", "$env:ProgramFiles(x86)\Cisco\Webex",
  "$env:ProgramFiles\WebEx", "$env:ProgramFiles(x86)\WebEx",
  "$env:LOCALAPPDATA\WebEx", "$env:APPDATA\WebEx",
  "$env:LOCALAPPDATA\Cisco", "$env:APPDATA\Cisco",
  "$env:ProgramFiles\Cisco\WebEx Bridges", "$env:ProgramFiles(x86)\Cisco\WebEx Bridges",
  "$env:USERPROFILE\AppData\Local\Temp\WebEx"
)

$RegKeys = @(
  'HKCU:\Software\Webex', 'HKLM:\Software\Webex',
  'HKCU:\Software\Cisco\Webex', 'HKLM:\Software\Cisco\Webex',
  'HKCU:\Software\WebEx', 'HKLM:\Software\WebEx',
  'HKCU:\Software\Cisco\WebEx Bridges', 'HKLM:\Software\Cisco\WebEx Bridges'
)

function Assert-Admin {
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrator')
  if (-not $admin) {
    Write-Host "ERROR: Run as Administrator" -ForegroundColor Red
    exit 1
  }
}

function Ensure-Log {
  $paths = @($LogRoot, (Join-Path $env:TEMP "WebexRemoval"))
  foreach ($path in $paths) {
    if ((New-Item -ItemType Directory -Path $path -Force -ErrorAction SilentlyContinue) -or (Test-Path $path)) {
      $script:LogFile = Join-Path $path ("WebexRemoval_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
      Start-Transcript -Path $script:LogFile -Force -ErrorAction SilentlyContinue | Out-Null
      return
    }
  }
}

function Stop-Log {
  Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}

function Test-WebexPresent {
  $apps = Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'webex' }
  if ($apps) { return $true }
  foreach ($p in $Folders) { if (Test-Path $p) { return $true } }
  foreach ($k in $RegKeys) { if (Test-Path $k) { return $true } }
  $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "(?i)$KillMatch" }
  if ($procs) { return $true }
  return $false
}

Assert-Admin
Ensure-Log
Write-Host "=== Webex Removal (v2.3) ===" -ForegroundColor Cyan
Write-Host "WARNING: Only Webex removed. AnyConnect/VPN protected." -ForegroundColor Yellow

Write-Host "1. Killing processes..."
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "(?i)$KillMatch" } | ForEach-Object {
  Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
  Write-Host "  Killed: $($_.ProcessName)"
}

Write-Host "2. Stopping services..."
Get-Service -ErrorAction SilentlyContinue | Where-Object {
  ($_.DisplayName -match '(?i)webex' -or $_.Name -match '(?i)webex') -and $_.Name -notin $ExcludedServices
} | ForEach-Object {
  Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
  Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
  Write-Host "  Stopped: $($_.DisplayName)"
}

Write-Host "3. Uninstalling MSI packages..."
Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'webex' } | ForEach-Object {
  if ($_.PSChildName -match '^\{[0-9A-Fa-f\-]{36}\}$') {
    Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $_.PSChildName, '/quiet', '/norestart') -Wait -NoNewWindow -ErrorAction SilentlyContinue
    Write-Host "  Uninstalled: $($_.DisplayName)"
  }
}

Write-Host "4. Killing processes (2nd pass)..."
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "(?i)$KillMatch" } | ForEach-Object {
  Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}

Write-Host "5. Deleting folders..."
foreach ($f in $Folders) {
  if (Test-Path $f) {
    Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Deleted: $f"
  }
}

Write-Host "6. Cleaning registry..."
foreach ($rk in $RegKeys) {
  if (Test-Path $rk) {
    Remove-Item $rk -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Cleaned: $rk"
  }
}

if (Test-WebexPresent) {
  Write-Host "Webex traces detected. REBOOT REQUIRED." -ForegroundColor Yellow
  $Global:RebootRecommended = $true
}
else {
  Write-Host "Webex fully removed." -ForegroundColor Green
}

Write-Host "=== Complete ===" -ForegroundColor Cyan
Stop-Log

if ($Global:RebootRecommended) {
  exit 3010
}
else {
  exit 0
}
