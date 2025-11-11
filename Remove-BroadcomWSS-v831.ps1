<#
    Remove-BroadcomWSS-v831.ps1
    Purpose : Force-remove Broadcom WSS Agent (version 8.3.1) safely & idempotently
    Author  : SecOps
    Version : 1.0
    Exit codes:
      0     = Broadcom WSS Agent not found / successfully removed (no reboot needed)
      3010  = Removed and reboot recommended
      1     = Error
#>

#--- Settings ---------------------------------------------------------------
$Global:RebootRecommended = $false
$LogRoot   = "C:\ProgramData\BroadcomWSSRemoval"
$LogFile   = Join-Path $LogRoot ("BroadcomWSSRemoval_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
$KillMatch = 'wsagent|broadcomwss|bdagent|wssagent|bdreinforcer|bdserver'
$SvcMatch  = 'broadcomwss|wsagent|bdagent|bdreinforcer'
$RegUninstallPaths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$Folders = @(
  "$env:ProgramFiles\Broadcom\WSS Agent",
  "$env:ProgramFiles(x86)\Broadcom\WSS Agent",
  "$env:ProgramFiles\Broadcom\Web Security Agent",
  "$env:ProgramFiles(x86)\Broadcom\Web Security Agent",
  "$env:LOCALAPPDATA\Broadcom\WSS",
  "$env:APPDATA\Broadcom\WSS",
  "$env:ProgramData\Broadcom",
  "$env:USERPROFILE\AppData\Local\Temp\BroadcomWSS"
)
$RegKeys = @(
  'HKCU:\Software\Broadcom',
  'HKLM:\Software\Broadcom',
  'HKCU:\Software\Symantec',
  'HKLM:\Software\Symantec'
)

#--- Helpers ----------------------------------------------------------------
function Ensure-Log {
  if (-not (Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
  Start-Transcript -Path $LogFile -Append -Force | Out-Null
}
function Stop-Log   { try { Stop-Transcript | Out-Null } catch {} }

function Test-BroadcomWSSPresent {
  # Returns $true if any Broadcom WSS Agent traces still exist
  $apps = Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue |
          Where-Object { $_.DisplayName -match '(?i)(broadcom|wss|web security)' }
  if ($apps) { return $true }

  foreach ($p in $Folders) { if (Test-Path $p) { return $true } }
  foreach ($k in $RegKeys) { if (Test-Path $k) { return $true } }

  # Running process is also a signal
  $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "(?i)$KillMatch" }
  if ($procs) { return $true }

  return $false
}

function Kill-BroadcomWSSProcesses {
  Write-Host "Killing Broadcom WSS Agent processes..."
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

function Stop-BroadcomWSSServices {
  Write-Host "Stopping and disabling Broadcom WSS Agent services..."
  Get-Service | Where-Object { $_.DisplayName -match "(?i)$SvcMatch" -or $_.Name -match "(?i)$SvcMatch" } |
    ForEach-Object {
      try { Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue } catch {}
      try { Set-Service  -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
      Write-Host "  Stopped/Disabled: $($_.DisplayName)"
    }
}

function Uninstall-BroadcomWSSProducts {
  Write-Host "Running registered uninstallers..."
  $targets = Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -match '(?i)(broadcom.*wss|broadcom.*web security|wss agent)' }
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

function Remove-BroadcomWSSFiles {
  Write-Host "Deleting Broadcom WSS Agent folders..."
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

function Remove-BroadcomWSSRegistry {
  Write-Host "Cleaning Broadcom WSS Agent registry keys..."
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
  Write-Host "=== Broadcom WSS Agent Force Removal - Start === $(Get-Date)"

  Kill-BroadcomWSSProcesses
  Stop-BroadcomWSSServices
  Uninstall-BroadcomWSSProducts
  Kill-BroadcomWSSProcesses         # second pass after uninstall
  Remove-BroadcomWSSFiles
  Remove-BroadcomWSSRegistry

  # If any traces remain, advise reboot and mark 3010
  if (Test-BroadcomWSSPresent) {
    Write-Host "Broadcom WSS Agent traces still detected. A reboot is recommended to finish cleanup."
    $Global:RebootRecommended = $true
  } else {
    Write-Host "Broadcom WSS Agent fully removed."
  }

  Write-Host "=== Broadcom WSS Agent Force Removal - End === $(Get-Date)"
  Stop-Log

  if ($Global:RebootRecommended) { exit 3010 } else { exit 0 }
}
catch {
  try { Stop-Log } catch {}
  Write-Host "FATAL: $($_.Exception.Message)"
  exit 1
}
