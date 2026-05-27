#--------------------------------------------------------------------------------------------
# <#
# .SYNOPSIS
#     Update group SIDs and domain names in GPO Backup.xml and gpreport.xml files under an import root.
#
# .DESCRIPTION
#     Scans each GPO folder under the import root, loads Backup.xml and gpreport.xml, resolves group
#     accounts against Active Directory, updates SID elements in XML and GptTmpl.inf files, and replaces
#     old domain FQDN and NetBIOS names with new values. Preserves file encodings when writing changes.
#
# .PARAMETER ImportRoot
#     The root folder that contains GPO import folders. Default: "..\GPO-Import-Files"
#
# .EXAMPLE
#     .\5.0.Update-GPO-Data-Before-Import.PS1
#     Runs the script with defaults to update SIDs and domain names under the configured ImportRoot.
#
# .NOTES
#     - Requires the ActiveDirectory module.
#     - Designed to be run with sufficient privileges to read/write GPO backup folders.
#>
#--------------------------------------------------------------------------------------------
# Importing functions like `Write-Log` from Toolbox.ps1 for logging purposes
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
# $GPOImportRoot              = "$ScriptPath\GPO-Import-Files"
# Domain replacement settings (old -> new)
$OldDomainFqdn = "ADT-LAB.LOCAL"
$NewDomainFqdn = (Get-ADDomain).Forest
$OldDomainNetbios = "ADT-LAB"
$NewDomainNetbios = (Get-ADDomain).NetBIOSName

# Helper: replace text in a file preserving BOM/encoding
function Replace-String-PreserveEncoding {
    param(
        [string]$Path,
        [string]$Old,
        [string]$New
    )

    if (-not (Test-Path $Path)) { return $false }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $encoding = [System.Text.Encoding]::UTF8
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $encoding = [System.Text.Encoding]::Unicode }
        elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $encoding = [System.Text.Encoding]::BigEndianUnicode }
        elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $encoding = [System.Text.Encoding]::UTF8 }

        $content = $encoding.GetString($bytes)
        if ($content -match [Regex]::Escape($Old)) {
            $newContent = $content -replace [Regex]::Escape($Old), $New
            $newBytes = $encoding.GetBytes($newContent)
            [System.IO.File]::WriteAllBytes($Path, $newBytes)
            return $true
        }
        return $false
    }
        catch {
            ("ERROR replacing domain in {0}: {1}" -f $Path, $_) | Out-File $LogFile -Append
            return $false
        }
}

# Helper: derive a searchable core from a SamAccountName (e.g. TSG_T1_Users_All_GPO -> T1_Users_All)
function Get-SamCore {
    param([string]$Sam)
    if ([string]::IsNullOrWhiteSpace($Sam)) { return $Sam }
    $parts = $Sam.Trim() -split '_'
    if ($parts.Length -gt 2) {
        return ($parts[1..($parts.Length - 2)] -join '_')
    }
    return $Sam.Trim()
}

try {
    $gpoDirs = Get-ChildItem -Path $GPOImportRoot -Directory -ErrorAction SilentlyContinue

    foreach ($gpoDir in $gpoDirs) {
        $XmlPath = Join-Path $gpoDir.FullName 'Backup.xml'
        $otherFile = Join-Path $gpoDir.FullName 'gpreport.xml'
        $files = @($XmlPath, $otherFile)

        "PROCESSING FOLDER: $($gpoDir.FullName)" | Out-File $LogFile -Append

        # Pre-load Backup.xml for this folder so we can copy existing SID values into gpreport.xml when AD lookup fails
        $backupDoc = $null
        $backupNs = $null
        if (Test-Path $XmlPath) {
            try {
                $backupDoc = New-Object System.Xml.XmlDocument
                $backupDoc.PreserveWhitespace = $true
                $backupDoc.LoadXml((Get-Content -Raw $XmlPath))
                $backupNs = New-Object System.Xml.XmlNamespaceManager($backupDoc.NameTable)
                $backupNs.AddNamespace("ns", "http://www.microsoft.com/GroupPolicy/GPOOperations")
            }
            catch {
                "WARN: could not preload backup doc: $XmlPath - $_" | Out-File $LogFile -Append
                $backupDoc = $null
            }
        }
# --------------------------------------------------------------------------------------------
# For each GPO folder, we want to update the SIDs for any groups in the Backup.xml and gpreport.xml files, by looking up the group in AD and getting the current SID, 
# we also want to replace any old domain names with the new domain name in those files, and in any GptTmpl.inf files under those folders
# Loop through all files we want to process in this folder (Backup.xml and gpreport.xml), if they exist, and update SIDs and domain names
#---------------------------------------------------------------------------------------------
        foreach ($file in $files) {
            "PROCESSING: $file" | Out-File $LogFile -Append

            if (-not (Test-Path $file)) { "SKIP (not found): $file" | Out-File $LogFile -Append; continue }

            $xmlDoc = New-Object System.Xml.XmlDocument
            $xmlDoc.PreserveWhitespace = $true
            $xmlDoc.LoadXml((Get-Content -Raw $file))

            $ns = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
            $ns.AddNamespace("ns", "http://www.microsoft.com/GroupPolicy/GPOOperations")

            $groups = $xmlDoc.SelectNodes("//ns:Group", $ns)

            foreach ($group in $groups) {
                $upnNode = $group.SelectSingleNode("ns:UPN", $ns)
                $samNode = $group.SelectSingleNode("ns:SamAccountName", $ns)

                $upn = $null
                if ($upnNode) { $upn = $upnNode.InnerText.Trim() }

                $sam = $null
                if ($samNode) { $sam = $samNode.InnerText.Trim() }

                if (-not $upn -and -not $sam) { continue }

                # Prefer UPN (left of @) when present, otherwise use SamAccountName
                if ($upn) {
                    $sam = if ($upn -match "@") { ($upn.Split('@'))[0].Trim() } else { $upn }
                }

                if ([string]::IsNullOrWhiteSpace($sam)) { continue }

                try {
                    # Try SamAccountName first, then Name as fallback
                    $adGroup = $null
                    try { $adGroup = Get-ADGroup -Filter "SamAccountName -eq '$sam'" -Properties SID,SamAccountName -ErrorAction Stop } catch {}
                    if (-not $adGroup) {
                        try { $adGroup = Get-ADGroup -Filter "Name -eq '$sam'" -Properties SID,SamAccountName -ErrorAction Stop } catch {}
                    }
                    # If still not found, derive a core from the sam and try a wildcard search
                    if (-not $adGroup) {
                        $core = Get-SamCore -Sam $sam
                        if (-not [string]::IsNullOrWhiteSpace($core)) {
                            $likePattern = "*$core*"
                            try { $adGroup = Get-ADGroup -Filter "SamAccountName -like '$likePattern'" -Properties SID,SamAccountName -ErrorAction Stop } catch {}
                        }
                    }

                    if ($adGroup) {
                        $newSID = $adGroup.SID.Value

                        # If AD returned a different SamAccountName/Name, update the dataset to match AD
                        $adSamName = $null
                        try { $adSamName = $adGroup.SamAccountName } catch {}
                        if (-not $adSamName) { try { $adSamName = $adGroup.Name } catch {} }
                        if ($adSamName) {
                            try {
                                if ($samNode) {
                                    $current = $samNode.InnerText.Trim()
                                    if ($current -ne $adSamName) {
                                        $samNode.RemoveAll()
                                        $c = $xmlDoc.CreateCDataSection($adSamName)
                                        $samNode.AppendChild($c) | Out-Null
                                        "UPDATED DATASET: group SamAccountName changed: $current -> $adSamName in $file" | Out-File $LogFile -Append
                                    }
                                }
                                else {
                                    # Create SamAccountName node if missing
                                    $newSamNode = $xmlDoc.CreateElement("SamAccountName", "http://www.microsoft.com/GroupPolicy/GPOOperations")
                                    $c = $xmlDoc.CreateCDataSection($adSamName)
                                    $newSamNode.AppendChild($c) | Out-Null
                                    $group.AppendChild($newSamNode) | Out-Null
                                    "ADDED DATASET SamAccountName: $adSamName in $file" | Out-File $LogFile -Append
                                }
                            } catch { }
                        }

                        $sidNode = $group.SelectSingleNode("ns:Sid", $ns)
                        $oldSID = $null
                        if ($sidNode) { $oldSID = $sidNode.InnerText.Trim() } else {
                            $sidNode = $xmlDoc.CreateElement("Sid", "http://www.microsoft.com/GroupPolicy/GPOOperations")
                            $group.AppendChild($sidNode) | Out-Null
                        }

                        $sidNode.RemoveAll()
                        $cdata = $xmlDoc.CreateCDataSection($newSID)
                        $sidNode.AppendChild($cdata) | Out-Null

                        "MATCH FOUND: $upn -> $newSID" | Out-File $LogFile -Append

                        # If an old SID existed, update any GptTmpl.inf under the XML folder
                        if ($oldSID -and $oldSID -ne $newSID) {
                            $rootFolder = Split-Path $file
                            $infFiles = Get-ChildItem -Path $rootFolder -Filter GptTmpl.inf -Recurse -File -ErrorAction SilentlyContinue
                            foreach ($inf in $infFiles) {
                                try {
                                    # Read raw bytes to preserve encoding
                                    $bytes = [System.IO.File]::ReadAllBytes($inf.FullName)
                                    $encoding = [System.Text.Encoding]::UTF8
                                    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $encoding = [System.Text.Encoding]::Unicode }
                                    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $encoding = [System.Text.Encoding]::BigEndianUnicode }
                                    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $encoding = [System.Text.Encoding]::UTF8 }

                                    $content = $encoding.GetString($bytes)
                                    if ($content -match [Regex]::Escape($oldSID)) {
                                        $newContent = $content -replace [Regex]::Escape($oldSID), $newSID
                                        $newBytes = $encoding.GetBytes($newContent)
                                        [System.IO.File]::WriteAllBytes($inf.FullName, $newBytes)
                                        "UPDATED INF: $($inf.FullName) replaced $oldSID -> $newSID" | Out-File $LogFile -Append
                                        # Also replace domain names in INF files we update
                                        try {
                                            if (Replace-String-PreserveEncoding -Path $inf.FullName -Old $OldDomainFqdn -New $NewDomainFqdn) { "DOMAINS REPLACED in: $($inf.FullName)" | Out-File $LogFile -Append }
                                            if (Replace-String-PreserveEncoding -Path $inf.FullName -Old $OldDomainNetbios -New $NewDomainNetbios) { "DOMAINS REPLACED in: $($inf.FullName)" | Out-File $LogFile -Append }
                                        } catch { }
                                    }
                                }
                                catch {
                                    "ERROR updating INF $($inf.FullName): $_" | Out-File $LogFile -Append
                                }
                            }
                        }
                    }
                    else {
                        "NO MATCH: $upn (sam: $sam)" | Out-File $LogFile -Append
                    }
                }
                catch {
                    "ERROR processing $upn  $_" | Out-File $LogFile -Append
                }
            }
            
            # Also handle <Name>/<SID> pairs in the Types namespace (gpreport.xml format)
            $typesNs = New-Object System.Xml.XmlNamespaceManager($xmlDoc.NameTable)
            $typesNs.AddNamespace("t", "http://www.microsoft.com/GroupPolicy/Types")

            $nameNodes = $xmlDoc.SelectNodes("//t:Name", $typesNs)
            foreach ($nameNode in $nameNodes) {
                $nameTxt = $nameNode.InnerText.Trim()
                if ([string]::IsNullOrWhiteSpace($nameTxt)) { continue }

                $idx = $nameTxt.LastIndexOf('\')
                if ($idx -ge 0) { $sam = $nameTxt.Substring($idx + 1).Trim() } else { $sam = $nameTxt.Trim() }
                if ([string]::IsNullOrWhiteSpace($sam)) { continue }

                "DEBUG: TYPES ENTRY: '$nameTxt' parsed sam='$sam'" | Out-File $LogFile -Append

                try {
                    $adGroup = $null
                    try { $adGroup = Get-ADGroup -Filter "SamAccountName -eq '$sam'" -Properties SID -ErrorAction Stop } catch {}
                    if (-not $adGroup) {
                        try { $adGroup = Get-ADGroup -Filter "Name -eq '$sam'" -Properties SID -ErrorAction Stop } catch {}
                    }

                    if ($adGroup) {
                        $newSID = $adGroup.SID.Value

                        $sidNode = $nameNode.ParentNode.SelectSingleNode("t:SID", $typesNs)
                        if (-not $sidNode) {
                            $sidNode = $xmlDoc.CreateElement("SID", "http://www.microsoft.com/GroupPolicy/Types")
                            $nameNode.ParentNode.AppendChild($sidNode) | Out-Null
                        }

                        $oldSID = $null
                        if ($sidNode) { $oldSID = $sidNode.InnerText.Trim() }

                        $sidNode.RemoveAll()
                        $text = $xmlDoc.CreateTextNode($newSID)
                        $sidNode.AppendChild($text) | Out-Null

                        "MATCH FOUND (types): $nameTxt -> $newSID" | Out-File $LogFile -Append

                        # If AD returned a different SamAccountName/Name, update the Name node in the Types entry
                        $adSamName = $null
                        try { $adSamName = $adGroup.SamAccountName } catch {}
                        if (-not $adSamName) { try { $adSamName = $adGroup.Name } catch {} }
                        if ($adSamName) {
                            try {
                                $newNameTxt = $nameTxt
                                if ($idx -ge 0) {
                                    $prefix = $nameTxt.Substring(0, $idx + 1)
                                    $newNameTxt = $prefix + $adSamName
                                }
                                else {
                                    $newNameTxt = $adSamName
                                }
                                if ($newNameTxt -ne $nameTxt) {
                                    $nameNode.RemoveAll()
                                    $nameNode.AppendChild($xmlDoc.CreateTextNode($newNameTxt)) | Out-Null
                                    "UPDATED DATASET (types): Name changed: $nameTxt -> $newNameTxt" | Out-File $LogFile -Append
                                }
                            } catch { }
                        }

                        if ($oldSID -and $oldSID -ne $newSID) {
                            $rootFolder = Split-Path $file
                            $infFiles = Get-ChildItem -Path $rootFolder -Filter GptTmpl.inf -Recurse -File -ErrorAction SilentlyContinue
                            foreach ($inf in $infFiles) {
                                try {
                                    # Read raw bytes to preserve encoding
                                    $bytes = [System.IO.File]::ReadAllBytes($inf.FullName)
                                    $encoding = [System.Text.Encoding]::UTF8
                                    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $encoding = [System.Text.Encoding]::Unicode }
                                    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $encoding = [System.Text.Encoding]::BigEndianUnicode }
                                    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $encoding = [System.Text.Encoding]::UTF8 }

                                    $content = $encoding.GetString($bytes)
                                    if ($content -match [Regex]::Escape($oldSID)) {
                                        $newContent = $content -replace [Regex]::Escape($oldSID), $newSID
                                        $newBytes = $encoding.GetBytes($newContent)
                                        [System.IO.File]::WriteAllBytes($inf.FullName, $newBytes)
                                        "UPDATED INF: $($inf.FullName) replaced $oldSID -> $newSID" | Out-File $LogFile -Append
                                    }
                                }
                                catch {
                                    "ERROR updating INF $($inf.FullName): $_" | Out-File $LogFile -Append
                                }
                            }
                                # After processing INF files for SID updates, also perform domain replacements in those INF files
                                try {
                                    $infFiles2 = Get-ChildItem -Path $rootFolder -Filter GptTmpl.inf -Recurse -File -ErrorAction SilentlyContinue
                                    foreach ($inf2 in $infFiles2) {
                                        try {
                                            if (Replace-String-PreserveEncoding -Path $inf2.FullName -Old $OldDomainFqdn -New $NewDomainFqdn) { "DOMAINS REPLACED in: $($inf2.FullName)" | Out-File $LogFile -Append }
                                            if (Replace-String-PreserveEncoding -Path $inf2.FullName -Old $OldDomainNetbios -New $NewDomainNetbios) { "DOMAINS REPLACED in: $($inf2.FullName)" | Out-File $LogFile -Append }
                                        } catch { }
                                    }
                                } catch { }
                        }
                    }
                    else {
                        # Try to copy SID from Backup.xml Groups if preloaded
                        $copied = $false
                        if ($backupDoc) {
                            "DEBUG: searching backup for sam='$sam'" | Out-File $LogFile -Append
                            $bGroups = $backupDoc.SelectNodes("//ns:Group", $backupNs)
                            foreach ($b in $bGroups) {
                                $bSam = $null
                                $bSamNode = $b.SelectSingleNode("ns:SamAccountName", $backupNs)
                                if ($bSamNode) { $bSam = $bSamNode.InnerText.Trim() }
                                        $coreForMatch = Get-SamCore -Sam $sam
                                        if ($bSam -and ($bSam -eq $sam -or ($coreForMatch -and $bSam -like "*$coreForMatch*"))) {
                                    $bSidNode = $b.SelectSingleNode("ns:Sid", $backupNs)
                                    if ($bSidNode) {
                                        $newSID = $bSidNode.InnerText.Trim()

                                        $sidNode = $nameNode.ParentNode.SelectSingleNode("t:SID", $typesNs)
                                        if (-not $sidNode) {
                                            $sidNode = $xmlDoc.CreateElement("SID", "http://www.microsoft.com/GroupPolicy/Types")
                                            $nameNode.ParentNode.AppendChild($sidNode) | Out-Null
                                        }

                                        $sidNode.RemoveAll()
                                        $text = $xmlDoc.CreateTextNode($newSID)
                                        $sidNode.AppendChild($text) | Out-Null

                                        "COPIED SID FROM BACKUP (types): $nameTxt -> $newSID" | Out-File $LogFile -Append
                                        $copied = $true
                                        break
                                    }
                                }
                            }
                            if (-not $copied) { "DEBUG: not found in backup for sam='$sam'" | Out-File $LogFile -Append }
                        }

                        if (-not $copied) {
                            # Fallback to manual map if AD lookup failed
                            if ($ManualSIDMap.ContainsKey($sam)) {
                                $newSID = $ManualSIDMap[$sam]

                                $sidNode = $nameNode.ParentNode.SelectSingleNode("t:SID", $typesNs)
                                if (-not $sidNode) {
                                    $sidNode = $xmlDoc.CreateElement("SID", "http://www.microsoft.com/GroupPolicy/Types")
                                    $nameNode.ParentNode.AppendChild($sidNode) | Out-Null
                                }

                                $sidNode.RemoveAll()
                                $text = $xmlDoc.CreateTextNode($newSID)
                                $sidNode.AppendChild($text) | Out-Null

                                "MANUAL MAP USED (types): $nameTxt -> $newSID" | Out-File $LogFile -Append
                            }
                            else {
                                "NO MATCH (types): $nameTxt (sam: $sam)" | Out-File $LogFile -Append
                            }
                        }
                    }
                }
                catch {
                    "ERROR processing (types) $nameTxt  $_" | Out-File $LogFile -Append
                }
            }

            $xmlDoc.Save($file)

            # Replace domain names in the file we just saved
            try {
                $replaced = $false
                if (Replace-String-PreserveEncoding -Path $file -Old $OldDomainFqdn -New $NewDomainFqdn) { $replaced = $true }
                if (Replace-String-PreserveEncoding -Path $file -Old $OldDomainNetbios -New $NewDomainNetbios) { $replaced = $true }
                if ($replaced) { "DOMAINS REPLACED in: $file" | Out-File $LogFile -Append }
            }
            catch {
                ("ERROR replacing domain in saved file {0}: {1}" -f $file, $_) | Out-File $LogFile -Append
            }

            "SUCCESS: File updated: $file" | Out-File $LogFile -Append
        }
    }
}
catch {
    "FATAL ERROR: $_" | Out-File $LogFile -Append
}

"===== END $(Get-Date) =====" | Out-File -FilePath $LogFile -Append
