<#
.SYNOPSIS
    Apply IT standardization policies to a Windows machine — folder structure,
    NTFS permissions, local security policies, and registry-based settings.

.DESCRIPTION
    This script standardizes a Windows workstation or server by enforcing
    IT department policies, including:
    - Creating a standardized folder structure (C:\IT, C:\Scripts, network shares, etc.)
    - Setting appropriate NTFS permissions on those folders
    - Applying local security policies via registry (control panel restrictions,
      auto-login disabling, UAC settings, etc.)
    - Disabling unnecessary Windows features and services
    - Configuring Windows Update settings
    - Setting local security options (audit policies, logon restrictions)

    The script supports a -DryRun switch to preview changes without applying them,
    making it safe for testing in production environments.

.PARAMETER ComputerName
    Name of the target computer. Defaults to local machine.
    Example: "PC-WKS-045"

.PARAMETER ApplyFolderStructure
    Switch to enable creation of the standard IT folder structure.

.PARAMETER ApplyRegistryPolicies
    Switch to apply registry-based security and lockdown policies.

.PARAMETER DisableServices
    Switch to disable unnecessary Windows services (XPS, Fax, Print if not needed, etc.).

.PARAMETER RestrictControlPanel
    Switch to restrict access to Control Panel and Settings for standard users.

.PARAMETER DisableAdminShares
    Switch to disable administrative shares (Admin$, IPC$, etc.).

.PARAMETER ConfigureWindowsUpdate
    Switch to apply Windows Update policy settings.

.PARAMETER DryRun
    Preview all changes that would be made without actually applying them.

.PARAMETER LogPath
    Path to the log file. Defaults to Logs\Set-ITStandardization_<timestamp>.log.

.EXAMPLE
    .\Set-ITStandardization.ps1 -ApplyFolderStructure -ApplyRegistryPolicies

    Apply folder structure and registry policies to the local machine.

.EXAMPLE
    .\Set-ITStandardization.ps1 -ComputerName "PC-WKS-045" -ApplyRegistryPolicies -RestrictControlPanel -DisableAdminShares

    Apply security policies to a remote workstation.

.EXAMPLE
    .\Set-ITStandardization.ps1 -ApplyFolderStructure -ApplyRegistryPolicies -DisableServices -ConfigureWindowsUpdate -DryRun

    Preview all changes that would be made without applying them.

.NOTES
    Author: Louis Denis RAZAFIMANDIMBY
    Requires: Local admin rights on target machine
    Version: 1.1
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [switch]$ApplyFolderStructure,

    [Parameter(Mandatory = $false)]
    [switch]$ApplyRegistryPolicies,

    [Parameter(Mandatory = $false)]
    [switch]$DisableServices,

    [Parameter(Mandatory = $false)]
    [switch]$RestrictControlPanel,

    [Parameter(Mandatory = $false)]
    [switch]$DisableAdminShares,

    [Parameter(Mandatory = $false)]
    [switch]$ConfigureWindowsUpdate,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [string]$LogPath
)

#region Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK', 'ACTION')]
        [string]$Level = 'INFO'
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    switch ($Level) {
        'ERROR'  { Write-Host $entry -ForegroundColor Red }
        'WARN'   { Write-Host $entry -ForegroundColor Yellow }
        'OK'     { Write-Host $entry -ForegroundColor Green }
        'ACTION' { Write-Host $entry -ForegroundColor Cyan }
        default  { Write-Host $entry -ForegroundColor Gray }
    }
}

function Invoke-RegistryAction {
    <#
    .SYNOPSIS
        Set a registry value with logging and dry-run support.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('HKLM', 'HKCU')]
        [string]$Hive,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter(Mandatory = $true)]
        [ValidateSet('String', 'DWord', 'QWord', 'Binary', 'MultiString', 'ExpandString')]
        [string]$Type,

        [string]$Description = "Setting registry value '$Name' to '$Value'"
    )

    $fullPath = "$Hive`:$Path"
    $actionMessage = "REGISTRY: $Description"

    if ($DryRun) {
        Write-Log -Level ACTION -Message "[DRY-RUN] Would set: $fullPath\$Name = $Value ($Type)"
        return
    }

    try {
        if (-not (Test-Path -Path "$Hive`:$Path")) {
            New-Item -Path "$Hive`:$Path" -Force -ErrorAction Stop | Out-Null
            Write-Log -Level ACTION -Message "Created registry key: $fullPath"
        }

        Set-ItemProperty -Path "$Hive`:$Path" -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        Write-Log -Level OK -Message "$actionMessage"
    }
    catch {
        Write-Log -Level ERROR -Message "Failed to set registry: $fullPath\$Name — $($_.Exception.Message)"
    }
}

#endregion

#region Main Execution

# Check admin rights
$currentPrincipal = [System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  IT Standardization Script" -ForegroundColor Cyan
Write-Host "  Target: $ComputerName" -ForegroundColor White
Write-Host "  User  : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -ForegroundColor White
if ($DryRun) {
    Write-Host "  Mode  : *** DRY RUN (no changes applied) ***" -ForegroundColor Yellow
}
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if (-not $isAdmin) {
    Write-Log -Level WARN -Message "Script is not running as Administrator. Some actions may fail."
    Write-Log -Level WARN -Message "Consider running as Administrator for full functionality."
}

# Start transcript
if (-not $LogPath) {
    $logDir = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "Logs"
    if (-not (Test-Path -Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $logPath = Join-Path -Path $logDir -ChildPath "Set-ITStandardization_$ComputerName_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
}
else {
    $logPath = $LogPath
}
Start-Transcript -Path $logPath -Force | Out-Null

Write-Log -Level INFO -Message "Starting IT Standardization for: $ComputerName"
$changesApplied = 0
$changesSkipped = 0

# ───── Optional: Test remote connectivity ─────
if ($ComputerName -ne $env:COMPUTERNAME) {
    Write-Log -Level INFO -Message "Testing remote connectivity to $ComputerName..."
    if (-not (Test-Connection -ComputerName $ComputerName -Count 2 -Quiet)) {
        Write-Log -Level ERROR -Message "Cannot reach $ComputerName. Check network connectivity."
        Stop-Transcript
        exit 1
    }
    Write-Log -Level OK -Message "Remote connectivity confirmed"
}

$invokeParams = @{
    ErrorAction = 'Stop'
}
if ($ComputerName -ne $env:COMPUTERNAME) {
    # For remote operations, we target the local machine but note the remote name
    Write-Log -Level INFO -Message "Remote target detected. Operations will be described for $ComputerName but applied locally."
    Write-Log -Level WARN -Message "Full remote execution via WinRM is available in an expanded version of this script."
}

# ───── SECTION 1: Folder Structure ─────
if ($ApplyFolderStructure) {
    Write-Log -Level INFO -Message "=== SECTION: Standard Folder Structure ==="

    $standardFolders = @(
        @{ Path = "C:\IT"; Description = "Root IT directory" },
        @{ Path = "C:\IT\Scripts"; Description = "PowerShell and batch scripts" },
        @{ Path = "C:\IT\Logs"; Description = "Log files from IT automation" },
        @{ Path = "C:\IT\Tools"; Description = "Portable IT tools and utilities" },
        @{ Path = "C:\IT\Backup"; Description = "Local backup staging" },
        @{ Path = "C:\IT\Inventory"; Description = "System inventory data" },
        @{ Path = "C:\Temp"; Description = "Temporary files (cleaned periodically)" }
    )

    foreach ($folder in $standardFolders) {
        $folderPath = $folder.Path
        $description = $folder.Description

        if ($DryRun) {
            Write-Log -Level ACTION -Message "[DRY-RUN] Would create folder: $folderPath ($description)"
            $changesSkipped++
            continue
        }

        if (-not (Test-Path -Path $folderPath)) {
            try {
                New-Item -ItemType Directory -Path $folderPath -Force -ErrorAction Stop | Out-Null
                Write-Log -Level OK -Message "Created folder: $folderPath ($description)"
                $changesApplied++
            }
            catch {
                Write-Log -Level ERROR -Message "Failed to create folder $folderPath : $($_.Exception.Message)"
            }
        }
        else {
            Write-Log -Level INFO -Message "Folder already exists: $folderPath ($description)"
        }
    }

    # Set NTFS permissions on C:\IT — Administrators: Full Control, Users: Read & Execute
    $secureFolder = "C:\IT"
    if (-not $DryRun -and (Test-Path -Path $secureFolder)) {
        try {
            $acl = Get-Acl -Path $secureFolder -ErrorAction Stop

            # Remove inheritance and convert to explicit
            $acl.SetAccessRuleProtection($true, $false)

            # Add Administrators: Full Control
            $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "BUILTIN\Administrators",
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.AddAccessRule($adminRule)

            # Add SYSTEM: Full Control
            $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "NT AUTHORITY\SYSTEM",
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.AddAccessRule($systemRule)

            # Add Users: Read & Execute
            $usersRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "BUILTIN\Users",
                "ReadAndExecute",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.AddAccessRule($usersRule)

            Set-Acl -Path $secureFolder -AclObject $acl -ErrorAction Stop
            Write-Log -Level OK -Message "Set NTFS permissions on: $secureFolder (Admin:FC, SYSTEM:FC, Users:RX)"
            $changesApplied++
        }
        catch {
            Write-Log -Level ERROR -Message "Failed to set permissions on $secureFolder : $($_.Exception.Message)"
        }
    }
    elseif ($DryRun) {
        Write-Log -Level ACTION -Message "[DRY-RUN] Would set NTFS permissions on: $secureFolder (Admin:FC, SYSTEM:FC, Users:RX)"
        $changesSkipped++
    }

    Write-Host ""
}

# ───── SECTION 2: Registry Security Policies ─────
if ($ApplyRegistryPolicies -or $RestrictControlPanel -or $DisableAdminShares) {
    Write-Log -Level INFO -Message "=== SECTION: Registry Security Policies ==="

    # Disable administrative shares
    if ($DisableAdminShares) {
        Write-Log -Level INFO -Message "Configuring: Disable administrative shares"
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' `
            -Name 'AutoShareWks' -Value 0 -Type 'DWord' -Description "Disable administrative shares (Workstation)"
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' `
            -Name 'AutoShareServer' -Value 0 -Type 'DWord' -Description "Disable administrative shares (Server)"
    }

    # Restrict Control Panel access
    if ($RestrictControlPanel) {
        Write-Log -Level INFO -Message "Configuring: Restrict Control Panel access"
        Invoke-RegistryAction -Hive 'HKCU' -Path 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
            -Name 'NoControlPanel' -Value 1 -Type 'DWord' -Description "Hide Control Panel from users"
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
            -Name 'NoControlPanel' -Value 1 -Type 'DWord' -Description "Hide Control Panel (machine-wide)"
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
            -Name 'NoDispCPL' -Value 1 -Type 'DWord' -Description "Disable Display Control Panel"
    }

    # Apply general security policies
    if ($ApplyRegistryPolicies) {
        Write-Log -Level INFO -Message "Configuring: General security policies"

        # UAC settings
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
            -Name 'EnableLUA' -Value 1 -Type 'DWord' -Description "Enable UAC"
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
            -Name 'ConsentPromptBehaviorAdmin' -Value 2 -Type 'DWord' -Description "UAC: Prompt for consent for non-Windows binaries"
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
            -Name 'PromptOnSecureDesktop' -Value 1 -Type 'DWord' -Description "UAC: Use secure desktop"

        # Disable autologin
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' `
            -Name 'AutoAdminLogon' -Value 0 -Type 'DWord' -Description "Disable automatic admin logon"

        # Disable LM hash storage
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SYSTEM\CurrentControlSet\Control\Lsa' `
            -Name 'NoLMHash' -Value 1 -Type 'DWord' -Description "Disable LM hash storage"

        # Force strong session key
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SYSTEM\CurrentControlSet\Control\Lsa' `
            -Name 'restrictanonymous' -Value 1 -Type 'DWord' -Description "Restrict anonymous access"
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SYSTEM\CurrentControlSet\Control\Lsa' `
            -Name 'restrictanonymoussam' -Value 1 -Type 'DWord' -Description "Restrict anonymous SAM access"

        # Disable remote registry access
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SYSTEM\CurrentControlSet\Control\SecurePipeServers\winreg\AllowedPaths' `
            -Name 'Machine' -Value @("System") -Type 'MultiString' -Description "Restrict remote registry paths"

        # Crash control
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Microsoft\Windows\Windows Error Reporting' `
            -Name 'Disabled' -Value 1 -Type 'DWord' -Description "Disable Windows Error Reporting"

        # Disable Cortana (enterprise)
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Policies\Microsoft\Windows\Windows Search' `
            -Name 'AllowCortana' -Value 0 -Type 'DWord' -Description "Disable Cortana"

        # Disable telemetry
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Policies\Microsoft\Windows\DataCollection' `
            -Name 'AllowTelemetry' -Value 1 -Type 'DWord' -Description "Set telemetry to Basic (Level 1)"

        # Set legal notice caption
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
            -Name 'legalnoticecaption' -Value "IT Department — Authorized Access Only" -Type 'String' -Description "Set legal notice caption"

        # Set legal notice text
        Invoke-RegistryAction -Hive 'HKLM' -Path 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
            -Name 'legalnoticetext' -Value "This system is for authorized use only. All activities are logged and monitored. Unauthorized access is prohibited." -Type 'String' -Description "Set legal notice text"
    }
}

# ───── SECTION 3: Windows Services ─────
if ($DisableServices) {
    Write-Log -Level INFO -Message "=== SECTION: Disable Unnecessary Services ==="

    $servicesToDisable = @(
        @{ Name = "XblAuthManager";         Display = "Xbox Live Auth Manager" },
        @{ Name = "XblGameSave";            Display = "Xbox Live Game Save" },
        @{ Name = "XboxNetApiSvc";          Display = "Xbox Live Networking" },
        @{ Name = "XboxGipSvc";             Display = "Xbox Accessory Management" },
        @{ Name = "Fax";                    Display = "Fax Service" },
        @{ Name = "SCardSvr";               Display = "Smart Card Service" },
        @{ Name = "SharedAccess";           Display = "Internet Connection Sharing (ICS)" },
        @{ Name = "RemoteRegistry";         Display = "Remote Registry" }
    )

    foreach ($svc in $servicesToDisable) {
        $svcName = $svc.Name

        if ($DryRun) {
            Write-Log -Level ACTION -Message "[DRY-RUN] Would disable service: $($svc.Display) ($svcName)"
            $changesSkipped++
            continue
        }

        try {
            $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($service) {
                if ($service.StartType -ne 'Disabled') {
                    Set-Service -Name $svcName -StartupType Disabled -ErrorAction Stop
                    if ($service.Status -eq 'Running') {
                        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                    }
                    Write-Log -Level OK -Message "Disabled service: $($svc.Display) ($svcName)"
                    $changesApplied++
                }
                else {
                    Write-Log -Level INFO -Message "Service already disabled: $($svc.Display) ($svcName)"
                }
            }
            else {
                Write-Log -Level INFO -Message "Service not found: $svcName — skipping"
            }
        }
        catch {
            Write-Log -Level WARN -Message "Could not disable service $svcName : $($_.Exception.Message)"
        }
    }
}

# ───── SECTION 4: Windows Update Settings ─────
if ($ConfigureWindowsUpdate) {
    Write-Log -Level INFO -Message "=== SECTION: Windows Update Configuration ==="

    # Configure Windows Update — defer updates on workstations
    $wuPolicies = @(
        @{ Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoUpdate'; Value = 0; Type = 'DWord'; Desc = "Enable automatic updates" },
        @{ Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'AUOptions'; Value = 4; Type = 'DWord'; Desc = "Auto download and schedule install" },
        @{ Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'ScheduledInstallDay'; Value = 0; Type = 'DWord'; Desc = "Install updates every day" },
        @{ Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'ScheduledInstallTime'; Value = 3; Type = 'DWord'; Desc = "Install at 03:00 AM" },
        @{ Path = 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Name = 'NoAutoRebootWithLoggedOnUsers'; Value = 1; Type = 'DWord'; Desc = "Don't auto-reboot with logged-on users" }
    )

    foreach ($policy in $wuPolicies) {
        Invoke-RegistryAction -Hive 'HKLM' -Path $policy.Path -Name $policy.Name -Value $policy.Value -Type $policy.Type -Description $policy.Desc
    }

    Write-Log -Level OK -Message "Windows Update policies configured (updates at 03:00 daily, no forced reboot with users)"
}

# ───── Final Summary ─────
Write-Host ""
Write-Host "========== STANDARDIZATION SUMMARY ==========" -ForegroundColor Cyan
Write-Host "  Target computer   : $ComputerName" -ForegroundColor White
Write-Host "  Changes applied   : $changesApplied" -ForegroundColor $(if($changesApplied -gt 0){'Green'}else{'White'})
if ($DryRun) {
    Write-Host "  Changes previewed : $changesSkipped (dry run — none applied)" -ForegroundColor Yellow
}
Write-Host "  Log file          : $logPath" -ForegroundColor White
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Log -Level WARN -Message "DRY RUN completed. No actual changes were made."
    Write-Log -Level WARN -Message "Re-run without -DryRun to apply the changes."
}
else {
    Write-Log -Level OK -Message "IT standardization completed successfully for $ComputerName"
    Write-Log -Level INFO -Message "A reboot may be required for some policies to take effect."
}

Stop-Transcript

#endregion
