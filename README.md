# PowerShell Toolkit for IT Administration

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)
![Platform](https://img.shields.io/badge/Platform-Windows-lightblue)
![RSAT](https://img.shields.io/badge/Requires-RSAT-orange)
![Maintained](https://img.shields.io/badge/Maintained-Yes-brightgreen)

> A collection of PowerShell automation scripts designed to simplify and standardize IT administration tasks in Windows environments. From Active Directory user reporting to system inventory, this toolkit helps IT teams save time and reduce manual effort.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Scripts Overview](#scripts-overview)
- [Usage Examples](#usage-examples)
  - [Get-ADUserReport.ps1](#get-aduserreportps1)
  - [Get-SystemInventory.ps1](#get-systeminventoryps1)
  - [Invoke-ITReport.ps1](#invoke-itreportps1)
  - [Set-ITStandardization.ps1](#set-itstandardizationps1)
- [Directory Structure](#directory-structure)
- [Logging](#logging)
- [Contributing](#contributing)
- [License](#license)
- [Author](#author)

---

## Overview

The **PowerShell Toolkit for IT Administration** provides a modular set of scripts that automate common IT administration workflows. Whether you need to audit Active Directory users, inventory workstations, generate executive reports, or enforce IT standards across machines, this toolkit has you covered.

Each script is designed with:

- **Comment-based help** — accessible via `Get-Help` directly in PowerShell.
- **Parameter validation** — safe defaults with error checking.
- **Structured logging** — every action is timestamped and recorded.
- **Modular design** — scripts can run standalone or be orchestrated together.

---

## Features

- Active Directory user reporting with CSV export
- Detection of disabled, inactive, and locked user accounts
- Workstation and server hardware/software inventory
- Installed software audit with publisher and version details
- Disk usage analysis with free-space alerts
- Centralized HTML report generation for management
- Local security policy enforcement and folder standardization
- Structured transcript-based logging for every run

---

## Prerequisites

| Requirement | Details |
|---|---|
| **PowerShell** | Version 5.1 or higher (Windows PowerShell or PowerShell 7) |
| **Operating System** | Windows Server 2016+ or Windows 10/11 |
| **RSAT Tools** | Active Directory module for `Get-ADUser` (not required for inventory scripts) |
| **Execution Policy** | Bypass or RemoteSigned (`Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`) |
| **Permissions** | Domain user rights for AD queries; local admin for system inventory |

> **Note:** The Active Directory module is part of RSAT (Remote Server Administration Tools). On Windows 10/11 Pro or Enterprise, enable it via:
> ```powershell
> Add-WindowsCapability -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 -Online
> ```

---

## Installation

### Option 1: Clone the repository

```powershell
git clone https://github.com/razafimandimby-IT/powershell-toolkit.git
cd powershell-toolkit
```

### Option 2: Download ZIP

Download the latest release from the [Releases page](https://github.com/razafimandimby-IT/powershell-toolkit/releases) and extract it to your preferred location.

### Set execution policy (if needed)

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Import modules (if running individual scripts from a different directory)

```powershell
# Navigate to the Scripts folder
cd .\Scripts\

# Or add the Scripts folder to your module path
$env:PSModulePath += ";$PWD\Scripts"
```

---

## Scripts Overview

| Script | Purpose | Key Outputs |
|---|---|---|
| `Get-ADUserReport.ps1` | Generate an AD user audit report | CSV report, disabled/inactive/locked user lists |
| `Get-SystemInventory.ps1` | Inventory a local or remote Windows machine | OS info, specs, installed software, disk usage |
| `Invoke-ITReport.ps1` | Master orchestrator producing an HTML summary | Consolidated HTML report with charts and tables |
| `Set-ITStandardization.ps1` | Apply IT standard configuration to a machine | Folder structure, permissions, registry-based GPO settings |

---

## Usage Examples

### Get-ADUserReport.ps1

Generate a full Active Directory user report and export it to CSV:

```powershell
.\Scripts\Get-ADUserReport.ps1 -OutputPath "C:\Reports\AD_Users.csv"
```

Generate a report filtering by a specific OU and only show disabled accounts:

```powershell
.\Scripts\Get-ADUserReport.ps1 -SearchBase "OU=Paris,DC=contoso,DC=com" -ShowDisabled -OutputPath "C:\Reports\Paris_Disabled.csv"
```

Generate a report for users inactive for more than 90 days:

```powershell
.\Scripts\Get-ADUserReport.ps1 -InactiveDays 90 -OutputPath "C:\Reports\InactiveUsers.csv"
```

---

### Get-SystemInventory.ps1

Inventory the local machine:

```powershell
.\Scripts\Get-SystemInventory.ps1 -OutputPath "C:\Reports\LocalInventory.json"
```

Inventory a remote computer with admin credentials:

```powershell
.\Scripts\Get-SystemInventory.ps1 -ComputerName "SRV-FILES-01" -IncludeSoftware -OutputPath "\\server\reports\SRV-FILES-01.json"
```

Export only disk information for multiple machines:

```powershell
"SRV-APP-01", "SRV-DB-01", "PC-WKS-045" | ForEach-Object {
    .\Scripts\Get-SystemInventory.ps1 -ComputerName $_ -OutputPath "C:\Reports\$_.json"
}
```

---

### Invoke-ITReport.ps1

Run the full reporting suite and generate an HTML dashboard:

```powershell
.\Scripts\Invoke-ITReport.ps1 -ADReportPath "C:\Reports\AD_Users.csv" -InventoryPath "C:\Reports\Inventory" -HtmlOutput "C:\Reports\IT_Dashboard.html"
```

Schedule a daily report with Task Scheduler integration:

```powershell
.\Scripts\Invoke-ITReport.ps1 -ADReportPath "C:\Reports\Daily\AD_Users.csv" `
    -InventoryPath "C:\Reports\Daily\Inventory" `
    -HtmlOutput "C:\Reports\Daily\Dashboard.html" `
    -CompanyName "Contoso Ltd."
```

---

### Set-ITStandardization.ps1

Apply standard folder structure and permissions to a machine:

```powershell
.\Scripts\Set-ITStandardization.ps1 -ComputerName "PC-WKS-045" -ApplyFolderStructure -ApplyRegistryPolicies
```

Preview what the script would do without making changes (dry run):

```powershell
.\Scripts\Set-ITStandardization.ps1 -ComputerName "PC-WKS-045" -DryRun
```

Apply only registry-based security policies:

```powershell
.\Scripts\Set-ITStandardization.ps1 -ApplyRegistryPolicies -RestrictControlPanel -DisableAdminShares
```

---

## Directory Structure

```
powershell-toolkit/
├── README.md
├── LICENSE
└── Scripts/
    ├── Get-ADUserReport.ps1
    ├── Get-SystemInventory.ps1
    ├── Invoke-ITReport.ps1
    └── Set-ITStandardization.ps1
```

---

## Logging

All scripts automatically generate a transcript log with the following naming convention:

```
.\Logs\Get-ADUserReport_2025-04-10_14-30-00.log
```

Logs capture every action with a timestamp, including warnings and errors, making it easy to audit what each script did during its execution.

---

## Contributing

Contributions are welcome! If you have a useful IT administration script or an improvement to an existing one:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-script`)
3. Commit your changes (`git commit -m "Add new feature"`)
4. Push to the branch (`git push origin feature/new-script`)
5. Open a Pull Request

Please ensure your scripts follow the existing patterns: comment-based help, parameter validation, and structured logging.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## Author

**Louis Denis RAZAFIMANDIMBY**

- GitHub: [@razafimandimby-IT](https://github.com/razafimandimby-IT)
- IT Administrator & Automation Enthusiast

Built with dedication to streamline IT operations through the power of PowerShell automation.

---

*Windows, PowerShell, and Active Directory are trademarks of Microsoft Corporation.*
