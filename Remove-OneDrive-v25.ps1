<#
    Remove-OneDrive-v25.ps1
    Purpose : Force-remove OneDrive (versions below 25) safely & idempotently
    Author  : SecOps
    Version : 1.0
    Exit codes:
      0     = OneDrive not found / successfully removed (no reboot needed)
      3010  = Removed and reboot recommended
      1     = Error
#>

#--- Settings ---------------------------------------------------------------
$Global:RebootRecommended = $false
$LogRoot   = "C:\ProgramData\OneDriveRemoval"
$LogFile   = Join-Path $LogRoot ("OneDriveRemoval_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
$KillMatch = 'onedrive|skypehost|groove|onenote'
$SvcMatch  = 'onedrive|groove|skype|microsoft.*online'
$RegUninstallPaths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$Folders = @(
  "$env:USERPROFILE\OneDrive",
  "$env:LOCALAPPDATA\Microsoft\OneDrive",
  "$env:ProgramFiles\Microsoft OneDrive",
  "$env:ProgramFiles(x86)\Microsoft OneDrive",
  "$env:APPDATA\Microsoft\OneDrive",
  "$env:LOCALAPPDATA\OneDrive",
  "$env:USERPROFILE\AppData\Local\Temp\OneDrive"
)
$RegKeys = @(
  'HKCU:\Software\Microsoft\OneDrive',
  'HKLM:\Software\Microsoft\OneDrive',
  'HKCU:\Software\Microsoft\SkyDrive'
)

#--- Helpers ----------------------------------------------------------------
function Ensure-Log {
  if (-not (Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
  Start-Transcript -Path $LogFile -Append -Force | Out-Null
}
function Stop-Log   { try { Stop-Transcript | Out-Null } catch {} }

function Test-OneDrivePresent {
  # Returns $true if any OneDrive traces still exist
  $apps = Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue |
          Where-Object { $_.DisplayName -match '(?i)onedrive' }
  if ($apps) { return $true }

  foreach ($p in $Folders) { if (Test-Path $p) { return $true } }
  foreach ($k in $RegKeys) { if (Test-Path $k) { return $true } }

  # Running process is also a signal
  $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "(?i)$KillMatch" }
  if ($procs) { return $true }

  return $false
}

function Kill-OneDriveProcesses {
  Write-Host "Killing OneDrive/Microsoft processes..."
  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match "(?i)$KillMatch" } |
    ForEach-Object {
      try {
        Stop-Process -Id $_.Id -Force -ErrorAction Stop
        Write-Host "  Killed: $($_.ProcessName)"
      } catch {
        Write-Host "  Could not kill: $($_.ProcessName) ($($_.Id)) $_"
      }
    }
}

function Stop-OneDriveServices {
  Write-Host "Stopping and disabling OneDrive/Microsoft services..."
  Get-Service | Where-Object { $_.DisplayName -match "(?i)$SvcMatch" -or $_.Name -match "(?i)$SvcMatch" } |
    ForEach-Object {
      try { Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue } catch {}
      try { Set-Service  -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
      Write-Host "  Stopped/Disabled: $($_.DisplayName)"
    }
}

function Uninstall-OneDriveProducts {
  Write-Host "Running registered uninstallers..."
  $targets = Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -match '(?i)onedrive' }
  foreach ($app in $targets) {
    try {
      $args = @()
      if ($app.PSChildName) {
        # MSI ProductCode path
        $args = @('/x', $app.PSChildName, '/quiet', '/norestart')
      } elseif ($app.UninstallString) {
        # EXE/MSI string path
        $uninst = $app.UninstallString.Trim('"')
        if ($uninst -match '(?i)msiexec') {
          $args = ($uninst -replace '(?i)msiexec\.exe','').Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries)
          if ($args -notcontains '/quiet')   { $args += '/quiet' }
          if ($args -notcontains '/norestart'){ $args += '/norestart' }
        } else {
          Start-Process -FilePath $uninst -ArgumentList '/S','/quiet','/qn','/norestart' -Wait -NoNewWindow -ErrorAction SilentlyContinue
          continue
        }
      }
      if ($args.Count -gt 0) {
        Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Write-Host "  Uninstalled: $($app.DisplayName)"
      }
    } catch {
      Write-Host "  Uninstall error for $($app.DisplayName): $_"
    }
  }
}

function Remove-OneDriveFiles {
  Write-Host "Deleting OneDrive folders..."
  foreach ($f in $Folders) {
    try {
      if (Test-Path $f) {
        # Unlock left-over file locks by retrying
        for ($i=0; $i -lt 3; $i++) {
          try { Remove-Item $f -Recurse -Force -ErrorAction Stop; break } catch { Start-Sleep -Seconds 2 }
        }
        if (Test-Path $f) { Write-Host "  Still present (locked?): $f" } else { Write-Host "  Deleted: $f" }
      }
    } catch { Write-Host "  Delete error: $f $_" }
  }
}

function Remove-OneDriveRegistry {
  Write-Host "Cleaning OneDrive registry keys..."
  foreach ($rk in $RegKeys) {
    try {
      if (Test-Path $rk) {
        Remove-Item $rk -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Cleaned: $rk"
      }
    } catch { Write-Host "  Registry delete error: $rk $_" }
  }
}

#--- Main -------------------------------------------------------------------
try {
  Ensure-Log
  Write-Host "=== OneDrive Force Removal - Start === $(Get-Date)"

  Kill-OneDriveProcesses
  Stop-OneDriveServices
  Uninstall-OneDriveProducts
  Kill-OneDriveProcesses             # second pass after uninstall
  Remove-OneDriveFiles
  Remove-OneDriveRegistry

  # If any traces remain, advise reboot and mark 3010
  if (Test-OneDrivePresent) {
    Write-Host "OneDrive traces still detected. A reboot is recommended to finish cleanup."
    $Global:RebootRecommended = $true
  } else {
    Write-Host "OneDrive fully removed."
  }

  Write-Host "=== OneDrive Force Removal - End === $(Get-Date)"
  Stop-Log

  if ($Global:RebootRecommended) { exit 3010 } else { exit 0 }
}
catch {
  try { Stop-Log } catch {}
  Write-Host "FATAL: $($_.Exception.Message)"
  exit 1
}
