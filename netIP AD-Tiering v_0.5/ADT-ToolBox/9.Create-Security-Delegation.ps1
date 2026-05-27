<#
.SYNOPSIS
Applies an explicit DENY (GenericAll) permission for specified groups on target Organizational Units in Active Directory.

.DESCRIPTION
Retrieves the ACL for each target OU, creates a DENY (GenericAll) access rule for the specified group, skips if a matching deny already exists, and applies the updated ACL. Actions and errors are logged via the Write-Log function from the Toolbox. Requires the ActiveDirectory module and appropriate privileges to modify AD ACLs.

.PARAMETER Groups
Array of group names (without prefix) to receive the deny.

.PARAMETER GroupNamePrefix
Optional prefix used when building full group names.

.PARAMETER TierGroups
Optional list of tier/OU names used to locate target OUs.

.EXAMPLE
.\4.Create-Security-Delegation.ps1

.NOTES
Must be run with privileges to read and modify AD ACLs. Ensure Parameters.ps1 and Toolbox.ps1 are loaded and the script runs with sufficient rights.
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

Load-Module-ActiveDirectory
CheckLogPath

Write-Log "Starting the delegation for configured groups on configured OUs"

function Sanitize-Name {
    param([string]$Name)
    return ($Name -replace '[^a-zA-Z0-9_-]', '_')
}

function Apply-AllowToOU {
    param(
        [string]$OU,
        [string]$Group
    )
    try {
        Write-Log "Processing Group='$Group' on OU='$OU'"

        # Get ACL
        $acl = Get-Acl -Path "AD:$OU" -ErrorAction Stop
        if (-not $acl) { throw "Failed to retrieve ACL for AD:$OU" }
        # Convert group to identity
        try { $identity = New-Object System.Security.Principal.NTAccount($Group) }
        catch { throw "Failed to create NTAccount for '$Group': $($_)" }
        # Create DENY rule (Full Control)
        Write-Log "Creating Allow rule (GenericAll) for $Group on $OU"
        $AllowRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $identity,
            [System.DirectoryServices.ActiveDirectoryRights]::GenericAll,
            [System.Security.AccessControl.AccessControlType]::Allow,
            [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
        )

       
        # Check for existing matching deny rule
        $existing = $acl.Access | Where-Object {
            ($_.IdentityReference -eq $identity) -and
            ($_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) -and
            (($_.ActiveDirectoryRights -band [System.DirectoryServices.ActiveDirectoryRights]::GenericAll) -ne 0) 
        }

        if ($existing) {
            Write-Log "Allow rule already exists for $Group on $OU; skipping add" "INFO"
            return
        }

        # Add and apply
        $acl.AddAccessRule($AllowRule)
        Write-Log "Applying updated ACL for $OU"
        Set-Acl -Path "AD:$OU" -AclObject $acl -ErrorAction Stop
        Write-Log "SUCCESS: Allow applied to $Group on $OU" "SUCCESS"
    }
    catch {
        Write-Log "ERROR processing Allow Group='$Group' OU='$OU': $($_.Exception.Message)" "ERROR"
    }
}
function Apply-DenyToOU {
    param(
        [string]$OU,
        [string]$Group
    )
    try {
        Write-Log "Processing Group='$Group' on OU='$OU'"

        # Get ACL
        $acl = Get-Acl -Path "AD:$OU" -ErrorAction Stop
        if (-not $acl) { throw "Failed to retrieve ACL for AD:$OU" }
        # Convert group to identity
        try { $identity = New-Object System.Security.Principal.NTAccount($Group) }
        catch { throw "Failed to create NTAccount for '$Group': $($_)" }
        # Create DENY rule (Full Control)
        Write-Log "Creating DENY rule (GenericAll) for $Group on $OU"
        $denyRule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $identity,
            [System.DirectoryServices.ActiveDirectoryRights]::GenericAll,
            [System.Security.AccessControl.AccessControlType]::Deny
        )

        # Check for existing matching deny rule
        $existing = $acl.Access | Where-Object {
            ($_.IdentityReference -eq $identity) -and
            ($_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny) -and
            (($_.ActiveDirectoryRights -band [System.DirectoryServices.ActiveDirectoryRights]::GenericAll) -ne 0)
        }

        if ($existing) {
            Write-Log "DENY rule already exists for $Group on $OU; skipping add" "INFO"
            return
        }

        # Add and apply
        $acl.AddAccessRule($denyRule)
        Write-Log "Applying updated ACL for $OU"
        Set-Acl -Path "AD:$OU" -AclObject $acl -ErrorAction Stop
        Write-Log "SUCCESS: DENY applied to $Group on $OU" "SUCCESS"
    }
    catch {
        Write-Log "ERROR processing Deny Group='$Group' OU='$OU': $($_.Exception.Message)" "ERROR"
    }
}



foreach ($key in $TierGroups.keys) {
    $OUName = "$($Key)" 
    $OUName = $OUName.Replace("y","") # Remove wildcard for matching
    $OUName = $OUName.Replace("x","") # Remove wildcard for matching
    $OUName = $OUName.Replace("z","") # Remove wildcard for matching
    $OUName = $OUName.Replace("gMSA","") # Remove wildcard for matching
    $AllowGroup = "$GroupNamePrefix$($TierGroups[$Key])"
     # For each group, apply the deny to all OUs (pairwise)
    $OUs=Get-ADOrganizationalUnit -Filter "*" | select name,DistinguishedName | Where-Object {$_.name -Like "$OUName"}
    Apply-AllowToOU -OU $OUs.DistinguishedName -Group $AllowGroup 
}

# Loop through OUs and Groups one-to-one (pairwise)

$grpCount = $Groups.Count

foreach ($Key in $Groups.keys) {
    $GroupName = "$GroupNamePrefix$($Key)" 
    $DenyGroup = "$GroupNamePrefix$($Groups[$Key])"
    # For each group, apply the deny to all OUs (pairwise)
    $OUs=Get-ADGroup -Filter "*" | select name,DistinguishedName | Where-Object {$_.name -Like "$GroupName"} 
    Apply-DenyToOU -OU $OUs.DistinguishedName -Group $DenyGroup   
    # For Tier0 OU, apply the deny to the corresponding group
    $targetKey = $TierGroups.Keys | Where-Object { $_ -like "*0" }
    $OUs=Get-ADOrganizationalUnit -Filter "*" | select name,DistinguishedName | Where-Object {$_.name -Like "$($targetKey)"}
    Apply-DenyToOU -OU $OUs.DistinguishedName -Group $DenyGroup
}
    
Write-Log "Completed DENY delegation for configured groups on configured OUs"