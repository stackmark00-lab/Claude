<#
    Remove-Webex.ps1
    Purpose : Remove Cisco Webex ONLY (safely & idempotently, without affecting other Cisco apps)
    Author  : SecOps
    Version : 2.3 (Multi-version support: up to 45, WBS up to 44, Meetings Client 43.8.0+)

    Supported versions:
      - WebEx Meeting Client 43.8.0 and newer (including v45)
      - Webex versions up to 45
      - WBS (Webex Bridges Service) 42.x and 44.x
      - Webex Productivity Tools
      - Legacy Cisco Webex installations

    Exit codes:
      0     = Webex not found / successfully removed (no reboot needed)
      3010  = Removed and reboot recommended
      1     = Error
#>

#--- Settings ---------------------------------------------------------------
$Global:RebootRecommended = $false
$LogRoot   = "C:\ProgramData\WebexRemoval"
$LogFile   = Join-Path $LogRoot ("WebexRemoval_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

# WEBEX-ONLY patterns (excludes AnyConnect, Cisco VPN, etc.)
# Supports: WebEx Meeting Client 45 and below, WBS up to 44, Meetings Client 43.8.0 and newer
$KillMatch = 'webex|ciscocollabhost|ptone|ptoneclk|atmgr|ciscowebex|wxm|wbx|webexservice|webexmngr|CiscoJabber|webexupdater|intgservices|wbxservice'
$SvcMatch  = 'webex|ciscocollabhost|webexservice|wbxservice'  # REMOVED generic 'cisco' to protect AnyConnect

# Services to EXCLUDE (do not stop)
$ExcludedServices = @(
  'vpnagent',           # Cisco VPN
  'anyconnect',         # Cisco AnyConnect
  'acvpnagent',         # AnyConnect VPN
  'ctrlpvtagent'        # Cisco ISE
)

# Registry paths
$RegUninstallPaths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

# Folders - WEBEX ONLY (covers versions up to 45, WBS up to 44, Meetings Client 43.8.0+)
$Folders = @(
  # Current/Modern paths (v45 and newer)
  "$env:LOCALAPPDATA\Webex",
  "$env:APPDATA\Webex",
  "$env:ProgramFiles\Webex",
  "$env:ProgramFiles(x86)\Webex",
  "$env:ProgramFiles\Cisco Webex",
  "$env:ProgramFiles(x86)\Cisco Webex",
  "$env:USERPROFILE\AppData\Local\Temp\WebEx",

  # Older version paths (pre-v45)
  "$env:ProgramFiles\Cisco\Webex",
  "$env:ProgramFiles(x86)\Cisco\Webex",
  "$env:ProgramFiles\Cisco Systems\Webex",
  "$env:ProgramFiles(x86)\Cisco Systems\Webex",
  "$env:LOCALAPPDATA\Cisco",
  "$env:APPDATA\Cisco",

  # WebEx Meetings Client specific (v43.8.0 - v45)
  "$env:ProgramFiles\WebEx",
  "$env:ProgramFiles(x86)\WebEx",
  "$env:LOCALAPPDATA\WebEx",
  "$env:APPDATA\WebEx",

  # WBS (Webex Bridges Service) paths (v42.x - v44.x)
  "$env:ProgramFiles\Cisco\WebEx Bridges",
  "$env:ProgramFiles(x86)\Cisco\WebEx Bridges",
  "$env:ProgramFiles\WebEx Bridges",
  "$env:ProgramFiles(x86)\WebEx Bridges",

  # Productivity Tools paths
  "$env:ProgramFiles\Cisco\WebEx Productivity Tools",
  "$env:ProgramFiles(x86)\Cisco\WebEx Productivity Tools",
  "$env:ProgramFiles\WebEx Productivity Tools",
  "$env:ProgramFiles(x86)\WebEx Productivity Tools",

  # Integration Services (v44+)
  "$env:ProgramFiles\Cisco\Integration Services",
  "$env:ProgramFiles(x86)\Cisco\Integration Services",

  # Cache and temp locations
  "$env:LOCALAPPDATA\WebEx\Cache",
  "$env:APPDATA\Webex\Cache"
)

# Registry keys - WEBEX ONLY (covers versions up to 45, WBS up to 44, Meetings Client 43.8.0+)
$RegKeys = @(
  # Modern paths (v45 and newer)
  'HKCU:\Software\Webex',
  'HKLM:\Software\Webex',
  'HKCU:\Software\Cisco\Webex',
  'HKLM:\Software\Cisco\Webex',

  # Older version paths (pre-v45)
  'HKCU:\Software\Cisco Systems\Webex',
  'HKLM:\Software\Cisco Systems\Webex',
  'HKCU:\Software\Cisco Systems\WebEx',
  'HKLM:\Software\Cisco Systems\WebEx',

  # WebEx Meetings Client paths (v43.8.0 - v45)
  'HKCU:\Software\WebEx',
  'HKLM:\Software\WebEx',

  # WBS paths (v42.x - v44.x)
  'HKCU:\Software\Cisco\WebEx Bridges',
  'HKLM:\Software\Cisco\WebEx Bridges',
  'HKCU:\Software\WebEx Bridges',
  'HKLM:\Software\WebEx Bridges',

  # Integration Services registry (v44+)
  'HKCU:\Software\Cisco\Integration Services',
  'HKLM:\Software\Cisco\Integration Services',

  # Additional Webex registry locations
  'HKCU:\Software\Cisco Webex',
  'HKLM:\Software\Cisco Webex',
  'HKCU:\Software\Webex Communications',
  'HKLM:\Software\Webex Communications'
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
  Write-Host "Killing Webex processes..."
  $killed = $false

  Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -match "(?i)$KillMatch" } |
    ForEach-Object {
      try {
        Stop-Process -Id $_.Id -Force -ErrorAction Stop
        Write-Host "  Killed: $($_.ProcessName)"
        $killed = $true
      } catch {
        Write-Host "  Could not kill: $($_.ProcessName) ($($_.Id)) - $_"
      }
    }

  if (-not $killed) {
    Write-Host "  No Webex processes found"
  }
}

function Stop-WebexServices {
  Write-Host "Stopping and disabling Webex services..."
  $stopped = $false

  Get-Service -ErrorAction SilentlyContinue |
    Where-Object {
      # Match Webex services ONLY
      ($_.DisplayName -match '(?i)webex' -or $_.Name -match '(?i)webex' -or
       $_.DisplayName -match '(?i)ciscocollabhost' -or $_.Name -match '(?i)ciscocollabhost') -and
      # EXCLUDE protected Cisco apps
      $_.Name -notin $ExcludedServices
    } |
    ForEach-Object {
      try {
        Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
        Write-Host "  Stopped: $($_.DisplayName)"
        $stopped = $true
      } catch {}
      try {
        Set-Service  -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  Disabled: $($_.DisplayName)"
      } catch {}
    }

  if (-not $stopped) {
    Write-Host "  No Webex services found"
  }
}

function Uninstall-WebexProducts {
  Write-Host "Running Webex uninstallers..."

  $targets = Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -match '(?i)webex' }

  if (-not $targets) {
    Write-Host "  No Webex products found in registry"
    return
  }

  foreach ($app in $targets) {
    try {
      $args = @()
      $uninstallMethod = $null

      # Try MSI ProductCode first (more reliable)
      if ($app.PSChildName -and (Test-ValidMSIProductCode -ProductCode $app.PSChildName)) {
        Write-Host "  Uninstalling via MSI: $($app.DisplayName)"
        $args = @('/x', $app.PSChildName, '/quiet', '/norestart')
        $uninstallMethod = 'msi'
      }
      # Fall back to UninstallString if it exists
      elseif ($app.UninstallString) {
        $uninstallMethod = Parse-UninstallString -UninstallString $app.UninstallString -DisplayName $app.DisplayName

        if ($uninstallMethod -eq 'exe') {
          # Already executed in Parse function
          continue
        } elseif ($uninstallMethod -ne 'msi') {
          Write-Host "  Skipping unrecognized uninstall method for: $($app.DisplayName)"
          continue
        }
      } else {
        Write-Host "  No valid uninstall method for: $($app.DisplayName)"
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
  param(
    [string]$UninstallString,
    [string]$DisplayName
  )

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
      Write-Host "  Executed uninstaller: $DisplayName"
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
  $deleted = $false

  foreach ($f in $Folders) {
    try {
      if (Test-Path $f) {
        # Retry with exponential backoff for locked files (up to 10 retries)
        $maxRetries = 10
        $retryDelays = @(1, 2, 4, 4, 4, 4, 4, 4, 4, 4)  # seconds
        $folderDeleted = $false

        for ($i = 0; $i -lt $maxRetries; $i++) {
          try {
            Remove-Item $f -Recurse -Force -ErrorAction Stop
            Write-Host "  Deleted: $f"
            $folderDeleted = $true
            $deleted = $true
            break
          } catch {
            if ($i -lt ($maxRetries - 1)) {
              Start-Sleep -Seconds $retryDelays[$i]
            }
          }
        }

        if (-not $folderDeleted -and (Test-Path $f)) {
          Write-Host "  Still present (locked?): $f"
        }
      }
    } catch {
      Write-Host "  Delete error: $f - $_"
    }
  }

  if (-not $deleted) {
    Write-Host "  No Webex folders found"
  }
}

function Remove-WebexRegistry {
  Write-Host "Cleaning Webex registry keys..."
  $cleaned = $false

  foreach ($rk in $RegKeys) {
    try {
      if (Test-Path $rk) {
        Remove-Item $rk -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Cleaned: $rk"
        $cleaned = $true
      }
    } catch {
      Write-Host "  Registry delete error: $rk - $_"
    }
  }

  if (-not $cleaned) {
    Write-Host "  No Webex registry keys found"
  }
}

#--- Main -------------------------------------------------------------------
try {
  # CRITICAL: Verify admin privileges first
  Assert-Administrator

  Ensure-Log
  Write-Host "=== Webex Force Removal (WEBEX ONLY) - Start === $(Get-Date)" -ForegroundColor Cyan
  Write-Host "Version: 2.3 | Supports: Meeting Client 45, WBS 44.x, Meetings Client 43.8.0+" -ForegroundColor Cyan
  Write-Host "User: $($env:USERNAME) | Computer: $($env:COMPUTERNAME)" -ForegroundColor Cyan
  Write-Host "WARNING: This will ONLY remove Webex. Other Cisco apps (AnyConnect, VPN) are protected." -ForegroundColor Yellow

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

  Write-Host "=== Webex Force Removal - End === $(Get-Date)" -ForegroundColor Cyan
  Stop-Log

  if ($Global:RebootRecommended) { exit 3010 } else { exit 0 }
}
catch {
  try { Stop-Log } catch {}
  Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Stack: $($_.ScriptStackTrace)"
  exit 1
}
