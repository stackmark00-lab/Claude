<#
    Remove-OneDrive.ps1
    Purpose : Force-remove Microsoft OneDrive (versions below 25) safely & idempotently
    Author  : SecOps
    Version : 1.3 (Fixed)
    Exit codes:
        0    = OneDrive not found / successfully removed (no reboot needed)
        3010 = Removed and reboot recommended
        1    = Error

    Requirements: Must run as Administrator
#>

#--- Settings ------------------------------------------------------------------------
$Global:RebootRecommended = $false
$LogRoot    = "C:\ProgramData\OneDriveRemoval"
$LogFile    = Join-Path $LogRoot ("OneDriveRemoval_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))
$KillMatch  = 'onedrive|filecoauth'
$SvcMatch   = 'onedrive'
$RegUninstallPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$Folders = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive",
    "$env:APPDATA\Microsoft\OneDrive",
    "$env:ProgramFiles\Microsoft OneDrive",
    "$env:ProgramFiles(x86)\Microsoft OneDrive",
    "$env:ProgramData\Microsoft OneDrive",
    "$env:USERPROFILE\OneDrive"
)
$RegKeys = @(
    'HKCU:\Software\Microsoft\OneDrive',
    'HKLM:\Software\Microsoft\OneDrive',
    'HKLM:\Software\WOW6432Node\Microsoft\OneDrive'
)

#--- Helpers -------------------------------------------------------------------------

# FIXED: Added administrator privilege check
function Test-AdminPrivileges {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Log {
    if (-not (Test-Path $LogRoot)) {
        New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    }
    try {
        Start-Transcript -Path $LogFile -Append -Force | Out-Null
    } catch {
        Write-Host "WARNING: Could not start transcript logging (may need Admin privileges): $_"
    }
}

function Stop-Log {
    try { Stop-Transcript | Out-Null } catch {}
}

function Test-OneDrivePresent {
    # Returns $true if any OneDrive traces still exist
    $apps = Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match '(?i)onedrive' }
    if ($apps) { return $true }

    foreach ($p in $Folders) {
        if (Test-Path $p) { return $true }
    }

    foreach ($k in $RegKeys) {
        if (Test-Path $k) { return $true }
    }

    # Running process is also a signal
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "(?i)$KillMatch" }
    if ($procs) { return $true }

    return $false
}

function Kill-OneDriveProcesses {
    Write-Host "Killing OneDrive processes..."
    $killed = 0
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -match "(?i)$KillMatch" } |
        ForEach-Object {
            try {
                Stop-Process -Id $_.Id -Force -ErrorAction Stop
                Write-Host "  Killed: $($_.ProcessName) (PID: $($_.Id))"
                $killed++
            } catch {
                Write-Host "  Could not kill: $($_.ProcessName) (PID: $($_.Id)) - $_"
            }
        }

    if ($killed -eq 0) {
        Write-Host "  No OneDrive processes found"
    }
}

function Stop-OneDriveServices {
    Write-Host "Stopping and disabling OneDrive services..."
    $stopped = 0
    Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "(?i)$SvcMatch" -or $_.Name -match "(?i)$SvcMatch" } |
        ForEach-Object {
            try {
                Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
            } catch {}
            try {
                Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
            } catch {}
            Write-Host "  Stopped/Disabled: $($_.DisplayName)"
            $stopped++
        }

    if ($stopped -eq 0) {
        Write-Host "  No OneDrive services found"
    }
}

function Uninstall-OneDriveProducts {
    Write-Host "Running registered uninstallers..."
    $targets = Get-ItemProperty $RegUninstallPaths -ErrorAction SilentlyContinue |
               Where-Object { $_.DisplayName -match '(?i)onedrive' }

    if (-not $targets) {
        Write-Host "  No OneDrive products found in registry"
        return
    }

    foreach ($app in $targets) {
        try {
            $args = @()

            # FIXED: Improved version parsing using [version] type
            $version = $app.DisplayVersion
            if ($version) {
                try {
                    # Try to parse as version object for robust comparison
                    $versionObj = [version]$version
                    if ($versionObj.Major -ge 25) {
                        Write-Host "  Skipping $($app.DisplayName) - version $version is 25 or above"
                        continue
                    }
                } catch {
                    # If version parsing fails, proceed with uninstall (conservative approach)
                    Write-Host "  Could not parse version for $($app.DisplayName), proceeding with uninstall"
                }
            }

            if ($app.PSChildName) {
                # MSI ProductCode path - typically GUID format
                $args = @('/x', $app.PSChildName, '/quiet', '/norestart')
                Write-Host "  Uninstalling via MSI: $($app.DisplayName) ($($app.PSChildName))"
            } elseif ($app.UninstallString) {
                # FIXED: Improved UninstallString parsing
                $uninst = $app.UninstallString.Trim('"')

                if ($uninst -match '(?i)msiexec') {
                    # Extract arguments and properly format
                    $parts = $uninst -split '\s+(?=(?:[^"]|"[^"]*")*$)'
                    $exePath = $parts[0]
                    $args = $parts[1..($parts.Count-1)] | Where-Object { $_ }

                    # Ensure quiet and norestart flags
                    if ($args -notcontains '/quiet')  { $args += '/quiet' }
                    if ($args -notcontains '/norestart') { $args += '/norestart' }

                    Write-Host "  Uninstalling via MSI: $($app.DisplayName)"
                } else {
                    # OneDrive typically uses: OneDriveSetup.exe /uninstall
                    if (Test-Path $uninst) {
                        Write-Host "  Executing uninstaller: $uninst"
                        Start-Process -FilePath $uninst -ArgumentList '/uninstall' -Wait -NoNewWindow -ErrorAction SilentlyContinue
                        continue
                    } else {
                        Write-Host "  Uninstall path not found: $uninst"
                        continue
                    }
                }
            }

            if ($args.Count -gt 0) {
                Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -NoNewWindow -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Host "  Uninstall error for $($app.DisplayName): $_"
        }
    }

    # Also try standard OneDrive uninstall paths
    $oneDriveSetupPaths = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
    )

    Write-Host "  Checking for OneDrive setup executables..."
    foreach ($setupPath in $oneDriveSetupPaths) {
        if (Test-Path $setupPath) {
            Write-Host "  Found OneDrive setup at: $setupPath"
            try {
                Start-Process -FilePath $setupPath -ArgumentList "/uninstall" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                Write-Host "  Executed uninstaller: $setupPath"
            } catch {
                Write-Host "  Could not execute: $setupPath - $_"
            }
        }
    }
}

function Remove-OneDriveFiles {
    Write-Host "Deleting OneDrive folders..."
    $deleted = 0

    foreach ($f in $Folders) {
        try {
            if (Test-Path $f) {
                # FIXED: Improved file deletion with better locking handling
                $retryCount = 0
                $maxRetries = 5
                $removed = $false

                while ($retryCount -lt $maxRetries -and -not $removed) {
                    try {
                        Remove-Item $f -Recurse -Force -ErrorAction Stop
                        $removed = $true
                        Write-Host "  Deleted: $f"
                        $deleted++
                    } catch {
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            Write-Host "  Retrying deletion of $f (attempt $retryCount/$maxRetries)..."
                            Start-Sleep -Seconds 2
                        } else {
                            Write-Host "  Could not delete after $maxRetries attempts (locked?): $f - $_"
                        }
                    }
                }
            }
        } catch {
            Write-Host "  Delete error: $f - $_"
        }
    }

    if ($deleted -eq 0) {
        Write-Host "  No OneDrive folders found to delete"
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
        } catch {
            Write-Host "  Registry delete error: $rk - $_"
        }
    }

    # Remove OneDrive from startup
    Write-Host "Removing OneDrive from startup..."
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    )

    foreach ($runKey in $runKeys) {
        try {
            Remove-ItemProperty -Path $runKey -Name "OneDrive" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $runKey -Name "OneDriveSetup" -ErrorAction SilentlyContinue
            Write-Host "  Removed startup entries from: $runKey"
        } catch {}
    }

    # FIXED: Improved File Explorer registry handling
    Write-Host "Removing OneDrive from File Explorer..."
    try {
        # Use HKCU registry instead of HKCR (more reliable)
        $explorerKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

        # Try to hide OneDrive folder from Quick Access
        if (Test-Path $explorerKey) {
            Set-ItemProperty -Path $explorerKey -Name "ShowSyncProviderNotifications" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Write-Host "  Disabled OneDrive sync notifications"
        }

        # Alternative: Try to remove from Classes registry if accessible
        $classesKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace"
        if (Test-Path $classesKey) {
            Remove-Item "$classesKey\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed OneDrive namespace from Explorer"
        }
    } catch {
        Write-Host "  Could not modify File Explorer settings: $_"
    }
}

#--- Main ----------------------------------------------------------------------------
try {
    # FIXED: Check for Administrator privileges first
    if (-not (Test-AdminPrivileges)) {
        Write-Host "ERROR: This script must run as Administrator"
        Write-Host "Please run PowerShell as Administrator and execute this script again"
        exit 1
    }

    Ensure-Log
    Write-Host "=== OneDrive Force Removal - Start === $(Get-Date)"
    Write-Host "Script Version: 1.3 (Fixed)"

    Kill-OneDriveProcesses
    Start-Sleep -Seconds 2

    Stop-OneDriveServices
    Start-Sleep -Seconds 2

    Uninstall-OneDriveProducts
    Start-Sleep -Seconds 3

    Kill-OneDriveProcesses        # second pass after uninstall
    Start-Sleep -Seconds 2

    Remove-OneDriveFiles
    Start-Sleep -Seconds 2

    Remove-OneDriveRegistry

    # If any traces remain, advise reboot and mark 3010
    Write-Host ""
    Write-Host "Checking for remaining OneDrive traces..."
    if (Test-OneDrivePresent) {
        Write-Host "WARNING: OneDrive traces still detected. A reboot is recommended to finish cleanup."
        $Global:RebootRecommended = $true
    } else {
        Write-Host "SUCCESS: OneDrive fully removed."
    }

    Write-Host "=== OneDrive Force Removal - End === $(Get-Date)"
    Stop-Log

    if ($Global:RebootRecommended) {
        Write-Host "Exiting with code 3010 (reboot recommended)"
        exit 3010
    } else {
        Write-Host "Exiting with code 0 (success)"
        exit 0
    }
}
catch {
    try { Stop-Log } catch {}
    Write-Host "FATAL ERROR: $($_.Exception.Message)"
    Write-Host "Stack Trace: $($_.Exception.StackTrace)"
    exit 1
}
