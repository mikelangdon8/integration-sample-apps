# Run the sample app: install IIS, create the sites, install and start Alloy, and generate load
param(
    [switch]$LoadInBackground,
    [int]$LoadDurationSeconds = 600
)

$ErrorActionPreference = "Stop"

# The step scripts read config\alloy-config.alloy and other files relative to the sample app's folder.
Set-Location (Join-Path $PSScriptRoot "..")

if (-not (Test-Path "config\alloy-config.alloy")) {
    $Host.UI.WriteErrorLine("config\alloy-config.alloy is missing. Create it with 'make defaultconfig' or scripts\create_default_config.ps1, then run this again.")
    exit 1
}

# Each step runs in its own process, so a step's exit code reaches this script even when the step ends without calling exit.
$powershell = Join-Path $PSHOME "powershell.exe"

foreach ($step in "install_iis.ps1", "setup_sites.ps1", "install_alloy.ps1", "configure_alloy.ps1", "start_alloy.ps1") {
    & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $step)
    if ($LASTEXITCODE -ne 0) {
        $code = $LASTEXITCODE
        $Host.UI.WriteErrorLine("$step failed with exit code $code.")
        exit $code
    }
}

$load = Join-Path $PSScriptRoot "generate_load.ps1"
if ($LoadInBackground) {
    Start-Process -FilePath $powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$load`" -DurationSeconds $LoadDurationSeconds" -WindowStyle Hidden
    Write-Host "Load generation started in the background for $LoadDurationSeconds seconds."
    exit 0
}

& $powershell -NoProfile -ExecutionPolicy Bypass -File $load -DurationSeconds $LoadDurationSeconds
exit $LASTEXITCODE
