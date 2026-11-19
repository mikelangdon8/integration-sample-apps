# Checks whether a GitHub-hosted Windows runner can host IIS and whether Alloy's
# windows exporter collects the Microsoft IIS integration's metrics there.

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$out = Join-Path $env:GITHUB_WORKSPACE "iis-runner-test-output"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$summary = Join-Path $out "summary.md"

function Add-Summary([string]$text) {
    Add-Content -Path $summary -Value $text
    if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $text }
    Write-Host $text
}

# The integration's metric_names in grafana/cloud-onboarding, without `up`, which comes from
# the scrape rather than the exporter.
$expected = @(
    "windows_iis_blocked_async_io_requests_total",
    "windows_iis_connection_attempts_all_instances_total",
    "windows_iis_current_application_pool_state",
    "windows_iis_current_connections",
    "windows_iis_current_worker_processes",
    "windows_iis_files_received_total",
    "windows_iis_files_sent_total",
    "windows_iis_locked_errors_total",
    "windows_iis_not_found_errors_total",
    "windows_iis_received_bytes_total",
    "windows_iis_rejected_async_io_requests_total",
    "windows_iis_requests_total",
    "windows_iis_sent_bytes_total",
    "windows_iis_server_file_cache_hits_total",
    "windows_iis_server_file_cache_queries_total",
    "windows_iis_server_metadata_cache_hits_total",
    "windows_iis_server_metadata_cache_queries_total",
    "windows_iis_server_output_cache_hits_total",
    "windows_iis_server_output_cache_queries_total",
    "windows_iis_server_uri_cache_hits_total",
    "windows_iis_server_uri_cache_queries_total",
    "windows_iis_total_worker_process_failures",
    "windows_iis_total_worker_process_ping_failures",
    "windows_iis_total_worker_process_shutdown_failures",
    "windows_iis_total_worker_process_startup_failures",
    "windows_iis_worker_file_cache_hits_total",
    "windows_iis_worker_file_cache_queries_total",
    "windows_iis_worker_max_threads",
    "windows_iis_worker_metadata_cache_hits_total",
    "windows_iis_worker_metadata_cache_queries_total",
    "windows_iis_worker_output_cache_hits_total",
    "windows_iis_worker_output_queries_total",
    "windows_iis_worker_request_errors_total",
    "windows_iis_worker_requests_total",
    "windows_iis_worker_threads",
    "windows_iis_worker_uri_cache_hits_total",
    "windows_iis_worker_uri_cache_queries_total",
    "windows_iis_worker_websocket_connection_accepted_total",
    "windows_iis_worker_websocket_connection_attempts_total"
)

function Send-Requests([int]$count) {
    $codes = @{}
    foreach ($port in 8081, 8082) {
        for ($i = 1; $i -le $count; $i++) {
            foreach ($path in "/", "/missing-$i.html", "/broken/") {
                try {
                    $code = [int](Invoke-WebRequest -Uri "http://localhost:$port$path" -UseBasicParsing -TimeoutSec 10).StatusCode
                } catch [System.Net.WebException] {
                    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } else { $code = 0 }
                }
                $key = "$port $code"
                if ($codes.ContainsKey($key)) { $codes[$key]++ } else { $codes[$key] = 1 }
            }
        }
    }
    return $codes
}

Add-Summary "# IIS runner test"
$os = Get-CimInstance Win32_OperatingSystem
Add-Summary "- OS: $($os.Caption), version $($os.Version)"

# 1. Install IIS with WebSocket support.
$install = Install-WindowsFeature -Name Web-Server, Web-WebSockets -IncludeManagementTools
$install | Format-List | Out-File (Join-Path $out "install-windowsfeature.txt")
Add-Summary "- Install-WindowsFeature: success $($install.Success), restart needed $($install.RestartNeeded), exit code $($install.ExitCode)"
if (-not $install.Success) { throw "IIS did not install." }
$iisVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp").VersionString
Add-Summary "- IIS: $iisVersion"
Get-WindowsFeature -Name Web-* | Where-Object Installed | Select-Object Name, DisplayName |
    Out-File (Join-Path $out "iis-features.txt")

# 2. Two application pools and two sites. /broken/ has an invalid web.config, so it returns 500.
Import-Module WebAdministration
foreach ($n in "a", "b") {
    $dir = "C:\iis-test\site-$n"
    New-Item -ItemType Directory -Path "$dir\broken" -Force | Out-Null
    Set-Content -Path "$dir\index.html" -Value "<html><body>site $n</body></html>"
    Set-Content -Path "$dir\broken\web.config" -Value "<configuration><system.webServer><notASection /></system.webServer></configuration>"
    New-WebAppPool -Name "pool-$n" | Out-Null
    $port = if ($n -eq "a") { 8081 } else { 8082 }
    New-Website -Name "site-$n" -Port $port -PhysicalPath $dir -ApplicationPool "pool-$n" | Out-Null
    Start-Website -Name "site-$n"
}
Get-Website | Select-Object Id, Name, State, PhysicalPath | Format-Table -AutoSize | Out-String | Write-Host
$codes = Send-Requests 100
Add-Summary "- Responses before Alloy started (port, status: count):"
$codes.GetEnumerator() | Sort-Object Name | ForEach-Object { Add-Summary "  - $($_.Name): $($_.Value)" }

# 3. Install Alloy and run the integration's metrics snippet from grafana/cloud-onboarding.
# The remote_write endpoint has no receiver: the test reads the exporter's endpoint instead.
& "$env:GITHUB_WORKSPACE\sample-apps\windows\scripts\install_alloy.ps1"
$alloyDir = "C:\Program Files\GrafanaLabs\Alloy"
$alloyExe = Get-ChildItem -Path $alloyDir -Filter "alloy*.exe" | Where-Object Name -notmatch "uninstall" | Select-Object -First 1
$alloyVersion = (& $alloyExe.FullName --version 2>&1 | Out-String).Trim()
Add-Summary "- Alloy: $alloyVersion"

$config = @'
prometheus.exporter.windows "integrations_windows_exporter" {
	enabled_collectors = ["iis"]

	dfsr {
		sources_enabled = [""]
	}

	exchange {
		enabled_list = [""]
	}

	mssql {
		enabled_classes = [""]
	}
}

discovery.relabel "integrations_windows_exporter" {
	targets = prometheus.exporter.windows.integrations_windows_exporter.targets

	rule {
		target_label = "job"
		replacement  = "integrations/iis"
	}

	rule {
		target_label = "instance"
		replacement  = constants.hostname
	}
}

prometheus.scrape "integrations_windows_exporter" {
	targets    = discovery.relabel.integrations_windows_exporter.output
	forward_to = [prometheus.remote_write.metrics_service.receiver]
	job_name   = "integrations/windows_exporter"
}

prometheus.remote_write "metrics_service" {
	endpoint {
		url = "http://localhost:9009/api/v1/push"
	}
}
'@
Set-Content -Path (Join-Path $alloyDir "config.alloy") -Value $config
Copy-Item (Join-Path $alloyDir "config.alloy") (Join-Path $out "config.alloy")
for ($i = 1; $i -le 12 -and -not (Get-Service -Name Alloy -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 5 }
Restart-Service -Name Alloy
Start-Sleep -Seconds 15
Add-Summary "- Alloy service: $((Get-Service -Name Alloy).Status)"

# Keep both worker processes busy while the exporter is read.
Send-Requests 50 | Out-Null

# 4. Read the exporter's metrics and compare them with the integration's list.
$url = "http://localhost:12345/api/v0/component/prometheus.exporter.windows.integrations_windows_exporter/metrics"
$body = $null
for ($i = 1; $i -le 6 -and -not $body; $i++) {
    try { $body = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30).Content }
    catch { Write-Host "Exporter endpoint not ready (attempt $i): $_"; Start-Sleep -Seconds 10 }
}
if (-not $body) {
    try {
        Get-WinEvent -ProviderName Alloy -MaxEvents 100 | Format-List TimeCreated, Message |
            Out-File (Join-Path $out "alloy-events.txt")
    } catch { Write-Host "No Alloy events: $_" }
    throw "The exporter endpoint never answered."
}
Set-Content -Path (Join-Path $out "exporter-metrics.txt") -Value $body

$names = $body -split "`n" | Where-Object { $_ -and -not $_.StartsWith("#") } |
    ForEach-Object { ($_ -split "[{ ]")[0] } | Sort-Object -Unique
$present = $expected | Where-Object { $names -contains $_ }
$missing = $expected | Where-Object { $names -notcontains $_ }
$extra = $names | Where-Object { $_ -like "windows_iis_*" -and $expected -notcontains $_ }
Add-Summary "- Integration metrics present: $($present.Count) of $($expected.Count)"
Add-Summary "- Missing:"
$missing | ForEach-Object { Add-Summary "  - $_" }
Add-Summary "- IIS metrics the integration doesn't use:"
$extra | ForEach-Object { Add-Summary "  - $_" }
$body -split "`n" | Where-Object { $_ -match "^windows_exporter_collector_success|^windows_iis_current_application_pool_state" } |
    ForEach-Object { Add-Summary "  - ``$_``" }

# 5. Flush IIS's log buffer and list the W3C log files.
netsh http flush logbuffer | Out-Null
Start-Sleep -Seconds 5
$logs = Get-ChildItem -Path "C:\inetpub\logs\LogFiles" -Recurse -File -ErrorAction SilentlyContinue
Add-Summary "- W3C log files:"
$logs | ForEach-Object { Add-Summary "  - $($_.FullName) ($($_.Length) bytes)" }
$logs | Select-Object -First 1 | ForEach-Object { Get-Content $_.FullName -TotalCount 20 | Out-File (Join-Path $out "w3c-log-sample.txt") }

if ($present.Count -eq 0) { throw "Alloy collected none of the integration's IIS metrics." }
