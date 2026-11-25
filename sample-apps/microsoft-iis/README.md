# Microsoft IIS sample app

This sample app installs Microsoft IIS on Windows Server, creates sites whose load produces the metrics and logs the Microsoft IIS integration reads, and collects them with Alloy using the integration's snippets. It uses PowerShell scripts and Make commands, and runs in GitHub Actions on Windows Server 2022 and 2025.

## Prerequisites

The sample app installs IIS on the machine it runs on and changes that machine's configuration. Run it on a virtual machine you can discard.

Before you begin, ensure you have the following:

- A Windows Server 2022 or 2025 VM, with administrator rights
- Git and GNU Make
- Internet access, for downloading Alloy and for Alloy to write to your endpoints
- A Prometheus-compatible endpoint and a Loki endpoint

### Suggested setup

- **VM**: Microsoft's free 180-day evaluation editions of [Windows Server 2025](https://www.microsoft.com/evalcenter/download-windows-server-2025) and [Windows Server 2022](https://www.microsoft.com/evalcenter/download-windows-server-2022) run the sample app. CI runs it with 4 vCPUs and 16 GB of memory.
- **Git and GNU Make**: Windows Server doesn't include them. [Chocolatey](https://chocolatey.org/install) installs both with `choco install git make -y`. Open a new administrator shell afterward, so the shell finds Git.
- **Endpoints**: A free [Grafana Cloud](https://grafana.com/products/cloud/) stack provides both. Install the Microsoft IIS integration in the stack to see the sample app's data on the integration's dashboards.

## Quick Start for new users

To get started with the sample app, follow these steps from an administrator shell:

1. **Clone the repository**:
   ```sh
   git clone https://github.com/grafana/integration-sample-apps.git
   cd integration-sample-apps/sample-apps/microsoft-iis
   ```

2. **Set up default config**:
   Execute `make defaultconfig PROMETHEUS_INSTANCE=<your-prometheus-host:port> LOKI_INSTANCE=<your-loki-host:port>` to create `config/alloy-config.alloy`. For a Grafana Cloud stack, run `make defaultconfig` without the variables, then replace both `url` values with your stack's push URLs and add credentials, as [Default configuration variables](#default-configuration-variables) describes.

3. **Run the sample app**:
   Use `make run` to install IIS, create the sites, install and start Alloy, and generate load for 10 minutes.

4. **Stop and clean up**:
   Use `make stop` to stop Alloy and `make clean` to remove the generated Alloy configuration.

## Make commands

- `make run`: Runs `defaultconfig`, then `scripts/run.ps1`. The script runs the other commands from `install-iis` to `generate-load` in order and stops at the first one that fails.
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
- Credentials: None by default. Add a `basic_auth` block with `username` and `password` inside an `endpoint` block to send them. For Grafana Cloud, the username is the stack's Prometheus or Loki user ID, and the password is a Grafana Cloud access policy token with write access to metrics and logs.

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
- **Check logs**: Review each site's access log under `C:\inetpub\logs\LogFiles\W3SVC<site-id>\`. `web-badid` writes none, because WAS disables its pool before it serves a request.

Each site has its own application pool, so each pool's metrics come from one kind of load:

| Site | Site ID | Port | Application pool | Load |
|---|---|---|---|---|
| `web-main` | 2 | 8081 | `pool-main` | Page requests, 404 and 500 responses, WebSocket connections, WebDAV uploads and writes to a locked file |
| `web-crash` | 3 | 8082 | `pool-crash` | Page requests, and its worker process is killed |
| `web-hang` | 4 | 8083 | `pool-hang` | Page requests, and in the load's first minutes its worker process is suspended until WAS pings fail |
| `web-stuck` | 5 | 8084 | `pool-stuck` | Page requests, and in the load's first minutes its worker process is suspended before the pool recycles |
| `web-badid` | 6 | 8085 | `pool-badid` | Runs as a user that doesn't exist, so WAS disables the pool |

The sample app does not produce data for five of the metrics the integration reads:

- `windows_iis_blocked_async_io_requests_total` and `windows_iis_rejected_async_io_requests_total`: Microsoft documents these counters as always zero since IIS 6.
- `windows_iis_server_metadata_cache_hits_total`: Stays at zero on IIS 10, while `windows_iis_worker_metadata_cache_hits_total` counts the same cache's hits.
- `windows_iis_total_worker_process_startup_failures`: Counts only a worker process that starts but doesn't report to WAS within the pool's startup time limit.
- `windows_iis_worker_threads`: ASP.NET hands each request off IIS's worker threads, so the count stays near zero.
