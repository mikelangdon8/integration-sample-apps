# Microsoft IIS sample app

This sample app installs Microsoft IIS on Windows Server, creates sites whose load produces the metrics and logs the Microsoft IIS integration reads, and collects them with Alloy using the integration's snippets. It uses PowerShell scripts and Make commands, and runs in GitHub Actions on Windows Server 2022 and 2025.

## Prerequisites

Before you begin, ensure you have the following:

- Windows Server 2022 or 2025, with administrator rights
- PowerShell 5.1 or later
- GNU Make, for the Make commands
- Internet connectivity for downloading Alloy
- A Prometheus-compatible endpoint and a Loki endpoint for Alloy to write to

## Quick Start for new users

To get started with the sample app, follow these steps from an administrator shell:

1. **Clone the repository**:
   ```sh
   git clone https://github.com/grafana/integration-sample-apps.git
   cd integration-sample-apps/sample-apps/microsoft-iis
   ```

2. **Set up default config**:
   Execute `make defaultconfig PROMETHEUS_INSTANCE=<your-prometheus-host:port> LOKI_INSTANCE=<your-loki-host:port>` to create `config/alloy-config.alloy`. Modify it to add credentials for your endpoints.

3. **Run the sample app**:
   Use `make run` to install IIS, create the sites, install and start Alloy, and generate load for 10 minutes.

4. **Stop and clean up**:
   Use `make stop` to stop Alloy and `make clean` to remove the generated Alloy configuration.

## Make commands

- `make run`: Runs every command below in order, from `install-iis` to `generate-load`.
- `make install-iis`: Installs IIS with ASP.NET 4.8, WebSocket, WebDAV and Windows authentication support.
- `make setup-sites`: Creates the sites and their application pools.
- `make defaultconfig`: Creates `config/alloy-config.alloy` from the integration's snippets, if it does not already exist. `make run` creates it when missing.
- `make install-alloy`: Installs the latest Alloy as a Windows service.
- `make configure-alloy`: Copies `config/alloy-config.alloy` to the Alloy service.
- `make start-alloy`: Starts the Alloy service.
- `make generate-load`: Generates load for 10 minutes.
- `make stop`: Stops the Alloy service.
- `make clean`: Removes `config/alloy-config.alloy`.

## Make variables

Set these on the command line, e.g. `make defaultconfig PROMETHEUS_INSTANCE=mimir.example.com:9009`. They apply only when `make defaultconfig` creates the configuration file.

- `PROMETHEUS_INSTANCE`: `host:port` of the Prometheus-compatible endpoint. Alloy writes to `http://<host:port>/api/v1/push`.
- `LOKI_INSTANCE`: `host:port` of the Loki endpoint. Alloy writes to `http://<host:port>/loki/api/v1/push`.

## Default configuration variables

`config/alloy-config.alloy` holds the endpoints Alloy writes to:

- `prometheus.remote_write "metrics_service"`: The `url` of the Prometheus-compatible push endpoint.
- `loki.write "grafana_cloud_loki"`: The `url` of the Loki push endpoint.
- Credentials: None by default. Add a `basic_auth` block with `username` and `password` inside an `endpoint` block to send them.

## Validating services

### Alloy
- **Check service status**: Confirm that Alloy is running.
  ```powershell
  Get-Service -Name Alloy
  ```
- **Review configuration**: Verify the configuration in `C:\Program Files\GrafanaLabs\Alloy\config.alloy` is correct.
- **Check components**: Open `http://localhost:12345` to see each component's health.

### Microsoft IIS
- **Check sites**: Confirm that the sites are started.
  ```powershell
  Get-Website
  ```
- **Check logs**: Review each site's access log under `C:\inetpub\logs\LogFiles\W3SVC<site-id>\`.

Each site has its own application pool, so each pool's metrics come from one kind of load:

| Site | Site ID | Port | Application pool | Load |
|---|---|---|---|---|
| `web-main` | 2 | 8081 | `pool-main` | Page requests, 404 and 500 responses, WebSocket connections, WebDAV uploads and writes to a locked file |
| `web-crash` | 3 | 8082 | `pool-crash` | Page requests, and its worker process is killed |
| `web-hang` | 4 | 8083 | `pool-hang` | Page requests, and its worker process is suspended until WAS pings fail |
| `web-stuck` | 5 | 8084 | `pool-stuck` | Page requests, and its worker process is suspended before the pool recycles |
| `web-badid` | 6 | 8085 | `pool-badid` | Runs as a user that doesn't exist, so WAS disables the pool |

The sample app does not produce data for five of the metrics the integration reads:

- `windows_iis_blocked_async_io_requests_total` and `windows_iis_rejected_async_io_requests_total`: Microsoft documents these counters as always zero since IIS 6.
- `windows_iis_server_metadata_cache_hits_total`: Stays at zero on IIS 10, while `windows_iis_worker_metadata_cache_hits_total` counts the same cache's hits.
- `windows_iis_total_worker_process_startup_failures`: Counts only a worker process that starts but doesn't report to WAS within the pool's startup time limit.
- `windows_iis_worker_threads`: ASP.NET hands each request off IIS's worker threads, so the count stays near zero.
