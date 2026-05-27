<#
.SYNOPSIS
    Professional Script Parameters and Configuration
    Version: 2024.06
.DESCRIPTION
    This script contains all the parameters and configuration settings used across the ADT-Projekt scripts.
    It centralizes variables such as group name prefixes, log paths, CSV paths, and mappings for OUs to groups.
    By importing this script in other scripts, we ensure consistency and ease of maintenance.
#>
# -------- GLOBAL VARIABLES --------

$DomainDN = (Get-ADDomain).DistinguishedName
$Domain   = (Get-ADDomain).DNSRoot
$CsvPath = "$PSScriptRoot\ADT-Master-Data-Model.csv"
$EnableProtection = $false # Default is to enable OU protection, set to $false to disable

$GroupNamePrefix = "TSG_"   

# This is used by 2.Create-OUStructure.ps1 to create the group names for the admin groups in each tier, it is then extended in 3.Create-AdminGroups.ps1 to include the tier number       
$SecurityGroupsMapping = @{
    "Tier0 Admins"           = "_Local_Admin_"
    "Tier1 Admins"           = "_Local_Admin_"
    "Tier1 Batch Users"      = "_Batch_"
    "Tier1 Remote Desktop"   = "_Remote_Desktop_"
    "Tier1 Service Accounts" = "_Service_Account_"
    "Tier1 SQL Admins"       = "_SQL_Admins_"
}
$SecurityGroupsDescription = @{
    "Tier0 Admins"           = "Local Administrator access"
    "Tier1 Admins"           = "Local Administrator access"
    "Tier1 Batch Users"      = "Log on as batch access"
    "Tier1 Remote Desktop"   = "RDP access"
    "Tier1 Service Accounts" = "Log on as service access"
    "Tier1 SQL Admins"       = "Local SQL Administrator access"
}
# This is used by step 2 to setup the tier groups for create the local admin groups,
# Example: if the nead for extra tiers group like 1.1 / 1.2 / 1.3 / 1.4 $TierGroups = "0","1","1.1","1.2","1.3","1.4","2"
$TierNumbers = "0","1","2"

# This is used by 3.Create-AdminGroups.ps1 to create the group names for the admin groups in each tier, it is then extended in 3.Create-AdminGroups.ps1 to include the tier number
# Move to the HouseKeeping scripts only used there
#$AdminsGroupsMapping = @{
#    "Admins"           = "_Local_Admin_"
#    "Batch Users"      = "_Batch_"
#    "Remote Desktop"   = "_Remote_Desktop_"
#    "Service Accounts" = "_Service_Account_"
#}
#$AdminsGroupsDescription = @{
#    "Admins"           = "Local Administrator access"
#    "Batch Users"      = "Log on as batch access"
#    "Remote Desktop"   = "RDP access"
#    "Service Accounts" = "Log on as service access"
#}
# This is used by 4.Set-OUDelegationV1.ps1 to construct the group names for the deny permissions
# List of Tier Top OU Add deny to Groups (will be applied for each OU)
# x and y are used to differentiate between the different Tier 1 and Tier 2 OUs, as they have different groups that need to be added to the deny permissions, 
# this is then used to include the actual values to be replaced
$TierGroups = @{
    ".Tier0"   = "T0_LocalAdmin_All"
    ".Tier1"   = "T0_LocalAdmin_All"
    ".Tier1x"  = "T1_LocalAdmin_All"
    ".Tier2"   = "T0_LocalAdmin_All"
    ".Tier2x"  = "T1_LocalAdmin_All"
    ".Tier2y"  = "T2_LocalAdmin_All"
}

# List of groups to deny (will be applied for each OU)
$Groups = @{
    "T1_LocalAdmin_All" = "T1_Users_All"
    "T2_LocalAdmin_All" = "T2_Users_All"
}
# This is used by 5.Migration Table Updater.ps1 to define the conversion table for updating the migration tables, it is then extended in 5.Migration Table Updater.ps1 to include the actual values to be replaced
$SourcePath = "$ScriptPath\MigrationsTables\OrgMigTablesFiles" # Sti til dine originale filer
$DestinationPath = "$ScriptPath\MigrationsTables\MigrationsTables_Updated" # Sti hvor de opdaterede filer skal gemmes

#Backup path for acl backup before modification
$BCKPath = "$ScriptPath\ACL_Backups"

# This is Parameters for 5.Create-GroupPolicies.ps1 to define the paths for migration tables and GPO backups, it is then used in 5.Create-GroupPolicies.ps1 to perform the GPO deployment workflow
$GPOImportRoot              = "$Global:RootPath\GPO-Import-Files\V1.0"
$MasterMigrationFileFolder  = "$Global:RootPath\GPO-Import-Files\v1.0"
$ACL_BackupsFolder          = "$Global:RootPath\ACL_Backups"


