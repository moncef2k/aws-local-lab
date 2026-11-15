# AWS local lab - entry points. Run `make help` to list the targets.
#
# Recipes always run in Git Bash, so they behave the same whether `make` is started from
# PowerShell, cmd or Git Bash. Adjust the path if Git is installed elsewhere. (GNU Make 4.4.1
# from winget accepts the space in "Program Files"; tested from PowerShell and Git Bash.)
ifeq ($(OS),Windows_NT)
SHELL := C:/Program Files/Git/bin/bash.exe
else
SHELL := /bin/bash
endif
.SHELLFLAGS := -eu -o pipefail -c

COMPOSE := docker compose

.DEFAULT_GOAL := help
.PHONY: help up down logs clean test load-test

help: ## List the available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

up: ## Build and start the lab in the background
	@if [ -z "$$($(COMPOSE) config --services)" ]; then \
	  echo "no services defined yet in docker-compose.yml - nothing to start"; \
	else \
	  $(COMPOSE) up -d --build --remove-orphans; \
	fi

down: ## Stop the lab (data volumes are kept)
	$(COMPOSE) down --remove-orphans

logs: ## Follow the logs of all services
	$(COMPOSE) logs -f --tail=100

clean: ## Stop the lab AND delete its data volumes (asks first)
	@read -r -p "This deletes ALL lab data (databases, buckets). Type 'yes' to continue: " answer; \
	  [ "$$answer" = "yes" ] || { echo "aborted"; exit 1; }
	$(COMPOSE) down -v --remove-orphans

test: ## Run all tests in tests/ (not implemented yet, see PLAN.md step 7)
	@echo "make test: not implemented yet" >&2; exit 1

load-test: ## Run the k6 load test (not implemented yet, see PLAN.md step 37)
	@echo "make load-test: not implemented yet" >&2; exit 1
