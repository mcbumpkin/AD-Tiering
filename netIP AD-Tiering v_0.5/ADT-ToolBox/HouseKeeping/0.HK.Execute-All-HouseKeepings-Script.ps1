#---------------------------------------------------------------------------------------------------------------------------------------------------
# This script executes all housekeeping scripts in the correct order.
# It is intended to be run as a scheduled task using the gMSA created in the previous step, but can also be run manually for testing purposes.
#---------------------------------------------------------------------------------------------------------------------------------------------------
#--------------------------------------------------------------------------------------------
# Variables and Logging Setup
#--------------------------------------------------------------------------------------------
$LogPath = "$PSScriptRoot\Logs"
$LogName = $MyInvocation.MyCommand.Name.Replace(".ps1","")
$LogFile = "$LogPath\$LogName.log"
# ---------------------------------------------------------------------------------------------------
# ----- Write to Logfile 
# ---------------------------------------------------------------------------------------------------
function Write-Log {
   param (
    [String]$Message,
    [string]$Level = "INFO",
    [string]$LogFile = $Logfile
   )
 $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
 $Entry = "$TimeStamp [$Level] $Message"
 Add-Content -Path $LogFile -Value $Entry
 Write-Host $Entry
}


#Start-Sleep -Seconds 1
./1.HK.Add-Users-To-Tier-Groups.ps1
#Start-Sleep -Seconds 1
./2.HK.Create-Servers-AD-Groups.ps1


