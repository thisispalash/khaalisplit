# ---------------- khaaliSplit ---------------------------------------------------- #

.PHONY: dev prod

dev:
	@echo "Starting dev server..."
	@echo "TODO: Add your dev server command here"

prod:
	@echo "Starting prod server..."
	@echo "TODO: Add your prod server command here"



# Markefile Reference 1

# Makefile

# SHELL := /bin/bash
# TIMESTAMP := $(shell date +%Y%m%dT%H%M%S)
# LOG_DIR := logs
# SERVER_LOG := $(LOG_DIR)/serverlog-$(TIMESTAMP).log
# TAILWIND_LOG := $(LOG_DIR)/tailwindlog-$(TIMESTAMP).log

# .PHONY: dev server tailwind build-css clean-logs clean
# .DEFAULT_GOAL := dev

# # Create logs directory
# logs-dir:
# 	@mkdir -p $(LOG_DIR)

# # Run both Django and Tailwind with logging
# dev: logs-dir
# 	@echo "Starting dev server... Logs: $(SERVER_LOG), $(TAILWIND_LOG)"
# 	@trap 'kill 0' INT; \
# 		./tailwindcss -i static/css/tw-in.css -o static/css/tw.css --watch 2>&1 | tee $(TAILWIND_LOG) & \
# 		poetry run python manage.py runserver 2>&1 | tee $(SERVER_LOG)


# # Run just Django
# server: logs-dir
# 	poetry run python manage.py runserver 2>&1 | tee $(SERVER_LOG)

# # Run just Tailwind
# tailwind: logs-dir
# 	./tailwindcss -i static/css/tw-in.css -o static/css/tw.css --watch 2>&1 | tee $(TAILWIND_LOG)

# # Build production CSS
# build-css:
# 	./tailwindcss -i static/css/tw-in.css -o static/css/tw.css --minify

# # Clean logs older than 7 days
# clean-logs:
# 	find $(LOG_DIR) -name "*.log" -mtime +7 -delete

# # Clean all logs
# clean:
# 	rm -rf $(LOG_DIR)/*.log


# Markfile Reference 2

# SHELL := /bin/bash

# .PHONY: dev server tailwind build-css prod migrate makemigrations shell collectstatic
# .DEFAULT_GOAL := dev

# # ---------------- dev ----------------------------------------------------- #
# # Runs Tailwind watch + Django dev server in parallel
# dev:
# 	@trap 'kill 0' INT; \
# 		tailwindcss -i static/css/tw-in.css -o static/css/tw.css --watch & \
# 		poetry run python manage.py runserver 0.0.0.0:8000

# server:
# 	poetry run python manage.py runserver 0.0.0.0:8000

# tailwind:
# 	tailwindcss -i static/css/tw-in.css -o static/css/tw.css --watch

# # ── build ──────────────────────────────────────────────────────────
# build-css:
# 	tailwindcss -i static/css/tw-in.css -o static/css/tw.css --minify

# collectstatic:
# 	poetry run python manage.py collectstatic --noinput

# # ── prod ───────────────────────────────────────────────────────────
# prod: build-css collectstatic
# 	poetry run gunicorn --bind 0.0.0.0:8000 config.wsgi:unhinged_lander

# # ── django management ─────────────────────────────────────────────
# migrate:
# 	poetry run python manage.py migrate

# makemigrations:
# 	poetry run python manage.py makemigrations

# shell:
# 	poetry run python manage.py shell

# # ── docker shortcuts ──────────────────────────────────────────────
# docker-migrate:
# 	docker compose exec unhinged_lander make migrate

# docker-makemigrations:
# 	docker compose exec unhinged_lander make makemigrations

# docker-shell:
# 	docker compose exec unhinged_lander make shell

# docker-db-setup:
# 	docker compose run --rm unhinged_lander make makemigrations
# 	docker compose run --rm unhinged_lander make migrate
