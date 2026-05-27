
# <#
# .SYNOPSIS
# Creates and installs the group Managed Service Account (gMSA) 'T1-housekeeping' on the current domain controller,
# ensures the KDS root key exists, adds the gMSA to the T1_LocalAdmin_All group, and verifies installation and group membership.
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
$gMSAName         = "T1-housekeeping"
$DnsHostName      = "$gMSAName.$((Get-ADDomain).DNSRoot)"
$Description      = "gMSA for T1 Tiering House HouseKeeping Tasks"
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
# WAIT FOR THE gMSA CREATION
# --------------------------------
Start-Sleep 2
# --------------------------------
# INSTALL THE gMSA
# --------------------------------
Install-ADServiceAccount -Identity $gMSAName
if ($?) {
    Write-Log "gMSA '$gMSAName' installed successfully on $DomainController"
}
else {
    Write-Log "Failed to install gMSA '$gMSAName' on $DomainController"
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
# ADD gMSA to TSG_T1_LocalAdmin_All
# --------------------------------
Add-ADGroupMember -Identity "$($GroupNamePrefix)T1_LocalAdmin_All" -Members "$gMSAName$"
if ($?) {
    Write-Log "gMSA '$gMSAName' added to group '$($GroupNamePrefix)T1_LocalAdmin_All' successfully"
}
else {
    Write-Log "Failed to add gMSA '$gMSAName' to group '$($GroupNamePrefix)T1_LocalAdmin_All'"
}

# --------------------------------
# VERIFY gMSA GROUP MEMBERSHIP
# --------------------------------

Get-ADGroupMember -Identity "$($GroupNamePrefix)T1_LocalAdmin_All" | Where-Object {$_.Name -like $gMSAName}
