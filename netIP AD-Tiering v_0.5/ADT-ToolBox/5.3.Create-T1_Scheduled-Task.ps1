<#
.SYNOPSIS
Creates and registers a scheduled task named "Tier1 - House keeping Task" that runs a housekeeping PowerShell script as the gMSA 'T1-housekeeping',
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
# ================================
# IMPORT MODULE
# ================================
Load-Module-ActiveDirectory
CheckLogPath
# ------------------------------
# VARIABLES
# ------------------------------
$Domain        = $env:USERDOMAIN
$gMSA          = "T1-housekeeping"
$gMSAAccount   = "$Domain\$gMSA$"
$TaskName      = "Tier1 - House keeping Task"
$TaskDesc      = "Scheduled task running as gMSA"
$ScriptPath    = "$Global:RootPath \Housekeeping\T1-Housekeeping-Script.ps1"
$TaskFolder    = "\"
$workingDir    = "$Global:RootPath\Housekeeping"
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
    -At (Get-Date "00:00") `
    -RepetitionInterval (New-TimeSpan -Minutes 15) `
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
