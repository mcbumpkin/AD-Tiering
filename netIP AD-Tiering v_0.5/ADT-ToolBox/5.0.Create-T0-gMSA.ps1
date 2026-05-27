
# <#
# .SYNOPSIS
# Creates and installs the group Managed Service Account (gMSA) 'T0-housekeeping' on the current domain controller,
# ensures the KDS root key exists, adds the gMSA to the T0_LocalAdmin_All group, and verifies installation and group membership.
# >
#
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
# --------------------------------
# VARIABLES
# --------------------------------
$DomainController = $env:COMPUTERNAME
$gMSAName         = "T0-housekeeping"
$DnsHostName      = "$gMSAName.$((Get-ADDomain).DNSRoot)"
$Description      = "gMSA for T0 Tiering House HouseKeeping Tasks"
$AllowedComputer  = Get-ADComputer $DomainController
# --------------------------------
# LOAD MODULE
# --------------------------------
Load-Module-ActiveDirectory
CheckLogPath
# --------------------------------
# ENSURE KDS ROOT KEY EXISTS
# (Required once per domain)
# --------------------------------
if (-not (Get-KdsRootKey -ErrorAction SilentlyContinue)) {
    Write-Log "Creating KDS Root Key..."
    Add-KdsRootKey -EffectiveTime (Get-Date).AddHours(-10)
}
# --------------------------------
# Check if the gMSA already exists
# --------------------------------
try {
    if (Get-ADServiceAccount -Identity $gMSAName -ErrorAction SilentlyContinue) {
    Write-Log "gMSA '$gMSAName' already exists. Skipping creation."
    exit 0
   }  
  } 
   catch {
    Write-Log "The gMSA account '$gMSAName' does not already exist: $_"
   }
# --------------------------------
# CREATE THE gMSA
# --------------------------------
New-ADServiceAccount `
    -Name $gMSAName `
    -DNSHostName $DnsHostName `
    -PrincipalsAllowedToRetrieveManagedPassword $AllowedComputer `
    -Description $Description `
    -Server $DomainController
if ($?) {
    Write-Log "gMSA '$gMSAName' created successfully on $DomainController"
}
else {
    Write-Log "Failed to create gMSA '$gMSAName' on $DomainController"
}

# --------------------------------
# INSTALL THE gMSA (with retry loop wrapped in try/catch)
# --------------------------------
$maxAttempts = 5
$attempt = 0
$installed = $false
while (-not $installed -and $attempt -lt $maxAttempts) {
    $attempt++
    try {
        Install-ADServiceAccount -Identity $gMSAName -ErrorAction Stop
        Write-Log "gMSA '$gMSAName' installed successfully on $DomainController (attempt $attempt)"
        $installed = $true
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Log "Attempt $attempt Exception installing gMSA '$gMSAName' on $DomainController $errMsg"
        if ($attempt -lt $maxAttempts) {
            Write-Log "Waiting 5 seconds before retrying..."
            Start-Sleep -Seconds 5
            Write-Log "Retrying installation (attempt $($attempt + 1))..."
        }
    }
}
if (-not $installed) {
    Write-Log "Failed to install gMSA '$gMSAName' after $maxAttempts attempts"
}
# --------------------------------
# VERIFY THE gMSA INSTALLATION
# --------------------------------
$result = Test-ADServiceAccount $gMSAName
 if ($result -eq $true) {
     Write-Log "gMSA '$gMSAName' verified successfully on $DomainController"
     }
 else {
     Write-Log "gMSA '$gMSAName' verified unsuccessfully on $DomainController"
    }

# --------------------------------
# ADD gMSA to TSG_T0_LocalAdmin_All
# --------------------------------
Add-ADGroupMember -Identity "$($GroupNamePrefix)T0_LocalAdmin_All" -Members "$gMSAName$"
if ($?) {
    Write-Log "gMSA '$gMSAName' added to group '$($GroupNamePrefix)T0_LocalAdmin_All' successfully"
}
else {
    Write-Log "Failed to add gMSA '$gMSAName' to group '$($GroupNamePrefix)T0_LocalAdmin_All'"
}

