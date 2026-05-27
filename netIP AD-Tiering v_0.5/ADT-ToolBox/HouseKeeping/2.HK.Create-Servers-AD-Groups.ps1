<#
.SYNOPSIS
 Creates per-server admin/security groups for servers in each tier based on CSV input, and
 backs up group members to CSV before removing groups for decommissioned servers.

.DESCRIPTION
 Reads a CSV that defines company, tier and OU structure, creates domain-local security groups
 per server according to configured mappings and naming prefix. Logs actions via the Toolbox
 `Write-Log` function. During cleanup, the script exports current group members to
 `\<LogPath>\GroupBackups\` before deleting groups whose server objects are no longer present.

.PARAMETER CsvPath
 Path to the input CSV file that defines OU and tier information.

.PARAMETER GroupNamePrefix
 Prefix used for generated group names.

.PARAMETER AdminsGroupsMapping
 Hashtable mapping logical admin group types to naming suffixes used when constructing per-server group names.

.PARAMETER DryRun
 Switch to perform a dry-run: log deletions without actually removing groups.

.EXAMPLE
 .\2.HK.Create-Servers-AD-Groups
 
.NOTES
 Requires ActiveDirectory module and appropriate privileges to create/delete groups and query computers.
 Ensure `Parameters.ps1` and `Toolbox.ps1` are loaded before running.
#>

# ---------------------------------------------------------------------------------------------------
# ----- Set Error Handling to Silent 
# ---------------------------------------------------------------------------------------------------
$ErrorActionPreference = "SilentlyContinue"
Remove-Variable * -ErrorAction SilentlyContinue
#--------------------------------------------------------------------------------------------
# Importing Functions like Write-Log function from Toolbox.ps1 for logging purposes
#--------------------------------------------------------------------------------------------
$ScriptPath = $PSScriptRoot 
$ScriptPath = $ScriptPath.Replace("\HouseKeeping","") # Adjust if the script is in a subfolder
$DomainDN = (Get-ADDomain).DistinguishedName
$GroupNamePrefix = "TSG_" 
$GroupNamePrefix = $GroupNamePrefix+"T"
$LogPath = "$PSScriptRoot\Logs"
$LogName = $MyInvocation.MyCommand.Name.Replace(".ps1","")
$LogFile = "$LogPath\$LogName.log"
$CsvPath = "C:\ADT-Projekt\Toolbox\ADT-Master-Data-Model.csv"

#--------------------------------------------------------------------------------------------
$AdminsGroupsMapping = @{
    "Admins"           = "_Local_Admin_"
    "Batch Users"      = "_Batch_"
    "Remote Desktop"   = "_Remote_Desktop_"
    "Service Accounts" = "_Service_Account_"
}
$AdminsGroupsDescription = @{
    "Admins"           = "Local Administrator access"
    "Batch Users"      = "Log on as batch access"
    "Remote Desktop"   = "RDP access"
    "Service Accounts" = "Log on as service access"
}

Import-Module ActiveDirectory -ErrorAction Stop

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

    # Ensure log directory exists
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


#----------------------------------------------------------------
# - Validate CSV File - Check if file exists and can be loaded   
#----------------------------------------------------------------
 if (!(Test-Path $CsvPath)) {
     Write-Error "CSV file not found: $CsvPath"
     exit 1
 }
 #Write-Log "Loading CSV file: $CsvPath"
  try {
     #Loading CSV file with UTF8 encoding (adjust if your file uses a different encoding)
     $Data = Import-Csv -Path $CsvPath -Delimiter ";"
     #Write-Log "CSV loaded successfully. Rows: $($Data.Count)" "SUCCESS"
 }
 catch {
    Write-Log "Failed to load CSV: $_" "ERROR"
    exit 1
 }
# ----------------------------------------------------------------
# - Process CSV file data to find the correct OU for servers 
# ----------------------------------------------------------------
foreach ($row in $Data) {
    if($row.LEVEL1 -like "*Servers*")
    {
     $TierLevelName = $row.LEVEL1
     $TierNumber = [regex]::Match($TierLevelName, '\d+')
     $TierNumber = $TierNumber.Value
     if (-not ([string]::IsNullOrEmpty($($row.COMPANY)))) {
         $TierLevel = "OU=$TierLevelName,OU=$($row.LEVEL0),OU=$($row.COMPANY),$DomainDN"
         $SecTierLevel = "OU=$($row.LEVEL0),OU=$($row.COMPANY),$DomainDN"
     } else {
         $TierLevel = "OU=$TierLevelName,OU=$($row.LEVEL0),$DomainDN"
         $SecTierLevel = "OU=$($row.LEVEL0),$DomainDN"
     }
     $ServerOU = "$TierLevel"
     $GroupOU = "OU=Tier$TierNumber Security Groups,$SecTierLevel"
    } else {
      continue
    }
    #---------------------------------------------------------------------------------------------------------
    # Get the list of servers in the current tier and log the group prefix and description for each OU match
    #---------------------------------------------------------------------------------------------------------
    $ServerList = Get-ADComputer -Filter {(Enabled -eq $true)} -SearchBase "$ServerOU" -SearchScope Subtree
    foreach ($key in $AdminsGroupsMapping.Keys) {
            $GroupNamePrefixNew = "$GroupNamePrefix$TierNumber" + $AdminsGroupsMapping[$key]
            $GroupDescription = $AdminsGroupsDescription[$key]
            $GroupPlacementOU =  Get-ADOrganizationalUnit -Filter "Name -like '*Tier$TierNumber $key*'" -SearchBase $GroupOU
        if ($GroupPlacementOU -ne $null) {
            foreach ($server in $ServerList) {
                # Construct group name: Prefix + TierNumber + Mapping + ServerName
                $NewServerGroup = $GroupNamePrefixNew+$server.Name 
                $ExistingGroup = Get-ADGroup -Filter "Name -eq '$NewServerGroup'" -ErrorAction SilentlyContinue
                 if ($ExistingGroup) {
                 # Write-Log "Already exists: $NewServerGroup"
                } else {  
                $Status = New-ADGroup -Name "$NewServerGroup" -samAccountName "$NewServerGroup" `
                -Description "$GroupDescription for $HostName" -Path $GroupPlacementOU `
                -GroupCategory Security -GroupScope DomainLocal -ErrorAction SilentlyContinue
                Write-Log "Creating group for server: $($server.Name) with prefix: $GroupNamePrefixNew$($server.Name) in OU: $($GroupPlacementOU.Name)"
                }
                
            }
        } else {
         Continue
        }    
    }
}

# ----------------------------------------------------------------
# Cleanup: Remove groups for decommissioned servers
# ----------------------------------------------------------------
#Write-Log "Starting cleanup: removing groups for computers that no longer exist" "INFO"
try {
    if (-not $GroupNamePrefix) {
        Write-Log "No GroupNamePrefix defined, skipping cleanup" "WARN"
    } else {
        # Get all groups that start with the prefix
        $filter = "Name -like '$GroupNamePrefix*'"
        $AllGroups = Get-ADGroup -Filter $filter -ResultSetSize $null -ErrorAction SilentlyContinue

        if ($AllGroups) {
            # Build regex to extract server name: prefix + tierNumber + mapping + servername
            $escapedPrefix = [regex]::Escape($GroupNamePrefix)
            $mappingPattern = ''
            if ($AdminsGroupsMapping) {
                $mappingPattern = ($AdminsGroupsMapping.Values | ForEach-Object {[regex]::Escape($_)}) -join '|'
            }

            foreach ($g in $AllGroups) {
                $groupName = $g.Name
                $serverName = $null

                if ($mappingPattern -ne '') {
                    # Expect: Prefix + TierNumber + Mapping + ServerName
                    $regex = "^$escapedPrefix(?<tier>\d+)(?<mapping>($mappingPattern))(?<server>.+)$"
                } else {
                    # Fallback: Prefix + TierNumber + optional separators + ServerName
                    $regex = "^$escapedPrefix(?<tier>\d+)(?:[-_ ]*)(?<server>.+)$"
                }

                $m = [regex]::Match($groupName, $regex)
                if ($m.Success) {
                    $serverName = $m.Groups['server'].Value
                    # Normalize server name: remove surrounding non-alphanumeric chars and trailing '$'
                    $serverName = $serverName -replace '^[^A-Za-z0-9]+|[^A-Za-z0-9]+$',''
                    $serverName = $serverName.TrimEnd('$')
                    # If an FQDN was captured, use the left-most label
                    if ($serverName -match '\.') {
                        $serverName = $serverName.Split('.')[0]
                    }

                    if ($serverName) {
                        $comp = Get-ADComputer -Filter "Name -eq '$serverName'" -ErrorAction SilentlyContinue
                        if (-not $comp) {
                            Write-Log "Deleting group $groupName because computer $serverName does not exist" "INFO"
                            try {
                                if ($DryRun) {
                                    Write-Log "Dry-run: would delete group $groupName" "INFO"
                                }
                                else {
                                            # Backup current group members before deletion
                                            try {
                                                $backupDir = Join-Path $LogPath 'GroupBackups'
                                                New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
                                                $backupFile = Join-Path $backupDir ("{0}-{1}.csv" -f $groupName, (Get-Date -Format 'yyyyMMddHHmmss'))
                                                $members = Get-ADGroupMember -Identity $g -Recursive -ErrorAction SilentlyContinue | Select-Object Name,SamAccountName,ObjectClass
                                                if ($members) { $members | Export-Csv -Path $backupFile -NoTypeInformation -Encoding UTF8 }
                                                Write-Log "Backed up members of $groupName to $backupFile" "INFO"
                                            }
                                            catch {
                                                Write-Log "Failed to backup members for $groupName $_" "WARN"
                                            }
                                            Remove-ADGroup -Identity $g -Confirm:$false -ErrorAction Stop
                                        }
                            }
                            catch {
                                Write-Log "Could not delete group $groupName - $_" "ERROR"
                            }
                        }
                    }
                    else {
                        Write-Log "Unable to extract server name from group $groupName" "WARN"
                    }
                }
            }
        } else {
            Write-Log "No groups found with prefix $GroupNamePrefix" "INFO"
        }
    }
}
catch {
    Write-Log "Error during cleanup: $_" "ERROR"
}
