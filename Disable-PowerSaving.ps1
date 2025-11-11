<#
.SYNOPSIS
    Disables power saving options on Windows endpoints

.DESCRIPTION
    This script disables various power saving features on Windows computers including:
    - Sleep and hibernation
    - Display timeout
    - Hard disk timeout
    - USB selective suspend
    - Sets the system to High Performance power plan

.NOTES
    Author: IT Administration
    Requires: Administrator privileges
    Compatible: Windows 7/8/10/11, Windows Server 2012+

.EXAMPLE
    .\Disable-PowerSaving.ps1
    Runs the script to disable all power saving options
#>

# Requires -RunAsAdministrator

[CmdletBinding()]
param()

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Set-PowerPlan {
    <#
    .SYNOPSIS
        Sets the active power plan to High Performance
    #>
    try {
        Write-Log "Configuring High Performance power plan..."

        # Get the High Performance power plan GUID
        $highPerfPlan = powercfg /list | Select-String "High performance" | ForEach-Object {
            if ($_ -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
                $matches[1]
            }
        }

        if ($highPerfPlan) {
            powercfg /setactive $highPerfPlan
            Write-Log "High Performance power plan activated: $highPerfPlan" "SUCCESS"
        } else {
            Write-Log "High Performance plan not found. Creating custom plan..." "WARNING"
            # Create a custom high performance plan
            powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
        }
    } catch {
        Write-Log "Failed to set power plan: $_" "ERROR"
    }
}

function Disable-MonitorTimeout {
    <#
    .SYNOPSIS
        Disables monitor/display timeout for both AC and DC power
    #>
    try {
        Write-Log "Disabling monitor timeout..."

        # AC (plugged in) - Set monitor timeout to 0 (never)
        powercfg /change monitor-timeout-ac 0

        # DC (on battery) - Set monitor timeout to 0 (never)
        powercfg /change monitor-timeout-dc 0

        Write-Log "Monitor timeout disabled for AC and DC power" "SUCCESS"
    } catch {
        Write-Log "Failed to disable monitor timeout: $_" "ERROR"
    }
}

function Disable-DiskTimeout {
    <#
    .SYNOPSIS
        Disables hard disk timeout for both AC and DC power
    #>
    try {
        Write-Log "Disabling disk timeout..."

        # AC (plugged in) - Set disk timeout to 0 (never)
        powercfg /change disk-timeout-ac 0

        # DC (on battery) - Set disk timeout to 0 (never)
        powercfg /change disk-timeout-dc 0

        Write-Log "Disk timeout disabled for AC and DC power" "SUCCESS"
    } catch {
        Write-Log "Failed to disable disk timeout: $_" "ERROR"
    }
}

function Disable-SleepTimeout {
    <#
    .SYNOPSIS
        Disables sleep timeout for both AC and DC power
    #>
    try {
        Write-Log "Disabling sleep timeout..."

        # AC (plugged in) - Set standby timeout to 0 (never)
        powercfg /change standby-timeout-ac 0

        # DC (on battery) - Set standby timeout to 0 (never)
        powercfg /change standby-timeout-dc 0

        Write-Log "Sleep timeout disabled for AC and DC power" "SUCCESS"
    } catch {
        Write-Log "Failed to disable sleep timeout: $_" "ERROR"
    }
}

function Disable-HibernateTimeout {
    <#
    .SYNOPSIS
        Disables hibernate timeout for both AC and DC power
    #>
    try {
        Write-Log "Disabling hibernate timeout..."

        # AC (plugged in) - Set hibernate timeout to 0 (never)
        powercfg /change hibernate-timeout-ac 0

        # DC (on battery) - Set hibernate timeout to 0 (never)
        powercfg /change hibernate-timeout-dc 0

        Write-Log "Hibernate timeout disabled for AC and DC power" "SUCCESS"
    } catch {
        Write-Log "Failed to disable hibernate timeout: $_" "ERROR"
    }
}

function Disable-Hibernation {
    <#
    .SYNOPSIS
        Completely disables hibernation feature
    #>
    try {
        Write-Log "Disabling hibernation feature..."

        powercfg /hibernate off

        Write-Log "Hibernation feature disabled" "SUCCESS"
    } catch {
        Write-Log "Failed to disable hibernation: $_" "ERROR"
    }
}

function Disable-USBSelectiveSuspend {
    <#
    .SYNOPSIS
        Disables USB selective suspend for both AC and DC power
    #>
    try {
        Write-Log "Disabling USB selective suspend..."

        # Get the active power scheme GUID
        $activeScheme = (powercfg /getactivescheme).Split()[3]

        # USB settings sub-group GUID
        $usbSubGroup = "2a737441-1930-4402-8d77-b2bebba308a3"

        # USB selective suspend setting GUID
        $usbSetting = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"

        # Disable for AC power (0 = Disabled)
        powercfg /setacvalueindex $activeScheme $usbSubGroup $usbSetting 0

        # Disable for DC power (0 = Disabled)
        powercfg /setdcvalueindex $activeScheme $usbSubGroup $usbSetting 0

        # Apply the settings
        powercfg /setactive $activeScheme

        Write-Log "USB selective suspend disabled for AC and DC power" "SUCCESS"
    } catch {
        Write-Log "Failed to disable USB selective suspend: $_" "ERROR"
    }
}

function Disable-PCIePowerManagement {
    <#
    .SYNOPSIS
        Disables PCI Express link state power management
    #>
    try {
        Write-Log "Disabling PCI Express power management..."

        # Get the active power scheme GUID
        $activeScheme = (powercfg /getactivescheme).Split()[3]

        # PCI Express sub-group GUID
        $pcieSubGroup = "501a4d13-42af-4429-9fd1-a8218c268e20"

        # Link State Power Management GUID
        $pcieSetting = "ee12f906-d277-404b-b6da-e5fa1a576df5"

        # Disable for AC power (0 = Off)
        powercfg /setacvalueindex $activeScheme $pcieSubGroup $pcieSetting 0

        # Disable for DC power (0 = Off)
        powercfg /setdcvalueindex $activeScheme $pcieSubGroup $pcieSetting 0

        # Apply the settings
        powercfg /setactive $activeScheme

        Write-Log "PCI Express power management disabled for AC and DC power" "SUCCESS"
    } catch {
        Write-Log "Failed to disable PCI Express power management: $_" "ERROR"
    }
}

function Disable-ProcessorPowerManagement {
    <#
    .SYNOPSIS
        Sets processor power management to maximum performance
    #>
    try {
        Write-Log "Configuring processor power management..."

        # Get the active power scheme GUID
        $activeScheme = (powercfg /getactivescheme).Split()[3]

        # Processor power management sub-group GUID
        $processorSubGroup = "54533251-82be-4824-96c1-47b60b740d00"

        # Minimum processor state GUID (set to 100%)
        $minProcessorState = "893dee8e-2bef-41e0-89c6-b55d0929964c"

        # Maximum processor state GUID (set to 100%)
        $maxProcessorState = "bc5038f7-23e0-4960-96da-33abaf5935ec"

        # Set minimum processor state to 100% for AC
        powercfg /setacvalueindex $activeScheme $processorSubGroup $minProcessorState 100

        # Set minimum processor state to 100% for DC
        powercfg /setdcvalueindex $activeScheme $processorSubGroup $minProcessorState 100

        # Set maximum processor state to 100% for AC
        powercfg /setacvalueindex $activeScheme $processorSubGroup $maxProcessorState 100

        # Set maximum processor state to 100% for DC
        powercfg /setdcvalueindex $activeScheme $processorSubGroup $maxProcessorState 100

        # Apply the settings
        powercfg /setactive $activeScheme

        Write-Log "Processor power management configured for maximum performance" "SUCCESS"
    } catch {
        Write-Log "Failed to configure processor power management: $_" "ERROR"
    }
}

function Show-CurrentSettings {
    <#
    .SYNOPSIS
        Displays current power settings
    #>
    Write-Log "Current Power Settings:" "INFO"
    Write-Log "========================" "INFO"

    try {
        $activeScheme = powercfg /getactivescheme
        Write-Log "Active Power Scheme: $activeScheme" "INFO"

        Write-Log "`nDetailed Settings:" "INFO"
        powercfg /query | Out-String | Write-Host
    } catch {
        Write-Log "Failed to retrieve current settings: $_" "ERROR"
    }
}

# Main execution
function Main {
    Write-Log "========================================" "INFO"
    Write-Log "Starting Power Saving Disable Script" "INFO"
    Write-Log "========================================" "INFO"

    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Log "This script requires Administrator privileges. Please run as Administrator." "ERROR"
        exit 1
    }

    Write-Log "Administrator privileges confirmed" "SUCCESS"
    Write-Log ""

    # Execute all power saving disable functions
    Set-PowerPlan
    Write-Log ""

    Disable-MonitorTimeout
    Write-Log ""

    Disable-DiskTimeout
    Write-Log ""

    Disable-SleepTimeout
    Write-Log ""

    Disable-HibernateTimeout
    Write-Log ""

    Disable-Hibernation
    Write-Log ""

    Disable-USBSelectiveSuspend
    Write-Log ""

    Disable-PCIePowerManagement
    Write-Log ""

    Disable-ProcessorPowerManagement
    Write-Log ""

    Write-Log "========================================" "INFO"
    Write-Log "Power saving options have been disabled" "SUCCESS"
    Write-Log "========================================" "INFO"
    Write-Log ""

    # Show current settings
    $showSettings = Read-Host "Would you like to view current power settings? (Y/N)"
    if ($showSettings -eq 'Y' -or $showSettings -eq 'y') {
        Show-CurrentSettings
    }

    Write-Log "Script execution completed successfully!" "SUCCESS"
}

# Run the main function
Main
