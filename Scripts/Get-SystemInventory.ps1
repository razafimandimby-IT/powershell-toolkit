<#
.SYNOPSIS
    Inventory a Windows workstation or server — collect OS info, hardware specs,
    installed software, and disk usage.

.DESCRIPTION
    This script collects detailed system information from a local or remote Windows
    machine. It queries WMI/CIM and the registry to gather:
    - Operating system details (version, edition, install date, last boot)
    - Hardware specifications (CPU, RAM, manufacturer, model, serial number)
    - Logical disk inventory (drive letter, size, free space, percentage free)
    - Installed software list (name, publisher, version, install date)
    - Network configuration (IP, MAC, DNS servers, DHCP status)
    - Running services and their startup type

    Results are exported to a structured JSON file for easy ingestion into
    reporting dashboards or further analysis.

.PARAMETER ComputerName
    Name of the target computer. Defaults to the local machine.
    Example: "SRV-FILES-01" or "192.168.1.100"

.PARAMETER OutputPath
    Path where the inventory JSON file will be saved.
    Example: "C:\Reports\Inventory_SRV01.json"

.PARAMETER IncludeSoftware
    Switch to include the full list of installed software (can be slow on remote machines).

.PARAMETER IncludeServices
    Switch to include running service information.

.PARAMETER Credential
    PSCredential object for remote authentication.

.EXAMPLE
    .\Get-SystemInventory.ps1 -OutputPath "C:\Reports\LocalInventory.json"

    Inventories the local machine.

.EXAMPLE
    .\Get-SystemInventory.ps1 -ComputerName "SRV-APP-01" -IncludeSoftware -OutputPath "\\server\reports\SRV-APP-01.json"

    Inventories a remote server, including installed software.

.EXAMPLE
    .\Get-SystemInventory.ps1 -ComputerName "PC-WKS-045" -IncludeSoftware -IncludeServices -Credential (Get-Credential) -OutputPath "C:\Reports\PC-WKS-045.json"

    Inventories a remote workstation with credentials and full data.

.NOTES
    Author: Louis Denis RAZAFIMANDIMBY
    Requires: WMI/CIM access to target machine, admin rights on target
    Version: 1.1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [string]$ComputerName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $true, HelpMessage = "Full path to the output JSON file")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSoftware,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeServices,

    [Parameter(Mandatory = $false)]
    [PSCredential]$Credential
)

#region Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    switch ($Level) {
        'ERROR' { Write-Host $entry -ForegroundColor Red }
        'WARN'  { Write-Host $entry -ForegroundColor Yellow }
        'OK'    { Write-Host $entry -ForegroundColor Green }
        default { Write-Host $entry -ForegroundColor Gray }
    }
}

function Get-CimParam {
    <#
    .SYNOPSIS
        Build splatting parameters for Get-CimInstance based on computer/credential.
    #>
    $params = @{ ErrorAction = 'Stop' }
    if ($ComputerName -ne $env:COMPUTERNAME -and $ComputerName -ne "localhost") {
        $params['ComputerName'] = $ComputerName
        if ($Credential) {
            $params['Credential'] = $Credential
        }
    }
    return $params
}

function Get-InstalledSoftware {
    <#
    .SYNOPSIS
        Retrieve installed software from the registry (local or remote).
    #>
    param([hashtable]$ConnectionParams)

    $software = [System.Collections.ArrayList]::new()
    $registryPaths = @(
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    try {
        # Use registry provider via CIM for remote or local
        foreach ($regPath in $registryPaths) {
            $regParams = @{
                Namespace = 'root\default'
                ClassName = 'StdRegProv'
            }
            if ($ConnectionParams.ContainsKey('ComputerName')) {
                $regParams['ComputerName'] = $ConnectionParams['ComputerName']
            }
            if ($ConnectionParams.ContainsKey('Credential')) {
                $regParams['Credential'] = $ConnectionParams['Credential']
            }

            $reg = Get-CimInstance @regParams -ErrorAction SilentlyContinue

            # Enumerate subkeys (we query via Win32Reg_AddRemovePrograms alternative for efficiency)
        }

        # Fallback: use Win32Reg_AddRemovePrograms if available, else standard WMI
        $wmiParams = @{
            ClassName = 'Win32Reg_AddRemovePrograms'
            ErrorAction = 'SilentlyContinue'
        }
        if ($ConnectionParams.ContainsKey('ComputerName')) {
            $wmiParams['ComputerName'] = $ConnectionParams['ComputerName']
        }
        if ($ConnectionParams.ContainsKey('Credential')) {
            $wmiParams['Credential'] = $ConnectionParams['Credential']
        }

        $programs = Get-CimInstance @wmiParams -ErrorAction SilentlyContinue

        if (-not $programs) {
            # Alternative: query Win32_Product (slower but works everywhere)
            $productParams = @{
                ClassName = 'Win32_Product'
                ErrorAction = 'SilentlyContinue'
            }
            if ($ConnectionParams.ContainsKey('ComputerName')) {
                $productParams['ComputerName'] = $ConnectionParams['ComputerName']
            }
            if ($ConnectionParams.ContainsKey('Credential')) {
                $productParams['Credential'] = $ConnectionParams['Credential']
            }
            $programs = Get-CimInstance @productParams -ErrorAction SilentlyContinue
        }

        if ($programs) {
            foreach ($prog in $programs) {
                [void]$software.Add([PSCustomObject]@{
                    Name        = $prog.DisplayName -or $prog.Name
                    Publisher   = $prog.Publisher
                    Version     = $prog.Version -or $prog.Version_
                    InstallDate = $prog.InstallDate
                })
            }
        }
    }
    catch {
        Write-Log -Level WARN -Message "Could not query installed software: $($_.Exception.Message)"
    }

    return $software
}

#endregion

#region Main Execution

# Start transcript
$logDir = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "Logs"
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = "Get-SystemInventory_$ComputerName_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$logPath = Join-Path -Path $logDir -ChildPath $logFile
Start-Transcript -Path $logPath -Force | Out-Null

Write-Log -Level INFO -Message "Starting system inventory for: $ComputerName"

$cimParams = Get-CimParam

# 1. Operating System Information
Write-Log -Level INFO -Message "Gathering OS information..."
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem @cimParams
    $osInfo = [PSCustomObject]@{
        Caption          = $os.Caption
        Edition          = $os.Caption -replace '.*Windows (Server |)\d+ (.*)', '$2'
        Version          = $os.Version
        BuildNumber      = $os.BuildNumber
        Architecture     = $os.OSArchitecture
        InstallDate      = $os.InstallDate.ToString("yyyy-MM-dd HH:mm:ss")
        LastBootUpTime   = $os.LastBootUpTime.ToString("yyyy-MM-dd HH:mm:ss")
        UptimeDays       = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
        SystemDrive      = $os.SystemDrive
        WindowsDirectory = $os.WindowsDirectory
        RegisteredUser   = $os.RegisteredUser
        Organization     = $os.Organization
        TotalVisibleMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        FreePhysicalMemoryGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    }
    Write-Log -Level OK -Message "OS: $($os.Caption) (Build $($os.BuildNumber))"
}
catch {
    Write-Log -Level ERROR -Message "Failed to get OS information: $($_.Exception.Message)"
    $osInfo = $null
}

# 2. Computer System / Hardware
Write-Log -Level INFO -Message "Gathering hardware information..."
try {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem @cimParams
    $hardwareInfo = [PSCustomObject]@{
        Manufacturer  = $cs.Manufacturer
        Model         = $cs.Model
        SerialNumber  = (Get-CimInstance -ClassName Win32_BIOS @cimParams).SerialNumber
        TotalRAMGB    = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        LogicalCPUs   = $cs.NumberOfLogicalProcessors
        PhysicalCPUs  = $cs.NumberOfProcessors
        Domain        = $cs.Domain
        Workgroup     = if ($cs.PartOfDomain) { "Domain: $($cs.Domain)" } else { "Workgroup" }
        CurrentUser   = $cs.UserName
    }

    # Get CPU details
    $cpu = Get-CimInstance -ClassName Win32_Processor @cimParams | Select-Object -First 1
    $cpuInfo = "$($cpu.Name) @ $([math]::Round($cpu.MaxClockSpeed / 1000, 2)) GHz ($($cpu.NumberOfCores) cores, $($cpu.NumberOfLogicalProcessors) logical)"

    Write-Log -Level OK -Message "Hardware: $($cs.Manufacturer) $($cs.Model) | $cpuInfo"
}
catch {
    Write-Log -Level ERROR -Message "Failed to get hardware information: $($_.Exception.Message)"
    $hardwareInfo = $null
    $cpuInfo = $null
}

# 3. Logical Disk Information
Write-Log -Level INFO -Message "Gathering disk information..."
try {
    $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" @cimParams
    $diskReport = [System.Collections.ArrayList]::new()
    foreach ($disk in $disks) {
        $freePercent = if ($disk.Size -gt 0) { [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2) } else { 0 }
        [void]$diskReport.Add([PSCustomObject]@{
            Drive       = $disk.DeviceID
            SizeGB      = [math]::Round($disk.Size / 1GB, 2)
            FreeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            UsedSpaceGB = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
            FreePercent = $freePercent
            UsedPercent = [math]::Round(100 - $freePercent, 2)
            VolumeName  = $disk.VolumeName
            Alert       = if ($freePercent -lt 10) { "CRITICAL" } elseif ($freePercent -lt 20) { "WARNING" } else { "OK" }
        })

        $alertColor = if ($freePercent -lt 10) { 'Red' } elseif ($freePercent -lt 20) { 'Yellow' } else { 'Green' }
        Write-Host "    $($disk.DeviceID) : $([math]::Round($disk.FreeSpace / 1GB, 1)) GB free / $([math]::Round($disk.Size / 1GB, 1)) GB total ($freePercent%)" -ForegroundColor $alertColor
    }
    Write-Log -Level OK -Message "Found $($diskReport.Count) logical disk(s)"
}
catch {
    Write-Log -Level ERROR -Message "Failed to get disk information: $($_.Exception.Message)"
    $diskReport = $null
}

# 4. Installed Software (optional)
$softwareReport = $null
if ($IncludeSoftware) {
    Write-Log -Level INFO -Message "Gathering installed software (this may take a moment)..."
    try {
        $softwareReport = Get-InstalledSoftware -ConnectionParams $cimParams
        Write-Log -Level OK -Message "Found $($softwareReport.Count) installed software entries"
    }
    catch {
        Write-Log -Level WARN -Message "Software inventory incomplete: $($_.Exception.Message)"
        $softwareReport = [System.Collections.ArrayList]::new()
    }
}

# 5. Network Configuration
Write-Log -Level INFO -Message "Gathering network configuration..."
try {
    $nics = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" @cimParams
    $networkReport = [System.Collections.ArrayList]::new()
    foreach ($nic in $nics) {
        [void]$networkReport.Add([PSCustomObject]@{
            Description    = $nic.Description
            IPAddress      = $nic.IPAddress -join ", "
            SubnetMask     = $nic.IPSubnet -join ", "
            DefaultGateway = $nic.DefaultIPGateway -join ", "
            DNSServers     = $nic.DNSServerSearchOrder -join ", "
            DHCPEnabled    = $nic.DHCPEnabled
            MACAddress     = $nic.MACAddress
        })
    }
    Write-Log -Level OK -Message "Found $($networkReport.Count) active network adapter(s)"
}
catch {
    Write-Log -Level ERROR -Message "Failed to get network configuration: $($_.Exception.Message)"
    $networkReport = $null
}

# 6. Running Services (optional)
$serviceReport = $null
if ($IncludeServices) {
    Write-Log -Level INFO -Message "Gathering running services..."
    try {
        $services = Get-CimInstance -ClassName Win32_Service -Filter "State = 'Running'" @cimParams
        $serviceReport = $services | Select-Object Name, DisplayName, StartMode, StartName, ProcessId, PathName
        Write-Log -Level OK -Message "Found $($serviceReport.Count) running service(s)"
    }
    catch {
        Write-Log -Level WARN -Message "Could not retrieve services: $($_.Exception.Message)"
        $serviceReport = [System.Collections.ArrayList]::new()
    }
}

# Build the final inventory object
$inventory = [PSCustomObject]@{
    Timestamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName    = $ComputerName
    OperatingSystem = $osInfo
    Hardware        = $hardwareInfo
    CPU             = $cpuInfo
    LogicalDisks    = $diskReport
    NetworkAdapters = $networkReport
    InstalledSoftware = $softwareReport
    Services        = $serviceReport
}

# Export to JSON
try {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        Write-Log -Level INFO -Message "Created output directory: $outputDir"
    }

    $inventory | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding utf8
    Write-Log -Level OK -Message "Inventory exported to: $OutputPath"
    Write-Log -Level INFO -Message "File size: $([math]::Round((Get-Item $OutputPath).Length / 1KB, 2)) KB"
}
catch {
    Write-Log -Level ERROR -Message "Failed to export inventory: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

# Summary
Write-Host ""
Write-Host "========== INVENTORY SUMMARY ==========" -ForegroundColor Cyan
Write-Host "  Computer Name     : $ComputerName" -ForegroundColor White
if ($osInfo) { Write-Host "  OS                : $($osInfo.Caption)" -ForegroundColor White }
if ($hardwareInfo) { Write-Host "  Model             : $($hardwareInfo.Manufacturer) $($hardwareInfo.Model)" -ForegroundColor White }
if ($cpuInfo) { Write-Host "  Processor         : $cpuInfo" -ForegroundColor White }
if ($hardwareInfo) { Write-Host "  RAM               : $($hardwareInfo.TotalRAMGB) GB" -ForegroundColor White }
if ($diskReport) {
    $alertDisks = @($diskReport | Where-Object { $_.Alert -ne "OK" })
    if ($alertDisks.Count -gt 0) {
        Write-Host "  Disk Alert(s)     : $($alertDisks.Count) disk(s) below 20% free space" -ForegroundColor Yellow
    }
    else {
        Write-Host "  Disk Status       : All disks healthy" -ForegroundColor Green
    }
}
Write-Host "  Output file       : $OutputPath" -ForegroundColor White
Write-Host "  Log file          : $logPath" -ForegroundColor White
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

Stop-Transcript
Write-Log -Level OK -Message "Script completed successfully"

#endregion
