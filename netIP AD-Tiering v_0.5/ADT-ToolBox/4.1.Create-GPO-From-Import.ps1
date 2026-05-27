<#
.SYNOPSIS
    Automates the deployment of Group Policy Objects (GPOs) from backup, including migration table processing and import.

.DESCRIPTION
This script performs a full GPO deployment workflow based on existing GPO backups.
It reads GPO backup folders, extracts GPO names and backup IDs from the backup.xml files, ensures GPOs exist in the domain, and imports the GPO settings. It also handles migration table processing if a corresponding .migtable file is present.     
       
.PARAMETER GPOImportRoot
  Path to the root folder containing GPO backups (each in its own GUID-named subfolder).
         
.PARAMETER LogFile
  Path to the log file where execution details will be written.
         
.NOTES
  Requirements:
    - The script must be run with appropriate permissions to create and modify GPOs in the target domain.  
    and the script Migration script is run Update-GPO-Data-Before-Import.PS1 under the toolbox folderbefore this script to ensure the .migtable files are up to date.
    - The GPO backup folders must be structured correctly, with each GPO backup in a subfolder named after the GPO's GUID, containing a backup.xml file and optionally a .migtable file for migration table processing.     
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
# ------------------------------------------------------------
# Load powershell modules
# ------------------------------------------------------------
Load-Module-GroupPolicy
Load-Module-ActiveDirectory
CheckLogPath

# ------------------------------------------------------------
# STEP 1 - IMPORT GPOs
# ------------------------------------------------------------
Write-Log "Importing GPOs..."
$IMP_NAME = ""
$ImportFolders = Get-ChildItem -Path $GPOImportRoot -Directory -ErrorAction Stop
foreach ($Folder in $ImportFolders) {
    try {
        $ImportXmlPath = Join-Path $Folder.FullName "backup.xml"
        if (!(Test-Path $ImportXmlPath)) {
            Write-Log "Missing backup.xml in $($Folder.Name)" "ERROR"
            continue
        }
        $GpoName = $null
        [xml]$Xml = Get-Content $ImportXmlPath

        if ($Xml.GroupPolicyBackupScheme.GroupPolicyObject.GroupPolicyCoreSettings.DisplayName.InnerText) {  
            $GpoName = $Xml.GroupPolicyBackupScheme.GroupPolicyObject.GroupPolicyCoreSettings.DisplayName.InnerText
        }
        if (!$GpoName) {
         Write-Log "Could not determine GPO name from backup.xml in $($Folder.Name)" "ERROR"
        continue
        }   

        $BackupId = $Xml.GroupPolicyBackupScheme.GroupPolicyObject.GroupPolicyCoreSettings.ID.InnerText

        if (!$GpoName -or !$BackupId) {
            Write-Log "Invalid backup.xml in $($Folder.Name)" "ERROR"
            continue
        }
        Write-Log "Processing GPO: $GpoName"
        # Ensure GPO exists
        if (!(Get-GPO -Name $GpoName$($IMP_NAME) -ErrorAction SilentlyContinue)) {
            New-GPO -Name $GpoName$($IMP_NAME) | Out-Null
            Write-Log "Created GPO"
        }
        # Import GPO backup
            $GPOStatus = Import-GPO `
                -BackupGpoName $GpoName `
                -Path $GPOImportRoot `
                -TargetName $GpoName$($IMP_NAME) `
                -CreateIfNeeded `
                -ErrorAction Stop
        
        Write-Log "Imported successfully"
    } catch {
        Write-Log "Failed processing $($Folder.Name): $_" "ERROR"
    }
}

Write-Log "===== SCRIPT END ====="