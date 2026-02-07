# ---------------- khaaliSplit ---------------------------------------------------- #

SHELL := /bin/bash

.PHONY: dev server tailwind build prod migrate makemigrations shell collectstatic \
        docker-migrate docker-makemigrations docker-shell docker-db-setup
.DEFAULT_GOAL := dev

# ── dev ──────────────────────────────────────────────────────────
# Runs Tailwind watch + Django dev server in parallel

dev:
	@trap 'kill 0' INT; \
		tailwindcss -i static/css/tw-in.css -o static/css/tw.css --watch & \
		poetry run python manage.py runserver 0.0.0.0:8000

server:
	poetry run python manage.py runserver 0.0.0.0:8000

tailwind:
	tailwindcss -i static/css/tw-in.css -o static/css/tw.css --watch

# ── build ────────────────────────────────────────────────────────

build-css:
	tailwindcss -i static/css/tw-in.css -o static/css/tw.css --minify

collectstatic:
	poetry run python manage.py collectstatic --noinput

build: build-css collectstatic makemigrations migrate

# ── prod ─────────────────────────────────────────────────────────

prod: build
	poetry run gunicorn --bind 0.0.0.0:8000 config.wsgi:khaaliSplit

# ── django management ────────────────────────────────────────────

migrate:
	poetry run python manage.py migrate

makemigrations:
	poetry run python manage.py makemigrations

shell:
	poetry run python manage.py shell

# ── docker shortcuts ─────────────────────────────────────────────

docker-migrate:
	docker compose exec khaaliSplit make migrate

docker-makemigrations:
	docker compose exec khaaliSplit make makemigrations

docker-shell:
	docker compose exec khaaliSplit make shell

docker-db-setup:
	docker compose run --rm khaaliSplit make makemigrations
	docker compose run --rm khaaliSplit make migrate
