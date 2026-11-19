LOKI_INSTANCE := your-loki-instance:3100
PROMETHEUS_INSTANCE := your-prometheus-instance:9009

.PHONY: run stop clean defaultconfig install-iis setup-sites install-alloy configure-alloy start-alloy generate-load

run: install-iis setup-sites defaultconfig install-alloy configure-alloy start-alloy generate-load
	@echo "Microsoft IIS sample app is running. Alloy should be collecting metrics and logs."

stop:
	@powershell -ExecutionPolicy Bypass -File "scripts/stop_alloy.ps1"

clean:
	@if exist "config\alloy-config.alloy" del "config\alloy-config.alloy"

defaultconfig:
	@powershell -ExecutionPolicy Bypass -File "scripts/create_default_config.ps1" -LokiUrl "http://$(LOKI_INSTANCE)/loki/api/v1/push" -PrometheusUrl "http://$(PROMETHEUS_INSTANCE)/api/v1/push"

install-iis:
	@powershell -ExecutionPolicy Bypass -File "scripts/install_iis.ps1"

setup-sites:
	@powershell -ExecutionPolicy Bypass -File "scripts/setup_sites.ps1"

install-alloy:
	@powershell -ExecutionPolicy Bypass -File "scripts/install_alloy.ps1"

configure-alloy:
	@powershell -ExecutionPolicy Bypass -File "scripts/configure_alloy.ps1"

start-alloy:
	@powershell -ExecutionPolicy Bypass -File "scripts/start_alloy.ps1"

generate-load:
	@powershell -ExecutionPolicy Bypass -File "scripts/generate_load.ps1"
