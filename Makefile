# Makefile for Traefik local reverse proxy

COMPOSE = docker compose -f docker-compose.yml

DASHBOARD_URL = http://127.0.0.1:8080

.PHONY: help up down restart logs dashboard add-site remove-site

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  up                              - Start Traefik in detached mode."
	@echo "  down                            - Stop and remove Traefik container."
	@echo "  restart                         - Restart Traefik container."
	@echo "  logs                            - Follow Traefik container logs."
	@echo "  dashboard                       - Open Traefik dashboard in the default browser."
	@echo "  add-site SLUG=x DOMAIN=y.localhost  - Generate mkcert cert and dynamic TLS config."
	@echo "  remove-site SLUG=x              - Remove cert and dynamic TLS config for a site."
	@echo "  help                            - Show this help message."

.DEFAULT_GOAL := help

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

restart:
	docker restart traefik_proxy

logs:
	docker logs -f traefik_proxy

dashboard:
	@bash -c 'url="$(DASHBOARD_URL)"; \
	if command -v xdg-open >/dev/null 2>&1; then xdg-open "$$url"; \
	elif command -v open >/dev/null 2>&1; then open "$$url"; \
	elif command -v cmd.exe >/dev/null 2>&1; then cmd.exe //c start "" "$$url"; \
	else echo "Open $$url in your browser"; fi'

add-site:
ifndef SLUG
	$(error SLUG is required, e.g. make add-site SLUG=mysite DOMAIN=mysite.localhost)
endif
ifndef DOMAIN
	$(error DOMAIN is required, e.g. make add-site SLUG=mysite DOMAIN=mysite.localhost)
endif
	bash "$(CURDIR)/scripts/add-site.sh" "$(SLUG)" "$(DOMAIN)"

remove-site:
ifndef SLUG
	$(error SLUG is required, e.g. make remove-site SLUG=mysite)
endif
	bash "$(CURDIR)/scripts/remove-site.sh" "$(SLUG)"
