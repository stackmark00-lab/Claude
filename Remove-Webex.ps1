<#
    Remove-Webex.ps1
    Purpose : Force-remove Cisco Webex (all variants) safely & idempotently
    Author  : SecOps
    Version : 2.0 (Security patched)
    Exit codes:
      0     = Webex not found / successfully removed (no reboot needed)
      3010  = Removed and reboot recommended
      1     = Error
#>

#--- Settings ---------------------------------------------------------------
$Global:RebootRecommended = $false
$LogRoot   = "C:\ProgramData\WebexRemoval"
$LogFile   = Join-Path $LogRoot ("WebexRemoval_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
$KillMatch = 'webex|ciscocollabhost|ptone|ptoneclk|atmgr|ciscowebex|wxm|wbx'
$SvcMatch  = 'webex|cisco'
$RegUninstallPaths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$Folders = @(
  "$env:LOCALAPPDATA\Webex",
  "$env:APPDATA\Webex",
  "$env:ProgramFiles\Webex",
  "$env:ProgramFiles(x86)\Webex",
  "$env:ProgramFiles\Cisco Webex",
  "$env:ProgramFiles(x86)\Cisco Webex",
  "$env:USERPROFILE\AppData\Local\Temp\WebEx"
)
$RegKeys = @(
  'HKCU:\Software\Webex',
  'HKLM:\Software\Webex'
)

#--- Helpers ----------------------------------------------------------------
function Assert-Administrator {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host "ERROR: This script must run as Administrator" -ForegroundColor Red
    exit 1
  }
}

function Ensure-Log {
  # Attempt primary location, fallback to temp if it fails
  $logPaths = @(
    $LogRoot,
    (Join-Path $env:TEMP "WebexRemoval")
  )

  foreach ($path in $logPaths) {
    try {
      if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
      }
      # Test write access
      $testFile = Join-Path $path ".writetest"
      [System.IO.File]::WriteAllText($testFile, "test")
      Remove-Item $testFile -Force

      # Set global LogRoot and LogFile to this path
      $script:LogRoot = $path
      $script:LogFile = Join-Path $path ("WebexRemoval_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

      # Start transcript
      if ($PSVersionTable.PSVersion.Major -ge 5) {
        Start-Transcript -Path $script:LogFile -Append -Force -ErrorAction Stop | Out-Null
      }
      return
    } catch {
      Write-Host "  Could not use log path: $path ($_)"
    }
  }

  Write-Host "WARNING: Could not initialize logging" -ForegroundColor Yellow
}

function Stop-Log {
  try {
    if ($PSVersionTable.PSVersion.Major -ge 5) {
      Stop-Transcript -ErrorAction Stop | Out-Null
    }
  } catch {
    Write-Host "WARNING: Could not stop transcript: $_" -ForegroundColor Yellow
  }
}

function Test-WebexPresent {
  # Returns $true if any Webex traces still exist
  $apps = Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue |
          Where-Object { $_.DisplayName -match '(?i)webex' }
  if ($apps) { return $true }

  foreach ($p in $Folders) { if (Test-Path $p) { return $true } }
  foreach ($k in $RegKeys) { if (Test-Path $k) { return $true } }

  # Running process is also a signal
  $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "(?i)$KillMatch" }
  if ($procs) { return $true }

  return $false
}

function Kill-WebexProcesses {
  Write-Host "Killing Webex/Cisco processes..."
  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match "(?i)$KillMatch" } |
    ForEach-Object {
      try {
        Stop-Process -Id $_.Id -Force -ErrorAction Stop
        Write-Host "  Killed: $($_.ProcessName)"
      } catch {
        Write-Host "  Could not kill: $($_.ProcessName) ($($_.Id)) - $_"
      }
    }
}

function Stop-WebexServices {
  Write-Host "Stopping and disabling Webex/Cisco services..."
  Get-Service | Where-Object { $_.DisplayName -match "(?i)$SvcMatch" -or $_.Name -match "(?i)$SvcMatch" } |
    ForEach-Object {
      try { Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue } catch {}
      try { Set-Service  -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue } catch {}
      Write-Host "  Stopped/Disabled: $($_.DisplayName)"
    }
}

function Uninstall-WebexProducts {
  Write-Host "Running registered uninstallers..."
  $targets = Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -match '(?i)webex' }

  foreach ($app in $targets) {
    try {
      $args = @()
      $uninstallMethod = $null

      # Try MSI ProductCode first (more reliable)
      if ($app.PSChildName -and (Test-ValidMSIProductCode -ProductCode $app.PSChildName)) {
        Write-Host "  Uninstalling via MSI ProductCode: $($app.DisplayName)"
        $args = @('/x', $app.PSChildName, '/quiet', '/norestart')
        $uninstallMethod = 'msi'
      }
      # Fall back to UninstallString if it exists
      elseif ($app.UninstallString) {
        $uninstallMethod = Parse-UninstallString -UninstallString $app.UninstallString

        if ($uninstallMethod -eq 'msi') {
          Write-Host "  Uninstalling via MSI UninstallString: $($app.DisplayName)"
          # This was already parsed and args prepared, use them from Parse function
        } elseif ($uninstallMethod -eq 'exe') {
          Write-Host "  Uninstalling via EXE: $($app.DisplayName)"
          # Already executed in Parse function
          continue
        } else {
          Write-Host "  Skipping unrecognized uninstall method for: $($app.DisplayName)"
          continue
        }
      } else {
        Write-Host "  No valid uninstall method found for: $($app.DisplayName)"
        continue
      }

      if ($args.Count -gt 0 -and $uninstallMethod -eq 'msi') {
        Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
      }
    } catch {
      Write-Host "  Uninstall error for $($app.DisplayName): $_"
    }
  }
}

function Test-ValidMSIProductCode {
  [CmdletBinding()]
  param([string]$ProductCode)

  # MSI ProductCode is a GUID format: {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}
  return $ProductCode -match '^\{[0-9A-Fa-f\-]{36}\}$'
}

function Parse-UninstallString {
  [CmdletBinding()]
  param([string]$UninstallString)

  if (-not $UninstallString) { return 'unknown' }

  $uninst = $UninstallString.Trim('"')

  # Check if it's an MSI command
  if ($uninst -match '(?i)msiexec') {
    # Extract arguments from msiexec command, preserving quoted paths
    $msiArgs = @()

    # Remove msiexec.exe and /i or /x arguments
    $cleaned = $uninst -replace '(?i)msiexec\.exe\s+' -replace '^\s+/[ix]\s+' -replace '^\s+'

    # Try to extract ProductCode (first non-flag argument)
    if ($cleaned -match '(?i)(\{[0-9A-Fa-f\-]{36}\})') {
      $productCode = $matches[1]
      if (Test-ValidMSIProductCode -ProductCode $productCode) {
        # Don't actually execute here; let caller handle it
        return 'msi'
      }
    }

    Write-Host "    Could not parse valid MSI ProductCode from: $uninst"
    return 'unknown'
  }

  # Assume it's an executable path
  if (Test-Path $uninst -PathType Leaf) {
    try {
      Start-Process -FilePath $uninst -ArgumentList '/S', '/quiet', '/qn', '/norestart' -Wait -NoNewWindow -ErrorAction SilentlyContinue
      return 'exe'
    } catch {
      Write-Host "    Could not execute: $uninst - $_"
      return 'unknown'
    }
  }

  Write-Host "    Uninstall path not found: $uninst"
  return 'unknown'
}

function Remove-WebexFiles {
  Write-Host "Deleting Webex folders..."
  foreach ($f in $Folders) {
    try {
      if (Test-Path $f) {
        # Retry with exponential backoff for locked files (up to 10 retries)
        $maxRetries = 10
        $retryDelays = @(1, 2, 4, 4, 4, 4, 4, 4, 4, 4)  # seconds
        $deleted = $false

        for ($i = 0; $i -lt $maxRetries; $i++) {
          try {
            Remove-Item $f -Recurse -Force -ErrorAction Stop
            Write-Host "  Deleted: $f"
            $deleted = $true
            break
          } catch {
            if ($i -lt ($maxRetries - 1)) {
              Start-Sleep -Seconds $retryDelays[$i]
            }
          }
        }

        if (-not $deleted -and (Test-Path $f)) {
          Write-Host "  Still present (locked?): $f"
        }
      }
    } catch {
      Write-Host "  Delete error: $f - $_"
    }
  }
}

function Remove-WebexRegistry {
  Write-Host "Cleaning Webex registry keys..."
  foreach ($rk in $RegKeys) {
    try {
      if (Test-Path $rk) {
        Remove-Item $rk -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Cleaned: $rk"
      }
    } catch {
      Write-Host "  Registry delete error: $rk - $_"
    }
  }
}

#--- Main -------------------------------------------------------------------
try {
  # CRITICAL: Verify admin privileges first
  Assert-Administrator

  Ensure-Log
  Write-Host "=== Webex Force Removal - Start === $(Get-Date)"
  Write-Host "User: $($env:USERNAME) | Computer: $($env:COMPUTERNAME)" -ForegroundColor Cyan

  Kill-WebexProcesses
  Stop-WebexServices
  Uninstall-WebexProducts
  Kill-WebexProcesses             # second pass after uninstall
  Remove-WebexFiles
  Remove-WebexRegistry

  # If any traces remain, advise reboot and mark 3010
  if (Test-WebexPresent) {
    Write-Host "`nWebex traces still detected. A reboot is recommended to finish cleanup." -ForegroundColor Yellow
    $Global:RebootRecommended = $true
  } else {
    Write-Host "`nWebex fully removed." -ForegroundColor Green
  }

  Write-Host "=== Webex Force Removal - End === $(Get-Date)"
  Stop-Log

  if ($Global:RebootRecommended) { exit 3010 } else { exit 0 }
}
catch {
  try { Stop-Log } catch {}
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Stack: $($_.ScriptStackTrace)"
  exit 1
}
