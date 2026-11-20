# Microsoft IIS sample app

This sample app installs Microsoft IIS on Windows Server, creates sites that produce the metrics and logs the Microsoft IIS integration reads, and collects them with Alloy using the integration's snippets. It runs in GitHub Actions on Windows Server 2022 and 2025 runners, with Mimir and Loki in Docker inside WSL.

## Prerequisites

- Windows Server 2022 or 2025, the versions the sample app's CI tests, with administrator rights
- PowerShell 5.1 or later
- Internet access to download Alloy
- A Prometheus-compatible endpoint and a Loki endpoint for Alloy to write to

## Quick start

1. Clone the repository and open the sample app's directory:

   ```sh
   git clone https://github.com/grafana/integration-sample-apps.git
   cd integration-sample-apps/sample-apps/microsoft-iis
   ```

2. Set `PROMETHEUS_INSTANCE` and `LOKI_INSTANCE` in the `Makefile` to your endpoints.

3. Run `make run` from an administrator shell. It installs IIS, creates the sites, installs and starts Alloy, and generates load for 10 minutes.

4. Run `make stop` to stop Alloy, and `make clean` to remove the generated Alloy configuration.

## Make commands

- `make run`: runs every step below in order.
- `make install-iis`: installs IIS with ASP.NET 4.8, WebSocket, WebDAV and Windows authentication support.
- `make setup-sites`: creates the application pools and sites.
- `make defaultconfig`: writes `config/alloy-config.alloy` from the integration's snippets.
- `make install-alloy`: installs the latest Alloy as a Windows service.
- `make configure-alloy`: copies `config/alloy-config.alloy` to the Alloy service.
- `make start-alloy`: starts the Alloy service.
- `make generate-load`: generates load for 10 minutes.
- `make stop`: stops the Alloy service.
- `make clean`: removes `config/alloy-config.alloy`.

## Sites

Each site has its own application pool, so each pool's metrics come from one kind of load.

| Site | Port | Application pool | Load |
|---|---|---|---|
| `web-main` | 8081 | `pool-main` | Static and ASP.NET pages, 404 and 500 responses, slow requests, WebSocket connections, WebDAV uploads and writes to a locked file |
| `web-throttled` | 8082 | `pool-throttled` | Downloads that exceed the site's 64 KB/s bandwidth limit |
| `web-crash` | 8083 | `pool-crash` | Its worker process is killed |
| `web-hang` | 8084 | `pool-hang` | Its worker process is suspended until WAS pings fail |
| `web-stuck` | 8085 | `pool-stuck` | Its worker process is suspended, then the pool recycles |
| `web-badid` | 8086 | `pool-badid` | The pool runs as a user that doesn't exist, so its worker processes fail to start |

Every site except `web-throttled` also gets `web-main`'s page requests and 404 and 500 responses.

## Validating the sample app

- Check that Alloy is running with `Get-Service -Name Alloy`.
- Open `http://localhost:12345` to see Alloy's components and their health.
- Check that IIS writes access logs under `C:\inetpub\logs\LogFiles\W3SVC<site-id>\`.
