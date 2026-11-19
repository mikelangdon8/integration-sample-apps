# Install Microsoft IIS with the role services the sample app's sites use
$ErrorActionPreference = "Stop"

$features = @(
    "Web-Server",
    "Web-Asp-Net45",
    "Web-WebSockets",
    "Web-DAV-Publishing",
    "Web-Windows-Auth",
    "Web-Mgmt-Console"
)

Write-Host "Installing IIS features: $($features -join ', ')..."
$result = Install-WindowsFeature -Name $features
if (-not $result.Success) {
    Write-Error "IIS installation failed with exit code: $($result.ExitCode)"
    exit 1
}
if ($result.RestartNeeded -eq "Yes") {
    Write-Warning "Windows reports that a restart is needed to finish the IIS installation."
}

$version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp").VersionString
Write-Host "Installed IIS $version."

# The integration's pre-install instructions start performance counters from Server Manager.
# This is the data collector set that the Server Manager command starts.
$collectorSet = "Server Manager Performance Monitor"
logman query "$collectorSet" > $null 2>&1
if ($LASTEXITCODE -eq 0) {
    logman start "$collectorSet" > $null 2>&1
    Write-Host "Started the '$collectorSet' data collector set."
} else {
    Write-Warning "The '$collectorSet' data collector set does not exist on this host."
}

exit 0
