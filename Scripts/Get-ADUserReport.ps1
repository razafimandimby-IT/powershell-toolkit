<#
.SYNOPSIS
    Generate a comprehensive Active Directory user report in CSV format.

.DESCRIPTION
    This script queries Active Directory to retrieve all enabled and disabled user
    accounts, their last logon timestamps, account status (locked/disabled/expired),
    group memberships, and other relevant attributes. Results are exported to a CSV
    file for further analysis or archiving.

    Features:
    - Detects disabled, locked, and expired accounts
    - Reports last logon timestamp and password last set date
    - Lists direct group memberships for each user
    - Filters by Organizational Unit if desired
    - Flags accounts inactive for a specified number of days

.PARAMETER OutputPath
    Path where the CSV report will be saved.
    Example: "C:\Reports\AD_Users.csv"

.PARAMETER SearchBase
    Distinguished name of the OU to search in.
    Example: "OU=Paris,DC=contoso,DC=com"

.PARAMETER ShowDisabled
    Switch to include only disabled user accounts in the report.

.PARAMETER ShowEnabled
    Switch to include only enabled user accounts in the report.

.PARAMETER InactiveDays
    Number of days since last logon to consider an account as inactive.
    Only users with lastLogonTimestamp older than this value are included.

.PARAMETER InactiveOnly
    Switch to export only inactive accounts (requires -InactiveDays).

.EXAMPLE
    .\Get-ADUserReport.ps1 -OutputPath "C:\Reports\AllUsers.csv"

    Exports all AD users to a CSV file.

.EXAMPLE
    .\Get-ADUserReport.ps1 -SearchBase "OU=Paris,DC=contoso,DC=com" -ShowDisabled -OutputPath "C:\Reports\Disabled_Paris.csv"

    Exports only disabled users from the Paris OU.

.EXAMPLE
    .\Get-ADUserReport.ps1 -InactiveDays 90 -InactiveOnly -OutputPath "C:\Reports\InactiveUsers.csv"

    Exports users who haven't logged on in 90+ days.

.NOTES
    Author: Louis Denis RAZAFIMANDIMBY
    Requires: Active Directory module (RSAT), domain-joined machine
    Version: 1.2
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Full path to the output CSV file")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter(Mandatory = $false, HelpMessage = "Base OU distinguished name for search scope")]
    [string]$SearchBase,

    [Parameter(Mandatory = $false)]
    [switch]$ShowDisabled,

    [Parameter(Mandatory = $false)]
    [switch]$ShowEnabled,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 9999)]
    [int]$InactiveDays,

    [Parameter(Mandatory = $false)]
    [switch]$InactiveOnly
)

#region Functions

function Write-LogMessage {
    <#
    .SYNOPSIS
        Internal helper to write timestamped log messages to console and transcript.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'ERROR' { Write-Host $logEntry -ForegroundColor Red }
        'WARN'  { Write-Host $logEntry -ForegroundColor Yellow }
        'OK'    { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry -ForegroundColor Gray }
    }
}

#endregion

#region Main Execution

# Start transcript logging
$logDir = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "Logs"
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logFile = "Get-ADUserReport_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
$logPath = Join-Path -Path $logDir -ChildPath $logFile
Start-Transcript -Path $logPath -Force | Out-Null

Write-LogMessage -Level INFO -Message "Starting Active Directory User Report"

# Check if the Active Directory module is available
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-LogMessage -Level ERROR -Message "Active Directory module is not installed. Please install RSAT tools."
    Stop-Transcript
    exit 1
}

# Import the Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-LogMessage -Level OK -Message "Active Directory module loaded successfully"
}
catch {
    Write-LogMessage -Level ERROR -Message "Failed to load Active Directory module: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

# Build the AD filter based on parameters
$adProperties = @(
    'Name',
    'SamAccountName',
    'UserPrincipalName',
    'Enabled',
    'LastLogonDate',
    'PasswordLastSet',
    'PasswordExpired',
    'LockedOut',
    'AccountExpirationDate',
    'Title',
    'Department',
    'Manager',
    'Office',
    'telephoneNumber',
    'mail',
    'Created',
    'Modified',
    'DistinguishedName'
)

# Build the LDAP filter
if ($ShowDisabled -and -not $ShowEnabled) {
    $userFilter = { Enabled -eq $false }
    $filterLabel = "disabled"
}
elseif ($ShowEnabled -and -not $ShowDisabled) {
    $userFilter = { Enabled -eq $true }
    $filterLabel = "enabled"
}
else {
    $userFilter = "*"
    $filterLabel = "all"
}

Write-LogMessage -Level INFO -Message "Querying AD for $filterLabel users (SearchBase: '$($SearchBase -replace '^(.{50}).*$','$1...')')"

# Retrieve users from AD
try {
    $getADUserParams = @{
        Properties = $adProperties
        Filter     = $userFilter
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('SearchBase')) {
        $getADUserParams['SearchBase'] = $SearchBase
    }

    $users = Get-ADUser @getADUserParams
    Write-LogMessage -Level OK -Message "Retrieved $($users.Count) user account(s) from Active Directory"
}
catch {
    Write-LogMessage -Level ERROR -Message "Failed to query Active Directory: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

# Process users and build report objects
$report = [System.Collections.ArrayList]::new()
$disabledCount = 0
$lockedCount = 0
$expiredCount = 0
$inactiveCount = 0

$inactiveThreshold = if ($InactiveDays) { (Get-Date).AddDays(-$InactiveDays) } else { $null }

foreach ($user in $users) {
    # Determine account status
    $status = @()
    if (-not $user.Enabled) {
        $status += "Disabled"
        $disabledCount++
    }
    if ($user.LockedOut) {
        $status += "Locked"
        $lockedCount++
    }
    if ($user.AccountExpirationDate -and $user.AccountExpirationDate -lt (Get-Date)) {
        $status += "Expired"
        $expiredCount++
    }
    if ($user.PasswordExpired) {
        $status += "PasswordExpired"
    }

    $accountStatus = if ($status.Count -gt 0) { $status -join "; " } else { "Active" }

    # Check inactivity
    $isInactive = $false
    if ($InactiveDays -and $user.LastLogonDate) {
        if ($user.LastLogonDate -lt $inactiveThreshold) {
            $isInactive = $true
            $inactiveCount++
        }
    }
    elseif ($InactiveDays -and -not $user.LastLogonDate) {
        # No last logon date at all — consider inactive
        $isInactive = $true
        $inactiveCount++
    }

    # Get group memberships
    $groups = $null
    try {
        $groupMembership = Get-ADPrincipalGroupMembership -Identity $user.SamAccountName -ErrorAction SilentlyContinue
        if ($groupMembership) {
            $groups = ($groupMembership | Where-Object { $_.GroupCategory -eq 'Security' } | Select-Object -ExpandProperty Name) -join "; "
        }
    }
    catch {
        $groups = "Unable to retrieve"
    }

    # Resolve manager name
    $managerName = $null
    if ($user.Manager) {
        try {
            $managerObj = Get-ADUser -Identity $user.Manager -Properties DisplayName -ErrorAction SilentlyContinue
            $managerName = $managerObj.DisplayName
        }
        catch {
            $managerName = $user.Manager
        }
    }

    # Create the report object
    $reportObject = [PSCustomObject]@{
        Name                = $user.Name
        SamAccountName      = $user.SamAccountName
        UserPrincipalName   = $user.UserPrincipalName
        Email               = $user.mail
        Telephone           = $user.telephoneNumber
        Title               = $user.Title
        Department          = $user.Department
        Office              = $user.Office
        Manager             = $managerName
        AccountStatus       = $accountStatus
        Enabled             = $user.Enabled
        LockedOut           = $user.LockedOut
        PasswordExpired     = $user.PasswordExpired
        LastLogonDate       = if ($user.LastLogonDate) { $user.LastLogonDate.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
        PasswordLastSet     = if ($user.PasswordLastSet) { $user.PasswordLastSet.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A" }
        AccountExpiration   = if ($user.AccountExpirationDate) { $user.AccountExpirationDate.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
        Created             = $user.Created.ToString("yyyy-MM-dd HH:mm:ss")
        LastModified        = $user.Modified.ToString("yyyy-MM-dd HH:mm:ss")
        DaysSinceLastLogon  = if ($user.LastLogonDate) { [math]::Round(((Get-Date) - $user.LastLogonDate).TotalDays) } else { "N/A" }
        Groups              = $groups
        DistinguishedName   = $user.DistinguishedName
    }

    # Apply inactive filter if requested
    if ($InactiveOnly -and -not $isInactive) {
        continue
    }

    [void]$report.Add($reportObject)
}

Write-LogMessage -Level INFO -Message "Processing complete: $($report.Count) accounts in final report"

# Export to CSV
try {
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path -Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        Write-LogMessage -Level INFO -Message "Created output directory: $outputDir"
    }

    $report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    Write-LogMessage -Level OK -Message "Report exported successfully to: $OutputPath"
    Write-LogMessage -Level INFO -Message "File size: $([math]::Round((Get-Item $OutputPath).Length / 1KB, 2)) KB"
}
catch {
    Write-LogMessage -Level ERROR -Message "Failed to export CSV: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

# Print summary
Write-Host ""
Write-Host "========== REPORT SUMMARY ==========" -ForegroundColor Cyan
Write-Host "  Total users in report  : $($report.Count)" -ForegroundColor White
Write-Host "  Disabled accounts      : $disabledCount" -ForegroundColor $(if ($disabledCount -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  Locked accounts        : $lockedCount" -ForegroundColor $(if ($lockedCount -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  Expired accounts       : $expiredCount" -ForegroundColor $(if ($expiredCount -gt 0) { 'Yellow' } else { 'Green' })
if ($InactiveDays) {
    Write-Host "  Inactive (>=$InactiveDays days): $inactiveCount" -ForegroundColor $(if ($inactiveCount -gt 0) { 'Yellow' } else { 'Green' })
}
Write-Host "  Output file            : $OutputPath" -ForegroundColor White
Write-Host "  Log file               : $logPath" -ForegroundColor White
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Clean up
Stop-Transcript
Write-LogMessage -Level OK -Message "Script completed successfully"

#endregion
