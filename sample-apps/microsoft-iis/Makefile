LOKI_INSTANCE := your-loki-instance:3100
PROMETHEUS_INSTANCE := your-prometheus-instance:9009
CONFIG_FILE := config/alloy-config.alloy
# Chocolatey's make is 32-bit, and 32-bit PowerShell can't load the IIS cmdlets.
# Sysnative exists only for 32-bit processes and points them at 64-bit PowerShell.
POWERSHELL := $(if $(wildcard $(SystemRoot)/Sysnative/WindowsPowerShell/v1.0/powershell.exe),$(SystemRoot)/Sysnative/WindowsPowerShell/v1.0/powershell.exe,powershell)

.PHONY: run stop clean defaultconfig install-iis setup-sites install-alloy configure-alloy start-alloy generate-load

run: install-iis setup-sites defaultconfig install-alloy configure-alloy start-alloy generate-load
	@echo "Microsoft IIS sample app is running. Alloy should be collecting metrics and logs."

stop:
	@"$(POWERSHELL)" -ExecutionPolicy Bypass -File "scripts/stop_alloy.ps1"

clean:
	@"$(POWERSHELL)" -NoProfile -Command "Remove-Item -Path '$(CONFIG_FILE)' -ErrorAction SilentlyContinue"

defaultconfig: $(CONFIG_FILE)

$(CONFIG_FILE):
	@"$(POWERSHELL)" -ExecutionPolicy Bypass -File "scripts/create_default_config.ps1" -LokiUrl "http://$(LOKI_INSTANCE)/loki/api/v1/push" -PrometheusUrl "http://$(PROMETHEUS_INSTANCE)/api/v1/push"

install-iis:
	@"$(POWERSHELL)" -ExecutionPolicy Bypass -File "scripts/install_iis.ps1"

setup-sites:
	@"$(POWERSHELL)" -ExecutionPolicy Bypass -File "scripts/setup_sites.ps1"

install-alloy:
	@"$(POWERSHELL)" -ExecutionPolicy Bypass -File "scripts/install_alloy.ps1"

configure-alloy:
	@"$(POWERSHELL)" -ExecutionPolicy Bypass -File "scripts/configure_alloy.ps1"

start-alloy:
	@"$(POWERSHELL)" -ExecutionPolicy Bypass -File "scripts/start_alloy.ps1"

generate-load:
	@"$(POWERSHELL)" -ExecutionPolicy Bypass -File "scripts/generate_load.ps1"
