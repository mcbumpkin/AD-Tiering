<#
.SYNOPSIS
Creates an Organizational Unit (OU) structure in Active Directory based on a CSV data model.

.DESCRIPTION
This script reads a CSV file containing a hierarchical OU data model and creates the corresponding
Organizational Unit (OU) structure in Active Directory.

The script is designed to support a tier-based AD model (e.g. Tier0, Tier1, Tier2) and will:
- Dynamically build OU structures based on input data
- Skip empty or invalid values
- Avoid duplicate OU creation (idempotent behavior)
- Log all actions to both a text log and an HTML report

The script includes full logging and error handling, making it suitable for production use.

-----------------------------
DATA MODEL STRUCTURE (CSV)
-----------------------------
The CSV file must use semicolon (;) as delimiter and contain the following columns:

COMPANY;LEVEL0;LEVEL1;LEVEL2

Column description:

COMPANY
- Optional top-level OU
- If empty or contains ".", it will be ignored
- In that case, LEVEL0 becomes the root OU

LEVEL0
- Mandatory (per row)
- Defines the first OU level under either DOMAIN or COMPANY
- Leading "." will be removed (e.g. ".TIER0" becomes "TIER0")

LEVEL1
- Optional
- Child OU under LEVEL0

LEVEL2
- Optional
- Child OU under LEVEL1

-----------------------------
OU STRUCTURE LOGIC
-----------------------------
Depending on input:

With COMPANY:
    DOMAIN
        └── COMPANY
            └── LEVEL0
                └── LEVEL1
                    └── LEVEL2

Without COMPANY (empty or "."):
    DOMAIN
        └── LEVEL0
            └── LEVEL1
                └── LEVEL2

-----------------------------
FEATURES
-----------------------------
- Idempotent OU creation (will not recreate existing OUs)
- Supports optional protection from accidental deletion
- Full logging:
    - Text log: C:\Logs\OUCreation_<timestamp>.log
- Detailed per-row processing logs
- Error handling with continuation (script does not stop on single failure)

-----------------------------
FUNCTIONS
-----------------------------

Write-Log
- Handles all logging output
- Writes to:
    - Console
    - Text log file
    - HTML report (color-coded)

Ensure-OU
- Ensures an OU exists at a given path
- Creates the OU if it does not exist
- Applies "Protect from accidental deletion" based on parameter
- Returns the Distinguished Name (DN) for chaining

-----------------------------
.PARAMETER CsvPath
Path to the CSV file containing the OU data model.

Default:
       C:\ADT-Projekt\1.AD-DataModel.csv

-----------------------------
.PARAMETER EnableProtection
Boolean flag to enable or disable "Protect object from accidental deletion" on created OUs.

Default: $true

-----------------------------
.EXAMPLE
Run using default CSV file:
    C:\.\1.Create-OUStructure.ps1

-----------------------------

.NOTES
- Requires ActiveDirectory PowerShell module (RSAT)
- Must be run with sufficient permissions to create OUs
- Designed for structured AD environments (e.g. tiering model)

#>

#--------------------------------------------------------------------------------------------
# Importing Functions like Write-Log function from Toolbox.ps1 for logging purposes
#--------------------------------------------------------------------------------------------
$Global:RootPath = $PSScriptRoot
$ScriptPath = $PSScriptRoot 
$ToolboxPath = "$ScriptPath\Toolbox\"
."$ToolboxPath\Parameters.ps1"
."$ToolboxPath\Toolbox.ps1"
$LogPath = "$ScriptPath\Logs"
$LogName = $MyInvocation.MyCommand.Name.Replace(".ps1","")
$LogFile = "$LogPath\$LogName.log"
$EnableProtection=$True
# ------------------------------------------------------------
# Load powershell modules
# ------------------------------------------------------------
Load-Module-ActiveDirectory
CheckLogPath

#----------------------------------------------------------------
# - Validate CSV File - Check if file exists and can be loaded   
#----------------------------------------------------------------
if (!(Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}
#Write-Log "Loading CSV file: $CsvPath"
try {
    $Data = Import-Csv -Path $CsvPath -Delimiter ";"
    #Write-Log "CSV loaded successfully. Rows: $($Data.Count)" "SUCCESS"
}
catch {
    Write-Log "Failed to load CSV: $_" "ERROR"
    exit 1
}

# ----- Get domain DN -----
$DomainDN = (Get-ADDomain).DistinguishedName
Write-Log "Domain DN: $DomainDN"
Write-Log "OU Protection Enabled: $EnableProtection"

# --------------------------------
# ----- OU creation function -----
# --------------------------------

function Create-OU {
    param (
        [string]$Name,
        [string]$ParentDN
    )
    $OUdn = "OU=$Name,$ParentDN"
    try {
        $existing = Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$OUdn)" -ErrorAction SilentlyContinue
        if ($existing) {
            #Write-Log "OU already exists: $OUdn" "INFO"
            Set-ADOrganizationalUnit -Identity $OUdn -ProtectedFromAccidentalDeletion $EnableProtection
        }
        else {
            $OUSAT = New-ADOrganizationalUnit -Name $Name -Path $ParentDN -ProtectedFromAccidentalDeletion $EnableProtection -PassThru
            Write-Log "Created OU: $OUdn (Protection=$EnableProtection)" "SUCCESS"
        }
    }
    catch {
        Write-Log "Failed to create OU: $OUdn - $_" "ERROR"
    }
    return $OUdn
}

# ------------------------
# ----- Process data -----
# ------------------------
foreach ($row in $Data) {
    #Write-Log "Processing row: COMPANY='$($row.COMPANY)' LEVEL0='$($row.LEVEL0)' LEVEL1='$($row.LEVEL1)' LEVEL2='$($row.LEVEL2)'' LEVEL3='$($row.LEVEL3)'" "INFO"
    $currentDN = $DomainDN
    # ----- COMPANY -----
    if (
        ![string]::IsNullOrWhiteSpace($row.COMPANY) -and  $row.COMPANY.Trim() -ne "."
    ) {
        $companyName = $row.COMPANY.Trim()
        $currentDN = Create-OU -Name $companyName -ParentDN $currentDN
    }
    else {
       # Write-Log "Skipping COMPANY (empty or '.')" "INFO"
    }

    # ----- LEVEL0 -----
    if (![string]::IsNullOrWhiteSpace($row.LEVEL0)) {
        #$level0Name = $row.LEVEL0.Trim().TrimStart(".")
        $level0Name = $row.LEVEL0.Trim()
        $currentDN = Create-OU -Name $level0Name -ParentDN $currentDN
           
    }
    else {
        Write-Log "LEVEL0 is missing - skipping row" "ERROR"
        continue
    }
    
    # ----- LEVEL1 -----
    if (![string]::IsNullOrWhiteSpace($row.LEVEL1)) {
        $level1Name = $row.LEVEL1.Trim()
        $currentDN = Create-OU -Name $level1Name -ParentDN $currentDN
    }

    # ----- LEVEL2 -----
    if (![string]::IsNullOrWhiteSpace($row.LEVEL2)) {
        $level2Name = $row.LEVEL2.Trim()
        $currentDN = Create-OU -Name $level2Name -ParentDN $currentDN
    }
    # ----- LEVEL3 -----
    if (![string]::IsNullOrWhiteSpace($row.LEVEL3)) {
        $level3Name = $row.LEVEL3.Trim()
        $currentDN = Create-OU -Name $level3Name -ParentDN $currentDN
    }
}
Write-Log "OU creation process completed" "SUCCESS"
Write-Host "`nLogs saved to:"
Write-Host $LogFile
