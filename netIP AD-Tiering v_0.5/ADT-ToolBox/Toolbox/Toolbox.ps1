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
# Eensure log folder exists
# ---------------------------------------------------------------------------------------------------
function CheckLogPath {
  if (!(Test-Path "$LogPath")) {
    New-Item -Path "$LogPath" -ItemType Directory -Force | Out-Null
  }
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
# Initialize-Script check GroupPolicy module is available
# ---------------------------------------------------------------------------------------------------
function Load-Module-GroupPolicy {
   try {
        Import-Module GroupPolicy -ErrorAction Stop 
        #Write-Log "GroupPolicy module loaded successfully"
    }
    catch {
        Write-Log "Failed to load GroupPolicy module: $_" "ERROR"
        exit 1
    }
}