# ------------------------------------------------------------------
# Adding types for GUI
# ------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ------------------------------------------------------------------
# Check PowerShell version and restart in PowerShell 7 if needed
# ------------------------------------------------------------------

# Ensure script runs in PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or newer." -ForegroundColor Yellow
    # Try to find pwsh.exe
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        Write-Host "PowerShell 7 is not installed." -ForegroundColor Red
        Write-Host "Download it here: https://aka.ms/powershell"
        Write-Host "or install by using the command: winget install --id Microsoft.PowerShell --source winget"
        exit 1
    }
    # Try to resolve script path safely
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) {
        Write-Host "Unable to determine script path. Please run this script from a file." -ForegroundColor Red
        exit 1
    }
    Write-Host "Restarting script in PowerShell 7..." -ForegroundColor Green
    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File "`"$scriptPath`""
    exit
}
# -------------------------------
# Paths
# -------------------------------
$Global:RootPath = $PSScriptRoot
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolboxPath = Join-Path $ScriptPath "Toolbox"

. "$ToolboxPath\Parameters.ps1"
. "$ToolboxPath\Toolbox.ps1"

# -------------------------------
# Helper: Execute script
# -------------------------------
function Execute-ScriptGUI {
    param (
        [string]$ScriptName,
        [string]$Description
    )

    $LogBox.AppendText("STARTER: $Description`r`n")

    try {
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwsh) { $exe = $pwsh.Source } else { $exe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source }
        if (-not $exe) { throw "Ingen PowerShell-eksekverbar fundet til at køre scriptet." }

        $scriptFile = Join-Path $ScriptPath $ScriptName

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $exe
        $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptFile`""
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($startInfo)
        $stdOut = $proc.StandardOutput.ReadToEnd()
        $stdErr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        if ($stdOut) { $LogBox.AppendText($stdOut + "`r`n") }
        if ($stdErr) {
            $LogBox.AppendText("ERROR OUTPUT:`r`n" + $stdErr + "`r`n")
            $LogBox.ForeColor = 'Red'
        } else {
            $LogBox.ForeColor = 'Black'
        }

        if ($proc.ExitCode -eq 0) {
            $LogBox.AppendText("SUCCESS: $Description færdig.`r`n`r`n")
            return $true
        }
        else {
            $LogBox.AppendText("FEJL i $Description (ExitCode $($proc.ExitCode))`r`n`r`n")
            return $false
        }
    }
    catch {
        $LogBox.AppendText("FEJL i $Description`r`n$($_.Exception.Message)`r`n`r`n")
        $LogBox.ForeColor = 'Red'
        return $false
    }
}


# -------------------------------
# Form
# -------------------------------
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "AD Tiering Setup - NETIP A/S"
$Form.Size = New-Object System.Drawing.Size(800, 600)
$Form.StartPosition = "CenterScreen"
$Form.MaximizeBox = $false

# -------------------------------
# Title
# -------------------------------
$Title = New-Object System.Windows.Forms.Label
$Title.Text = "SCRIPT FOR AD TIERING SETUP"
$Title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$Title.AutoSize = $true
$Title.Location = New-Object System.Drawing.Point(20, 15)
$Form.Controls.Add($Title)

# Checkbox: allow proceeding to next step even if the action returned errors
$ChkAllowProceed = New-Object System.Windows.Forms.CheckBox
$ChkAllowProceed.Text = "Allow proceed on errors"
$ChkAllowProceed.Checked = $true
$ChkAllowProceed.AutoSize = $true
$ChkAllowProceed.Location = New-Object System.Drawing.Point(400, 25)
$ChkAllowProceed.Hide()
$Form.Controls.Add($ChkAllowProceed)

# -------------------------------
# Buttons
# -------------------------------
$ButtonY = 70
$ButtonHeight = 35

# Ordered list of step buttons (for enforcing sequence)
# Reinitialize to ensure previous runs don't leave buttons disabled in the same session
$global:StepButtons = New-Object System.Collections.ArrayList

function Add-Button {
    param ($Text, $Y, $Action)

    $Btn = New-Object System.Windows.Forms.Button
    $Btn.Text = $Text
    $Btn.Size = New-Object System.Drawing.Size(350, $ButtonHeight)
    $Btn.Location = New-Object System.Drawing.Point(20, $Y)
    # Align text to the right
    $Btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    # Determine if this is a step button (text starts with 'Step')
    $isStep = $Text -like 'Step*'

    # Store the action in the button Tag so it's available in the event handler
    $Btn.Tag = $Action

    # If it's a step button, add to global ordered list and disable unless it's the first step
    if ($isStep) {
        $null = $global:StepButtons.Add($Btn)
        if ($global:StepButtons.Count -gt 1) { $Btn.Enabled = $false } else { $Btn.Enabled = $true }
    }

    # Click handler: turn the clicked button green, log the click, then invoke the stored scriptblock
    $Btn.Add_Click({ param($s,$e)
        $s.BackColor = [System.Drawing.Color]::LightGreen
        try { if ($LogBox) { $LogBox.AppendText("BUTTON CLICKED: $($s.Text)`r`n") } } catch { }
        try {
            $sb = $s.Tag
            if ($sb -is [scriptblock]) 
             { $result = $sb.Invoke() } 
            elseif ($sb) 
             { $result = Invoke-Command -ScriptBlock $sb }
            else { $result = $true }
        }
        catch {
            $result = $false
            try { if ($LogBox) { $LogBox.AppendText("ERROR running action: $($_.Exception.Message)`r`n") } } catch { }
        }

        # If this was a step button and action succeeded, or user allowed proceeding on errors, enable next step
        try {
            $proceed = $false
            if ($result) { $proceed = $true }
            else {
                try { if ($ChkAllowProceed -and $ChkAllowProceed.Checked) { $proceed = $true } } catch { }
            }
            if (($s.Text -like 'Step*') -and $proceed) {
                # Find index of the clicked button by matching Text (more reliable across event contexts)
                $idx = -1
                for ($i = 0; $i -lt $global:StepButtons.Count; $i++) {
                    try {
                        if ($global:StepButtons[$i].Text -eq $s.Text) { $idx = $i; break }
                    } catch { }
                }
                if ($idx -ge 0 -and ($idx + 1) -lt $global:StepButtons.Count) {
                    $next = $global:StepButtons[$idx + 1]
                    try { $next.Enabled = $true } catch { }
                    if ($LogBox) { $LogBox.AppendText("ENABLED NEXT STEP: $($next.Text)`r`n") }
                }
            }
        } catch { }
    })

    $Form.Controls.Add($Btn)
}

Add-Button "Step 1 - Create OU tiering structure" $ButtonY {
    Execute-ScriptGUI "1.Create-OUStructure.ps1" "Create OU Structure"
}

Add-Button "Step 2 - Create Security Groups All" ($ButtonY += 45) {
    Execute-ScriptGUI "2.Create-Security-Groups.ps1" "Create Security Groups"
}

Add-Button "Step 3 - Create Admins Groups" ($ButtonY += 45) {
    Execute-ScriptGUI "\HouseKeeping\1.HK.Add-Users-To-Tier-Groups.ps1" "Create Admins Groups"
}

Add-Button "Step 4 - Create GPO and Import Data" ($ButtonY += 45) {
    Execute-ScriptGUI ".\4.0.Update-GPO-Data-Before-Import.PS1" "Update GPO Data Before Import"
    Execute-ScriptGUI ".\4.1.Create-GPO-From-Import.ps1" "Create Group Policies"
}
Add-Button "Step 5 - Create T0 GMSA Account and scheduled Task" ($ButtonY += 45) {
    Execute-ScriptGUI ".\5.0.Create-T0-gMSA.ps1" "Create T0 gMSA Account and scheduled Task"
    Execute-ScriptGUI ".\5.1.Create-T0_Scheduled-Task.ps1" "Create T0 Scheduled Task"
}

Add-Button "Step 9 - Setup OU Delegation Deny" ($ButtonY += 45) {
    Execute-ScriptGUI ".\9.Create-Security-Delegation.ps1" "Setup OU Delegation Deny"
}

Add-Button "View/Edit Tiering master data model" ($ButtonY += 55) {
    notepad "$ToolboxPath\ADT-Master-Data-Model.csv"
}

Add-Button "View/Edit Parameters.ps1" ($ButtonY += 55) {
    notepad "$ToolboxPath\Parameters.ps1"
}

Add-Button "Exit" ($ButtonY += 45) {
    $Form.Close()
}

# -------------------------------
# Log Box
# -------------------------------
$LogBox = New-Object System.Windows.Forms.TextBox
$LogBox.Multiline = $true
$LogBox.ScrollBars = "Vertical"
$LogBox.ReadOnly = $true
$LogBox.Size = New-Object System.Drawing.Size(380, 450)
$LogBox.Location = New-Object System.Drawing.Point(390, 70)
$LogBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$Form.Controls.Add($LogBox)

# -------------------------------
# Start GUI
# -------------------------------
[void]$Form.ShowDialog()