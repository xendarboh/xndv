SHELL := /bin/bash
export BUILDKIT_PROGRESS := plain

# https://unix.stackexchange.com/questions/235223/makefile-include-env-file
include .env
export
MAKEFILE_LIST = Makefile
COMPOSE_BUILD := docker compose --profile build
COMPOSE_MODELS := docker compose --profile models
COMPOSE_GATEWAY := docker compose --profile gateway

.PHONY: help build-tty rebuild-tty install-x11docker fetch-nvidia-driver build retag rebuild refresh models-up models-down models-logs models-status gateway-up gateway-down gateway-logs gateway-status gateway-login gateway-quota

# https://blog.testdouble.com/posts/2017-04-17-makefile-usability-tips/#step-3-parse-annotations
help: ## print this help message with some nifty mojo
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

build-tty: ## build tty-only docker image
	time $(COMPOSE_BUILD) build xen-dev

build-tty-sys: build-tty ## build tty+sysbox docker image
	time $(COMPOSE_BUILD) build xen-sys

rebuild-tty: ## (re)build tty-only docker image with --no-cache --pull
	time $(COMPOSE_BUILD) build --no-cache --pull xen-dev

rebuild-tty-sys: build-tty ## (re)build tty+sysbox docker image with --no-cache --pull
	time $(COMPOSE_BUILD) build xen-sys --no-cache --pull xen-dev

install-x11docker: ## install or update x11docker and pull xserver image
	curl -fsSL https://raw.githubusercontent.com/mviereck/x11docker/master/x11docker | sudo bash -s -- --update
	docker pull x11docker/xserver

fetch-nvidia-driver: ## fetch versioned NVIDIA driver for x11docker
	@V=$$(grep -oP 'Kernel Module\s+\K[0-9.]+' /proc/driver/nvidia/version | head -1); \
	if [ -z "$$V" ]; then echo "Error: No NVIDIA driver detected" >&2; exit 1; fi; \
	echo "Detected: $$V"; \
	DL="$$HOME/.local/share/x11docker"; \
	mkdir -p "$$DL" && \
	curl -fL --progress-bar "https://http.download.nvidia.com/XFree86/Linux-x86_64/$$V/NVIDIA-Linux-x86_64-$$V.run" -o "$$DL/NVIDIA-Linux-x86_64-$$V.run"

build: ## build docker images
	time $(COMPOSE_BUILD) build xen-x11
	time $(COMPOSE_BUILD) build --build-arg IMAGE_BASE=xen/x11 xen-dev
	time $(COMPOSE_BUILD) build xen-sys

retag: ## tag docker images: latest --> prev
	-docker rmi xen/sys:prev xen/dev:prev xen/x11:prev
	-docker image tag xen/dev:latest xen/dev:prev
	-docker image tag xen/sys:latest xen/sys:prev
	-docker image tag xen/x11:latest xen/x11:prev

rebuild: ## rebuild docker images (no cache, pull latest base images)
	time docker pull ${IMAGE_BASE}
	time $(COMPOSE_BUILD) build --no-cache --pull xen-x11
	time $(COMPOSE_BUILD) build --no-cache --build-arg IMAGE_BASE=xen/x11 xen-dev
	time $(COMPOSE_BUILD) build --no-cache xen-sys

refresh: ## pull latest peripheral images and rebuild external-source services
	$(COMPOSE_MODELS) pull
	$(COMPOSE_GATEWAY) pull
	$(COMPOSE_GATEWAY) build --no-cache gateway-quota
	docker model uninstall-runner --images # uninstall first to force a fresher backend image
	docker model install-runner --backend $(MODELS_BACKEND) --gpu $(MODELS_GPU)

models-up: ## start local model runner + Open WebUI
	$(COMPOSE_MODELS) up -d

models-down: ## stop local model services
	$(COMPOSE_MODELS) down

models-logs: ## show local model service logs
	$(COMPOSE_MODELS) logs -f

models-status: ## show local model service status
	$(COMPOSE_MODELS) ps

models-thinking-disable: ## configure model to disable thinking
	docker model configure $(MODELS_BACKEND) -- \
		--chat-template-kwargs '{"enable_thinking":false}' \
		--reasoning-budget 0

models-thinking-enable: ## configure model to enable thinking
	docker model configure $(MODELS_BACKEND) -- \
		--chat-template-kwargs '{"enable_thinking":true}' \
		--reasoning-budget -1

gateway-up: ## start LLM gateway (LiteLLM proxy)
	$(COMPOSE_GATEWAY) up -d

gateway-down: ## stop LLM gateway services
	$(COMPOSE_GATEWAY) down

gateway-logs: ## show LLM gateway service logs
	$(COMPOSE_GATEWAY) logs -f

gateway-status: ## show LLM gateway service status
	$(COMPOSE_GATEWAY) ps

gateway-login: ## login to OAuth provider for gateway (PROVIDER=<provider>)
	@test -n "$(PROVIDER)" || { \
		echo "[xndv] Usage: make gateway-login PROVIDER=<provider>"; \
		echo "[xndv] See the following --<provider>-login options for supported providers"; \
		echo ""; \
		$(COMPOSE_GATEWAY) exec gateway-oauth ./CLIProxyAPI --help; \
		exit 1; \
	}
	$(COMPOSE_GATEWAY) exec gateway-oauth ./CLIProxyAPI --$(PROVIDER)-login -no-browser

gateway-login-google: ## login to OAuth provider for gateway (PROVIDER=google)
	$(COMPOSE_GATEWAY) exec gateway-oauth ./CLIProxyAPI -login -no-browser

gateway-quota: ## show quota/usage details from OAuth providers via CLIProxyAPI
	$(COMPOSE_GATEWAY) run --rm gateway-quota
