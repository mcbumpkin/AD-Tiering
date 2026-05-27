<#
.SYNOPSIS
Creates Tier-based Active Directory security groups for servers based on a CSV data model.

.DESCRIPTION
This script reads a CSV file containing an AD data model and automatically creates
security groups for servers in Tier 0 and Tier 1 environments.

For each server object found in the defined Organizational Units (OUs), the script:
- Builds the appropriate OU Distinguished Name (DN)
- Generates standardized group names based on Tier and role
- Checks if the group already exists
- Creates missing groups with proper naming and descriptions

The script supports multiple administrative roles such as:
- Local Administrators
- Remote Desktop Users
- Batch Users
- Service Accounts
- SQL Administrators

Logging is written to a file under C:\Logs and includes informational, success, and error messages.

.PARAMETER CsvPath
Path to the CSV file containing the AD data model.
Default: C:\ADT-Projekt\1.AD-DataModel.csv

.PARAMETER LogPath
Directory where the log file will be stored.
Default: C:\Logs

.FUNCTIONALITY
- Reads and validates CSV input
- Iterates through Tier 0 and Tier 1 structures
- Dynamically builds OU paths
- Retrieves Active Directory computer objects
- Creates Domain Local security groups per server and role
- Prevents duplicate group creation
- Logs all operations

.FUNCTION CreateGroups
Processes a list of computers and creates corresponding AD groups.

For each computer:
- Constructs group name using:
  Prefix + Tier + Role + Hostname
- Checks if the group already exists
- Creates the group if missing
- Assigns appropriate description and OU location

.INPUTS
CSV file with columns such as:
- COMPANY
- LEVEL0
- LEVEL1
- LEVEL2

.OUTPUTS
- Active Directory security groups
- Log file entries in C:\Logs\Create-Admins-Tiers-Groups.log

.NOTES
- Requires ActiveDirectory module
- Requires appropriate permissions to create AD groups
- Error handling is set to SilentlyContinue, so logging should be reviewed for issues

.EXAMPLE
Run the script:
PS> .\2.Create-Security-Groups.ps1

This will read the CSV file and create missing groups for all Tier 0 and Tier 1 servers.

#>
# ---------------------------------------------------------------------------------------------------
# Initialization Parameters
# ---------------------------------------------------------------------------------------------------
$DomainDN = (Get-ADDomain).DistinguishedName

#--------- Set Error Handling to Silent ------
#$ErrorActionPreference = "SilentlyContinue"

#--------------------------------------------------------------------------------------------
# Importing Functions like Write-Log function from Toolbox.ps1 for logging purposes
#--------------------------------------------------------------------------------------------
$Global:RootPath = $PSScriptRoot
$ScriptPath = $PSScriptRoot # Antager at skripterne ligger i samme mappe
$ToolboxPath = "$ScriptPath\Toolbox\"
."$ToolboxPath\Parameters.ps1"
."$ToolboxPath\Toolbox.ps1"
$LogPath = "$ScriptPath\Logs\"
$Logfile = "$LogPath\Create-Admins-Tiers-Groups.log"
# ------------------------------------------------------------
# Load powershell modules
# ------------------------------------------------------------
Load-Module-ActiveDirectory
CheckLogPath

#----------------------------------------------------------------------------------------------------------------------------------
# Function that runs through all server objects in Tier 0/1 and checks whether these groups have been created or are being created
#----------------------------------------------------------------------------------------------------------------------------------
function CreateGroups{
    param (
        $Computers,
        $CurrentDN
    )
    $TireNumber=$Level0Name.Trim(".").Replace("Tier","")
    ForEach ($Computer in $Computers)
    {
     $computer = Get-ADComputer -Identity $Computer.Name -Properties *
     $HostName = $Computer.Name
     $GroupName = "$GroupNamePrefix"+"T"+$TireNumber+$SecurityGroupsMapping[$Level2Name]+$HostName
     #--------------------------------------------------------------------------------------------------------------    
     # Creating groups for each server in Tier 0/1 and checking if they already exist
     #--------------------------------------------------------------------------------------------------------------
     if (@(Get-ADGroup -Identity "$GroupName").Count) {
         Write-Log "Already exists: $GroupName"
     } else {
        $OUDescription = $SecurityGroupsDescription[$Level2Name]
        Write-Log  "$HostName - Creating $OUDescription group"
        New-ADGroup -Name "$GroupName" -samAccountName "$GroupName" -Description "$OUDescription for $HostName" -Path "$CurrentDN" -GroupCategory Security -GroupScope Global 
     }   
   } 
}
# ---------------------------------------------------------------------------------------------------
# ----- Validate and Read CSV file
# ---------------------------------------------------------------------------------------------------
  if (!(Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
   }
   Write-Log "Loading CSV file: $CsvPath"
   try {
    $Data = Import-Csv -Path $CsvPath -Delimiter ";"
    Write-Log "CSV loaded successfully. Rows: $($Data.Count)" "SUCCESS"
   }
   catch {
    Write-Log "Failed to load CSV: $_" "ERROR"
    exit 1
   }
# ---------------------------------------------------------------------------------------------------
# Lopping through the Tiers and processing the data to create groups for each server in Tier 0/1/2
# ---------------------------------------------------------------------------------------------------
   foreach ($Tier in $TierNumbers) {
    Write-Log "Processing Tier $Tier"
    $AllGroups = $data | Where-Object { $_.LEVEL3 -like "Tier$Tier All Admins" }
    if($AllGroups.Count -eq 0)
    {
     Write-Log "No Admins All found for Tier $Tier in CSV" "WARNING"
     continue
    } else {
     $CompanyName = $AllGroups.COMPANY
     $Level0Name = $AllGroups.LEVEL0
     $Level1Name = $AllGroups.LEVEL1
     $Level2Name = $AllGroups.LEVEL2
     $Level3Name = $AllGroups.LEVEL3
# ---------------------------------------------------------------------------------------------------
# Create all Admins All group for each Tier
# ---------------------------------------------------------------------------------------------------
    if (-not ([string]::IsNullOrEmpty($CompanyName))) { 
        $AllGroupsOU = "OU=$level3Name,OU=$level2Name,OU=$level1Name,OU=$level0Name,OU=$companyName,$DomainDN"
    } else {
      $AllGroupsOU = "OU=$level3Name,OU=$level2Name,OU=$level1Name,OU=$level0Name,$DomainDN"
    } 
    $TireNumber=$Level0Name.Trim(".").Replace("Tier","")
    $GroupName = "$GroupNamePrefix"+"T"+$TireNumber+"_LocalAdmin_All"
    try {
      $CheckGroup = Get-ADGroup -Identity "$GroupName" -ErrorAction SilentlyContinue
    }
    catch {
        $CheckGroup = $null
        $OUDescription = "Local Administrator access for all servers in Tier $Tier"
        Write-Log  "Creating $OUDescription group: $GroupName"
        New-ADGroup -Name "$GroupName" -samAccountName "$GroupName" -Description "$OUDescription" -Path "$AllGroupsOU" -GroupCategory Security -GroupScope Global 
    }
# ---------------------------------------------------------------------------------------------------
# Create All User Groups for each Tier
# ---------------------------------------------------------------------------------------------------
      if (-not ([string]::IsNullOrEmpty($CompanyName))) { 
         $AllGroupsOU = "OU=$level1Name,OU=$level0Name,OU=$companyName,$DomainDN"
      } else {
       $AllGroupsOU = "OU=$level1Name,OU=$level0Name,$DomainDN"
      } 
      $UserGroupName = "$GroupNamePrefix"+"T"+$TireNumber+"_Users_All"
      try {
      if (@(Get-ADGroup -Identity "$UserGroupName").Count) {
         Write-Log "Users group already exists: $UserGroupName"
       } 
      }
      catch {
        $OUDescription = "Local User access for Tier $Tier"
        Write-Log  "Creating $OUDescription group: $UserGroupName"
        New-ADGroup -Name "$UserGroupName" -samAccountName "$UserGroupName" -Description "$OUDescription" -Path "$AllGroupsOU" -GroupCategory Security -GroupScope Global 
      }
      
# ---------------------------------------------------------------------------------------------------
# Create All Service Accounts Groups for tier 0 and 1 only
# ---------------------------------------------------------------------------------------------------
      $ServiceAccountsOU = "Tier$TireNumber Service Accounts"
      if ($Tier -ne 2) {
      if (-not ([string]::IsNullOrEmpty($CompanyName))) { 
         $AllGroupsOU = "OU=$ServiceAccountsOU,OU=Tier$TireNumber Security Groups,OU=$level0Name,OU=$companyName,$DomainDN" 
      } else {
        $AllGroupsOU = "OU=$ServiceAccountsOU,OU=Tier$TireNumber Security Groups,OU=$level0Name,$DomainDN"
      } 
      $UserGroupName = "$GroupNamePrefix"+"T"+$TireNumber+"_ServiceAccounts_All"
      try {
      if (@(Get-ADGroup -Identity "$UserGroupName").Count) {
          Write-Log "Service Accounts group already exists: $UserGroupName"
       } 
      }
      catch {
        $OUDescription = "Local User access for Tier $Tier"
        Write-Log  "Creating $OUDescription group: $UserGroupName"
        New-ADGroup -Name "$UserGroupName" -samAccountName "$UserGroupName" -Description "$OUDescription" -Path "$AllGroupsOU" -GroupCategory Security -GroupScope Global 
      }
     } 
    }     
# ---------------------------------------------------------------------------------------------------
# Collecting all Servers for each Tier to create the local groups for each server
# ---------------------------------------------------------------------------------------------------
    $Serverslist = $data | Where-Object { $_.LEVEL1 -like "Tier$Tier Servers*" }
    if($Serverslist.Count -eq 0)
     {
      Write-Log "No Servers Groups found for Tier $Tier in CSV" "WARNING"
      continue
     }
# ---------------------------------------------------------------------------------------------------
# Building OU structure for groups creation for each server in Tier 0/1
# ---------------------------------------------------------------------------------------------------
    foreach ($row in $results) {
     foreach ($Server in $Serverslist) {
     if (
         ![string]::IsNullOrWhiteSpace($row.COMPANY) -and 
         $row.COMPANY.Trim() -ne "."
       ) 
      {
       $CompanyName = $row.COMPANY
       $Level0Name  = $row.LEVEL0
       $Level1Name  = $row.LEVEL1
       $Level2Name  = $row.LEVEL2
       $CurrentDN   = "OU=$level2Name,OU=$level1Name,OU=$level0Name,OU=$companyName,$DomainDN"  
       $Level0Server= $Server.LEVEL0
       $Level1Server= $Server.LEVEL1
       $ServerOU="OU=$Level1Server,OU=$Level0Server,OU=$CompanyName,$DomainDN"
       Write-Log "Processed with OU: $CurrentDN" "INFO"
      } else {
        #Write-Log "Skipping COMPANY (empty or '.')" "INFO"
       $Level0Name  = $row.LEVEL0
       $Level1Name  = $row.LEVEL1
       $Level2Name  = $row.LEVEL2
       $CurrentDN   = "OU=$level2Name,OU=$level1Name,OU=$level0Name,$DomainDN"   
       $ServerOU    ="OU=$Level1Server,OU=$CompanyName,$DomainDN"     
       Write-Log "Processed with OU: $CurrentDN" "INFO"
      }
      Write-Log "---------- Starting Create the Local Tier Groups ----------"
      $Servers = Get-ADComputer -Filter {(Enabled -eq $true)} -SearchBase "$ServerOU" -SearchScope Subtree
      if($Servers.Name.Length -ne 0)
      {
       CreateGroups $Servers $CurrentDN
      }
    }   
  }
}
