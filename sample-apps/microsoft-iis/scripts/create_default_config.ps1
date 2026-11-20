# Create the Alloy configuration from the Microsoft IIS integration's snippets
param(
    [string]$LokiUrl = "http://localhost:3100/loki/api/v1/push",
    [string]$PrometheusUrl = "http://localhost:9009/api/v1/push",
    [string]$LokiUser = "",
    [string]$LokiPass = "",
    [string]$PrometheusUser = "",
    [string]$PrometheusPass = ""
)

$ErrorActionPreference = "Stop"

function Get-BasicAuth([string]$user, [string]$pass) {
    if ($user -and $pass) {
        return @"

    basic_auth {
      username = "$user"
      password = "$pass"
    }
"@
    }
    return ""
}

# These match the sites that setup_sites.ps1 creates.
$sites = @(
    @{ Name = "web-main";      Id = 2 },
    @{ Name = "web-throttled"; Id = 3 },
    @{ Name = "web-crash";     Id = 4 },
    @{ Name = "web-hang";      Id = 5 },
    @{ Name = "web-stuck";     Id = 6 },
    @{ Name = "web-badid";     Id = 7 },
    @{ Name = "web-slowstart"; Id = 8 },
    @{ Name = "web-classic";   Id = 9 }
)

$pathTargets = ($sites | ForEach-Object {
@"
		{
			__address__ = "localhost",
			__path__    = "/inetpub/logs/LogFiles/W3SVC$($_.Id)/u_ex*.log",
			instance    = constants.hostname,
			job         = "integrations/iis",
			site        = "$($_.Name)",
		},
"@
}) -join "`n"

$config = @"
prometheus.remote_write "metrics_service" {
  endpoint {
    url = "$PrometheusUrl"
$(Get-BasicAuth $PrometheusUser $PrometheusPass)
  }
}

loki.write "grafana_cloud_loki" {
  endpoint {
    url = "$LokiUrl"
$(Get-BasicAuth $LokiUser $LokiPass)
  }
}

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

local.file_match "logs_integrations_integrations_iis" {
	path_targets = [
$pathTargets
	]
}

loki.process "logs_integrations_integrations_iis" {
	forward_to = [loki.write.grafana_cloud_loki.receiver]

	stage.match {
		selector            = "{job=\"integrations/iis\"} |~ \"^#\""
		action              = "drop"
		drop_counter_reason = "iis_comment_line"
	}
}

loki.source.file "logs_integrations_integrations_iis" {
	targets    = local.file_match.logs_integrations_integrations_iis.targets
	forward_to = [loki.process.logs_integrations_integrations_iis.receiver]
}
"@

$configDir = Join-Path $PSScriptRoot "..\config"
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
$configPath = Join-Path $configDir "alloy-config.alloy"
$config | Out-File -FilePath $configPath -Encoding UTF8

Write-Host "Created Alloy configuration at: $configPath"
Write-Host "  - Prometheus endpoint: $PrometheusUrl"
Write-Host "  - Loki endpoint: $LokiUrl"
