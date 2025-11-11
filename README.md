# Disable Power Saving Script for Windows Endpoints

This PowerShell script disables various power saving features on Windows endpoints to ensure maximum performance and availability.

## Features

The script disables the following power saving options:

- **Sleep and Hibernation**: Prevents the system from entering sleep or hibernation mode
- **Monitor/Display Timeout**: Keeps the display always on
- **Hard Disk Timeout**: Prevents hard disks from spinning down
- **USB Selective Suspend**: Disables USB power management
- **PCI Express Power Management**: Disables PCI-E link state power management
- **Processor Power Management**: Sets CPU to run at maximum performance
- **High Performance Power Plan**: Activates the High Performance power scheme

All settings are applied for both **AC power (plugged in)** and **DC power (battery)**.

## Requirements

- Windows 7/8/10/11 or Windows Server 2012+
- Administrator privileges
- PowerShell 5.0 or higher

## Usage

### Method 1: Run Locally

1. Open PowerShell as Administrator
2. Navigate to the script directory
3. Run the script:

```powershell
.\Disable-PowerSaving.ps1
```

### Method 2: Run with Execution Policy Bypass

If you encounter execution policy restrictions:

```powershell
PowerShell.exe -ExecutionPolicy Bypass -File ".\Disable-PowerSaving.ps1"
```

### Method 3: Remote Deployment (Multiple Endpoints)

Deploy to multiple computers using PowerShell remoting:

```powershell
# Single computer
Invoke-Command -ComputerName "PC01" -FilePath ".\Disable-PowerSaving.ps1" -Credential (Get-Credential)

# Multiple computers
$computers = @("PC01", "PC02", "PC03")
Invoke-Command -ComputerName $computers -FilePath ".\Disable-PowerSaving.ps1" -Credential (Get-Credential)
```

### Method 4: Group Policy Deployment

1. Copy the script to a network share accessible by all endpoints
2. Create a new Group Policy Object (GPO)
3. Navigate to: `Computer Configuration > Policies > Windows Settings > Scripts > Startup`
4. Add the script as a startup script

### Method 5: SCCM/Intune Deployment

Deploy via System Center Configuration Manager or Microsoft Intune as a PowerShell script package.

## What the Script Does

1. **Checks Administrator Privileges**: Verifies the script is running with admin rights
2. **Sets High Performance Power Plan**: Activates or creates a high performance power scheme
3. **Disables Timeouts**: Sets all timeout values to 0 (never) for:
   - Monitor/Display
   - Hard Disk
   - Sleep
   - Hibernation
4. **Disables Power Management Features**:
   - USB selective suspend
   - PCI Express link state power management
   - Processor throttling (sets to 100% always)
5. **Logs All Actions**: Provides detailed logging of each operation
6. **Shows Current Settings**: Optionally displays the applied power configuration

## Output Example

```
[2025-11-11 10:30:15] [INFO] ========================================
[2025-11-11 10:30:15] [INFO] Starting Power Saving Disable Script
[2025-11-11 10:30:15] [INFO] ========================================
[2025-11-11 10:30:15] [SUCCESS] Administrator privileges confirmed

[2025-11-11 10:30:16] [INFO] Configuring High Performance power plan...
[2025-11-11 10:30:16] [SUCCESS] High Performance power plan activated

[2025-11-11 10:30:17] [INFO] Disabling monitor timeout...
[2025-11-11 10:30:17] [SUCCESS] Monitor timeout disabled for AC and DC power

...

[2025-11-11 10:30:25] [INFO] ========================================
[2025-11-11 10:30:25] [SUCCESS] Power saving options have been disabled
[2025-11-11 10:30:25] [INFO] ========================================
```

## Verifying the Configuration

After running the script, verify the settings:

```powershell
# View active power plan
powercfg /getactivescheme

# List all power plans
powercfg /list

# View detailed power settings
powercfg /query

# Check specific timeouts
powercfg /query | Select-String -Pattern "timeout"
```

## Reverting Changes

To re-enable power saving features:

```powershell
# Switch to Balanced power plan
powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e

# Re-enable hibernation
powercfg /hibernate on

# Set default timeouts (example for 15 minutes)
powercfg /change monitor-timeout-ac 15
powercfg /change monitor-timeout-dc 15
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 30
```

## Important Considerations

### Laptops and Battery Life
- Disabling power saving on laptops will significantly reduce battery life
- Consider creating separate policies for desktop vs. laptop endpoints
- For laptops, you may want to only disable AC power saving and keep DC settings

### Server Environments
- This configuration is ideal for servers where maximum performance and availability are required
- Ensure adequate cooling is available as components will run at full power continuously

### Energy Consumption
- Disabling power saving will increase electricity consumption
- Consider environmental and cost implications

## Troubleshooting

### Script Fails with "Access Denied"
- Ensure you're running PowerShell as Administrator
- Check that execution policy allows script execution

### High Performance Plan Not Found
- The script will automatically create a custom high performance plan
- Some Windows editions (Home) may have limited power plan options

### Settings Revert After Reboot
- Check Group Policy settings that might override local power configuration
- Verify the script is set to run at startup

### Remote Execution Fails
- Ensure PowerShell remoting is enabled: `Enable-PSRemoting -Force`
- Verify firewall rules allow WinRM traffic
- Check credentials have administrative rights on target machines

## Security Considerations

- This script requires administrative privileges
- Review the script contents before deployment
- Test in a controlled environment before production deployment
- Maintain audit logs of where and when the script was deployed

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Windows Event Viewer for power management events
3. Verify hardware compatibility with power management features

## License

This script is provided as-is for administrative purposes.

## Version History

- **v1.0** - Initial release with comprehensive power saving disable features
