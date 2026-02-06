# ==============================================================================
# ANTIGRAVITY MANAGER - MAKEFILE (LINUX)
# ==============================================================================

SHELL := /bin/sh

.DEFAULT_GOAL := help

.PHONY: help setup compose-config ci-validate up down logs logs-rclone logs-antigravity \
	restart restart-rclone restart-antigravity ps clean backup restore \
	shell-rclone shell-antigravity check-ready sync-manual config-show test-s3

COMPOSE ?= docker compose
ENV_FILE ?= .env
BACKUP_DIR ?= backups
ACTIVE_ENV_FILE := $(if $(wildcard $(ENV_FILE)),$(ENV_FILE),.env.example)
DC := $(COMPOSE) --env-file $(ACTIVE_ENV_FILE)

BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help: ## Show this help message
	@printf "$(BLUE)===================================================================\n$(NC)"
	@printf "$(GREEN)Antigravity Manager - Docker Compose Commands (Linux)\n$(NC)"
	@printf "$(BLUE)===================================================================\n$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "$(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'

setup: ## Initial setup - copy .env.example to .env
	@if [ ! -f .env ]; then \
		cp .env.example .env && \
		printf "$(GREEN)Created .env file from .env.example$(NC)\n" && \
		printf "$(YELLOW)Please edit .env and fill in S3 credentials$(NC)\n"; \
	else \
		printf "$(YELLOW).env already exists, skipping$(NC)\n"; \
	fi
	@chmod +x scripts/*.sh
	@printf "$(GREEN)Scripts are executable$(NC)\n"

compose-config: ## Validate docker-compose with active env file
	@$(DC) config >/dev/null
	@printf "$(GREEN)Compose config is valid (env: $(ACTIVE_ENV_FILE))$(NC)\n"

ci-validate: ## Run Linux CI checks (GitHub Actions/Azure Pipelines)
	@sh scripts/ci-validate.sh

up: ## Start containers in background
	@$(DC) up -d
	@printf "$(GREEN)Containers started$(NC)\n"

down: ## Stop and remove containers (keeps volumes)
	@$(DC) down
	@printf "$(GREEN)Containers stopped$(NC)\n"

logs: ## Show logs (follow mode)
	@$(DC) logs -f

logs-rclone: ## Show rclone-sync logs only
	@$(DC) logs -f rclone-sync

logs-antigravity: ## Show antigravity logs only
	@$(DC) logs -f antigravity

restart: ## Restart all containers
	@$(DC) restart
	@printf "$(GREEN)Containers restarted$(NC)\n"

restart-rclone: ## Restart rclone-sync only
	@$(DC) restart rclone-sync

restart-antigravity: ## Restart antigravity only
	@$(DC) restart antigravity

ps: ## Show container status
	@$(DC) ps

clean: ## Stop containers and remove volumes (WARNING: deletes data)
	@printf "$(YELLOW)WARNING: This will delete all data in volumes!$(NC)\n"
	@printf "Are you sure? [y/N] " && read answer; \
	case "$$answer" in \
		y|Y) $(DC) down -v && printf "$(GREEN)Containers and volumes removed$(NC)\n" ;; \
		*) printf "$(BLUE)Cancelled$(NC)\n" ;; \
	esac

backup: ## Backup antigravity_data volume to tar.gz
	@mkdir -p $(BACKUP_DIR)
	@BACKUP_FILE="$(BACKUP_DIR)/antigravity-backup-$$(date +%Y%m%d-%H%M%S).tar.gz"; \
	$(DC) run --rm -T --entrypoint sh rclone-sync -c "tar czf - -C /data/.antigravity_tools ." > "$$BACKUP_FILE" && \
	printf "$(GREEN)Backup created: %s$(NC)\n" "$$BACKUP_FILE"

restore: ## Restore antigravity_data volume from latest backup
	@LATEST_BACKUP=$$(ls -t $(BACKUP_DIR)/antigravity-backup-*.tar.gz 2>/dev/null | head -1); \
	if [ -z "$$LATEST_BACKUP" ]; then \
		printf "$(YELLOW)No backup files found in $(BACKUP_DIR)/$(NC)\n"; \
		exit 1; \
	fi; \
	printf "$(BLUE)Restoring from: %s$(NC)\n" "$$LATEST_BACKUP"; \
	cat "$$LATEST_BACKUP" | $(DC) run --rm -T --entrypoint sh rclone-sync -c "mkdir -p /data/.antigravity_tools && (rm -rf /data/.antigravity_tools/* /data/.antigravity_tools/.[!.]* /data/.antigravity_tools/..?* 2>/dev/null || true) && tar xzf - -C /data/.antigravity_tools" && \
	printf "$(GREEN)Restore completed$(NC)\n"

shell-rclone: ## Open shell in rclone-sync container
	@$(DC) exec rclone-sync sh

shell-antigravity: ## Open shell in antigravity container
	@$(DC) exec antigravity sh

check-ready: ## Check if READY flag exists
	@$(DC) exec rclone-sync sh -c 'if [ -f /shared/READY ]; then echo "READY flag exists"; echo "Created at: $$(cat /shared/READY)"; else echo "READY flag not found"; exit 1; fi'

sync-manual: ## Trigger manual sync UP to S3
	@$(DC) exec rclone-sync sh -c 'rclone sync /data/.antigravity_tools "$$REMOTE:$$REMOTE_PATH" -v --stats=1s --s3-list-version=2'

config-show: ## Show rclone configuration for the active remote
	@$(DC) exec rclone-sync sh -c 'rclone config show "$$REMOTE"'

test-s3: ## Test S3 connection
	@$(DC) exec rclone-sync sh -c 'rclone lsd "$$REMOTE:$$REMOTE_PATH" -v --s3-list-version=2'
