<#
.SYNOPSIS
Synchronizes Tier users and Service Accounts to their corresponding security groups.

.DESCRIPTION
This script ensures that all users in Tier OUs are members of their
corresponding security groups.

It processes:
- Tier 0, 1 and 2 Users
- Tier 0 and 1 Service Accounts

If an account is missing from the correct group,
it will be added automatically.

Full logging:
C:\Logs\Sync-ADTierMembership.log

.NOTES
Requires ActiveDirectory module.
Must run with sufficient privileges.
#>

#--------------------------------------------------------------------------------------------
# Importing Functions like Write-Log function from Toolbox.ps1 for logging purposes
#--------------------------------------------------------------------------------------------
$ScriptPath = $PSScriptRoot 
$ScriptPath = $ScriptPath.Replace("\HouseKeeping","") # Adjust if the script is in a subfolder
#$ToolboxPath = "$ScriptPath\Toolbox\"
#."$ToolboxPath\Parameters.ps1"
#."$ToolboxPath\Toolbox.ps1"
$LogPath = "$PSScriptRoot\Logs"
$LogName = $MyInvocation.MyCommand.Name.Replace(".ps1","")
$LogFile = "$LogPath\$LogName.log"

# Base OU for Tiers or empty if Tiers are directly under domain
$DomainDN = (Get-ADDomain).DistinguishedName
$TopOULevelName = ""
$GroupNamePrefix = "TSG_T"
# ---------------------------------------------------------------------------------------------------
# ----- Write to Logfile 
# ---------------------------------------------------------------------------------------------------
function Write-Log {
   param (
    [String]$Message,
    [string]$Level = "INFO",
    [string]$LogFile = $Logfile
   )
 if (!(Test-Path "$LogPath")) {
    New-Item -Path "$LogPath" -ItemType Directory -Force | Out-Null
  }
 $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
 $Entry = "$TimeStamp [$Level] $Message"
 Add-Content -Path $LogFile -Value $Entry
 Write-Host $Entry
}
# ---------------------------------------------------------------------------------------------------
# Initialize-Script check ActiveDirectory module is available
# ---------------------------------------------------------------------------------------------------
function Load-Module-ActiveDirectory {

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        #Write-Log "ActiveDirectory module loaded successfully"
    }
    catch {
        Write-Log "Failed to load ActiveDirectory module: $_" "ERROR"
        exit 1
    }
}
# ---------------------------------------------------------------------------------------------------
# Eensure log folder exists
# ---------------------------------------------------------------------------------------------------
function CheckLogPath {
  if (!(Test-Path "$LogPath")) {
    New-Item -Path "$LogPath" -ItemType Directory -Force | Out-Null
  }
}
# ---------------------------------------------------------------------------------------------------
# Setup Tier top OU based on configuration
# ---------------------------------------------------------------------------------------------------
if ($TopOULevelName) {
    $TierLevelOU = "OU=$TopOULevelName,$DomainDN"
} else {
    $TierLevelOU = $DomainDN
}
# ---------------------------------------------------------------------------------------------------
# ----- Write to Logfile 
# ---------------------------------------------------------------------------------------------------

Function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile = $LogFile,
        [int]$RetentionDays = 1
    )

    # Create log directory if it doesn't exist
    $LogPath = Split-Path $LogFile
    if (!(Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }

    # ---------- Cleanup  ----------
    if (Test-Path $LogFile) {
        $CutoffDate = (Get-Date).AddDays(-$RetentionDays)

        $FilteredLines = Get-Content $LogFile | Where-Object {
            try {
                $LineDate = [datetime]::ParseExact(
                    $_.Substring(0,19),
                    'yyyy-MM-dd HH:mm:ss',
                    $null
                )
                $LineDate -ge $CutoffDate
            }
            catch {
                # keep the linjes that don't match the expected format (e.g. header or malformed lines)
                $true
            }
        }

        Set-Content -Path $LogFile -Value $FilteredLines
    }

    # ---------- Write the new data to logfil ----------
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "$TimeStamp [$Level] $Message"

    Add-Content -Path $LogFile -Value $Entry
    Write-Host $Entry
}

# ---------------------------------------------------------------------------------------------------
# Adding the Tier users for Tier 1 and 2
# ---------------------------------------------------------------------------------------------------
function Add-UsersToGroups {
    for ($tier = 0; $tier -lt 3; $tier++) {
        #Write-Log "Processing Tier $tier Users"
  try {
        $searchBase = Get-ADOrganizationalUnit -Filter "*" | select name,DistinguishedName | Where-Object {$_.name -Like "*Tier$Tier Accounts"}
        $groupName  = "$GroupNamePrefix${tier}_${TierSubLevel}Users_All"
        $users        = Get-ADUser -SearchBase $searchBase.DistinguishedName -Filter * -Properties DistinguishedName 
        $group        = Get-ADGroup -Identity $groupName -ErrorAction Stop
        $groupMembers = Get-ADGroupMember -Identity $group -Recursive
   }
    catch {
          Write-Log "Error retrieving users or group for Tier $tier : $_" "ERROR"
         continue
    }
    $memberHash = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($member in $groupMembers) {
           $memberHash.Add($member.DistinguishedName) | Out-Null
    }
    foreach ($user in $users) {
        if (-not $memberHash.Contains($user.DistinguishedName)) {
                try {
                    Add-ADGroupMember -Identity $group -Members $user -ErrorAction Stop
                    Write-Log "Added user $($user.SamAccountName) to $groupName"
                }
                catch {
                    Write-Log "Failed to add user $($user.SamAccountName): $_" "ERROR"
                }
            }
        } 
    }
}
# ---------------------------------------------------------------------------------------------------
# Adding the Service Accounts for Tier 0 and 1 to Groups
# ---------------------------------------------------------------------------------------------------
function Add-ServiceAccountsToGroups {
    for ($tier = 0; $tier -le 1; $tier++) {
        #Write-Log "Processing Tier $tier Service Accounts"
        try {
         $searchBase = Get-ADOrganizationalUnit -Filter "*" | select name,DistinguishedName | Where-Object {$_.name -Like "*Tier$Tier Services Accounts"}
         $groupName  = "$GroupNamePrefix${tier}_${TierSubLevel}ServiceAccounts_All"
         $users        = Get-ADUser -SearchBase $searchBase.DistinguishedName -Filter * -Properties DistinguishedName 
         $group        = Get-ADGroup -Identity $groupName -ErrorAction Stop
         $groupMembers = Get-ADGroupMember -Identity $group -Recursive
         }
        catch {
            Write-Log "Error retrieving service accounts or group for Tier $tier : $_" "ERROR"
            continue
        }
        $memberHash = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($member in $groupMembers) {
            $memberHash.Add($member.DistinguishedName) | Out-Null
        }
        foreach ($user in $users) {

            if (-not $memberHash.Contains($user.DistinguishedName)) {
                try {
                    Add-ADGroupMember -Identity $group -Members $user -ErrorAction Stop
                    Write-Log "Added service account $($user.SamAccountName) to $groupName"
                }
                catch {
                    Write-Log "Failed to add service account $($user.SamAccountName): $_" "ERROR"
                }
            }
        }
    }
}
# ---------------------------------------------------------------------------------------------------
# Main Script Execution
# ---------------------------------------------------------------------------------------------------
Load-Module-ActiveDirectory
CheckLogPath
Add-UsersToGroups
Add-ServiceAccountsToGroups
