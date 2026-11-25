# Create the sample app's application pools and sites
param(
    [string]$ContentRoot = "C:\inetpub\sample-app"
)

$ErrorActionPreference = "Stop"
Import-Module WebAdministration

$siteSource = Join-Path $PSScriptRoot "..\site"

# Each site has its own application pool, so each pool's metrics come from one kind of load.
$sites = @(
    @{ Name = "web-main";  Id = 2; Port = 8081; Pool = "pool-main" },
    @{ Name = "web-crash"; Id = 3; Port = 8082; Pool = "pool-crash" },
    @{ Name = "web-hang";  Id = 4; Port = 8083; Pool = "pool-hang" },
    @{ Name = "web-stuck"; Id = 5; Port = 8084; Pool = "pool-stuck" },
    @{ Name = "web-badid"; Id = 6; Port = 8085; Pool = "pool-badid" }
)

foreach ($site in $sites) {
    $path = Join-Path $ContentRoot $site.Name
    Write-Host "Creating site $($site.Name) on port $($site.Port) in $path..."
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Copy-Item -Path (Join-Path $siteSource "*") -Destination $path -Recurse -Force

    if (-not (Test-Path "IIS:\AppPools\$($site.Pool)")) {
        New-WebAppPool -Name $site.Pool | Out-Null
    }
    if (-not (Get-Website -Name $site.Name)) {
        New-Website -Name $site.Name -Id $site.Id -Port $site.Port -PhysicalPath $path -ApplicationPool $site.Pool | Out-Null
    }
}

# The failure pools would otherwise be stopped by rapid-fail protection after five failures.
foreach ($pool in "pool-crash", "pool-hang", "pool-stuck", "pool-badid") {
    Set-ItemProperty "IIS:\AppPools\$pool" -Name failure.rapidFailProtection -Value $false
}

# A suspended pool-hang worker stops answering pings, and WAS counts a ping failure.
Set-ItemProperty "IIS:\AppPools\pool-hang" -Name processModel.pingInterval -Value "00:00:05"
Set-ItemProperty "IIS:\AppPools\pool-hang" -Name processModel.pingResponseTime -Value "00:00:05"

# A suspended pool-stuck worker can't shut down when the pool recycles, and WAS counts a
# shutdown failure. Pinging is off, so a ping failure doesn't end the worker first.
Set-ItemProperty "IIS:\AppPools\pool-stuck" -Name processModel.pingingEnabled -Value $false
Set-ItemProperty "IIS:\AppPools\pool-stuck" -Name processModel.shutdownTimeLimit -Value "00:00:05"

# pool-badid runs as a user that doesn't exist, so WAS disables the pool on its first request.
Set-ItemProperty "IIS:\AppPools\pool-badid" -Name processModel -Value @{
    identityType = 3
    userName     = ".\iis-sample-app-missing-user"
    password     = "not-a-password"
}

# WebDAV on web-main's dav folder lets the load scripts upload files and lock them.
$apphost = "MACHINE/WEBROOT/APPHOST"
Set-WebConfigurationProperty -PSPath $apphost -Location "web-main" -Filter "system.webServer/webdav/authoring" -Name enabled -Value $true
$davRule = Get-WebConfigurationProperty -PSPath $apphost -Location "web-main/dav" -Filter "system.webServer/webdav/authoringRules" -Name Collection |
    Where-Object { $_.users -eq "*" -and $_.path -eq "*" }
if (-not $davRule) {
    Add-WebConfigurationProperty -PSPath $apphost -Location "web-main/dav" -Filter "system.webServer/webdav/authoringRules" -Name "." -Value @{ users = "*"; path = "*"; access = "Read,Write,Source" }
}
Set-WebConfigurationProperty -PSPath $apphost -Location "web-main/dav" -Filter "system.webServer/security/authentication/anonymousAuthentication" -Name enabled -Value $false
Set-WebConfigurationProperty -PSPath $apphost -Location "web-main/dav" -Filter "system.webServer/security/authentication/windowsAuthentication" -Name enabled -Value $true

foreach ($site in $sites) {
    Start-Website -Name $site.Name
}

Get-Website | Format-Table -AutoSize Id, Name, State, PhysicalPath
Write-Host "IIS sites are ready."
exit 0
