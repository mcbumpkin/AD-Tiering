<#
.SYNOPSIS
Creates and registers a scheduled task named "Tier0 - House keeping Task" that runs a housekeeping PowerShell script as the gMSA 'T0-housekeeping',
configures trigger, principal, and settings, and starts the task for a test run.
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
# ------------------------------
# VARIABLES
# ------------------------------
$Domain        = $env:USERDOMAIN
$gMSA          = "T0-housekeeping"
$gMSAAccount   = "$Domain\$gMSA$"
$TaskName      = "Tier0 - House keeping Task"
$TaskDesc      = "Scheduled task running as gMSA"
$ScriptPath    = "$Global:RootPath\Housekeeping\0.HK.Execute-All-HouseKeepings-Script.ps1"
$TaskFolder    = "\"
$workingDir    = "$Global:RootPath\Housekeeping"

# ==============================
# CHECK IF TASK ALREADY EXISTS
# If the scheduled task already exists at the specified folder/name, log and exit
# ==============================
try {
    $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue
}
catch {
    $existingTask = $null
}
if ($existingTask) {
    Write-Log "Scheduled task '$TaskName' already exists at folder '$TaskFolder'. Skipping creation."
    Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Confirm:$false 
    Write-Log "Existing scheduled task '$TaskName' unregistered successfully. Proceeding to create a new one." 
}

# ==============================
# TASK ACTION
# ==============================
$Action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" -WorkingDirectory $workingDir
if ($Action) {
    Write-Log "Scheduled task action created successfully"
}
else {
    Write-Log "Failed to create scheduled task action"
}
# ------------------------------
# TASK TRIGGER
# ------------------------------
$trigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date "09:45") `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration (New-TimeSpan -Hours 23 -Minutes 45) 
     
if ($Trigger) {
    Write-Log "Scheduled task trigger created successfully"
}
else {
    Write-Log "Failed to create scheduled task trigger"
}
# ------------------------------
# TASK PRINCIPAL (gMSA)
# ------------------------------
$Principal = New-ScheduledTaskPrincipal `
    -UserId $gMSAAccount `
    -LogonType Password `
    -RunLevel Highest
if ($Principal) {
    Write-Log "Scheduled task principal created successfully"
}
else {
    Write-Log "Failed to create scheduled task principal"
}
# ------------------------------
# TASK SETTINGS
# ------------------------------

$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 14)
if ($Settings) {
    Write-Log "Scheduled task settings created successfully"
}
else {
    Write-Log "Failed to create scheduled task settings"
}

# ------------------------------
# REGISTER TASK
# ------------------------------
$Task = Register-ScheduledTask `
    -TaskName $TaskName `
    -TaskPath $TaskFolder `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Description $TaskDesc
if ($Task) {
    Write-Log "Scheduled task '$TaskName' registered successfully"
}
else {
    Write-Log "Failed to register scheduled task '$TaskName'"
}
Write-Host "Scheduled task '$TaskName' created successfully" -ForegroundColor Green
# ------------------------------
# OPTIONAL: TEST RUN
# ------------------------------
Start-ScheduledTask -TaskName $TaskName
if ($?) {
    Write-Log "Scheduled task '$TaskName' started successfully for test run"
}
else {
    Write-Log "Failed to start scheduled task '$TaskName' for test run"
}
Write-Host "Task started manually for test run" -ForegroundColor Cyan
