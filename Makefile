.PHONY: up down dev build build-gateway build-capture build-client build-storage rebuild logs health ready test test-fnmr test-fnmr-mmu2 test-bench shell status clean nuke ps gallery webcam webcam-macos webcam-relay build-tools dev-client dev-client-macos build-client-web build-client-macos db-shell db-reset export-training

# --- Core ---

up:                ## Start all services
	docker compose up

up-d:              ## Start all services (detached)
	docker compose up -d

down:              ## Stop all services
	docker compose down

dev:               ## Start with hot reload (development)
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up

build:             ## Build all service images
	docker compose build

build-gateway:     ## Build gateway image only
	docker compose build gateway

build-capture:     ## Build capture-device image only
	docker compose build capture-device

build-client:      ## Build client (Flutter web) Docker image
	docker compose build client

build-storage:     ## Build storage service image
	docker compose build storage

rebuild:           ## Rebuild all without cache
	docker compose build --no-cache

restart:           ## Restart iris-engine
	docker compose restart iris-engine

# --- Status ---

ps:                ## Show running containers
	docker compose ps

health:            ## Liveness check (all services)
	@echo "--- iris-engine ---" && curl -s http://localhost:9500/health/alive | python3 -m json.tool
	@echo "--- gateway ---" && curl -s http://localhost:9504/health/alive | python3 -m json.tool
	@echo "--- storage ---" && curl -s http://localhost:9507/health/alive | python3 -m json.tool 2>/dev/null || echo '  (not running)'

ready:             ## Readiness check (all services)
	@echo "--- iris-engine ---" && curl -s http://localhost:9500/health/ready | python3 -m json.tool
	@echo "--- gateway ---" && curl -s http://localhost:9504/health/ready | python3 -m json.tool
	@echo "--- storage ---" && curl -s http://localhost:9507/health/ready | python3 -m json.tool 2>/dev/null || echo '  (not running)'

gallery:           ## Show gallery size
	@curl -s http://localhost:9500/gallery/size | python3 -m json.tool

nats-info:         ## NATS server info
	@curl -s http://localhost:9501/varz | python3 -m json.tool

nats-conns:        ## NATS active connections
	@curl -s http://localhost:9501/connz | python3 -m json.tool

nats-subs:         ## NATS subscriptions
	@curl -s http://localhost:9501/subsz | python3 -m json.tool

status: ps health ready gallery  ## Full status overview

# --- Logs ---

logs:              ## Follow all logs
	docker compose logs -f

logs-engine:       ## Follow iris-engine logs
	docker compose logs -f iris-engine

logs-nats:         ## Follow NATS logs
	docker compose logs -f nats

logs-gateway:      ## Follow gateway logs
	docker compose logs -f gateway

logs-capture:      ## Follow capture-device logs
	docker compose logs -f capture-device

logs-storage:      ## Follow storage service logs
	docker compose logs -f storage

# --- Testing ---

test:              ## Run fast unit tests inside container
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec iris-engine pytest tests/test_pipeline.py -v

test-integration:  ## Run end-to-end integration test (gateway → NATS → iris-engine)
	@docker compose stop capture-device 2>/dev/null || true
	@sleep 2
	docker compose run --rm integration-test
	@docker compose start capture-device 2>/dev/null || true

test-fnmr:         ## Run FNMR accuracy test on CASIA1 dataset
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec iris-engine pytest tests/test_fnmr.py -v -s

test-fnmr-mmu2:    ## Run FNMR accuracy test on MMU2 dataset
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec iris-engine pytest tests/test_fnmr_mmu2.py -v -s

test-bench:        ## Run pipeline latency benchmark
	docker compose -f docker-compose.yml -f docker-compose.dev.yml exec iris-engine pytest tests/test_benchmark.py -v -s

shell:             ## Open shell in iris-engine container
	docker compose exec iris-engine /bin/bash

# --- Client Logs ---

logs-client:       ## Follow client (nginx) logs
	docker compose logs -f client

# --- Webcam ---

webcam:             ## Start with webcam (Linux — /dev/video0 passthrough)
	docker compose -f docker-compose.yml -f docker-compose.webcam.yml up

webcam-macos:       ## Start with webcam (macOS — requires webcam-relay running)
	docker compose -f docker-compose.yml -f docker-compose.webcam-macos.yml up

webcam-relay:       ## Run MJPEG webcam relay on host (macOS/Windows)
	./build/tools/webcam-relay

build-tools:        ## Build native tools (webcam-relay)
	cmake -B build/tools tools
	cmake --build build/tools

# --- Flutter Client ---

FLUTTER := fvm flutter

dev-client:         ## Start Flutter client (web, Chrome)
	cd client && $(FLUTTER) run -d chrome

dev-client-macos:   ## Start Flutter client (macOS native)
	cd client && $(FLUTTER) run -d macos

dev-client-macos-clean:   ## Start Flutter clean client (macOS native)
	cd client && $(FLUTTER) clean && $(FLUTTER) run -d macos

build-client-web:   ## Build Flutter client for web
	cd client && $(FLUTTER) build web --release

build-client-macos: ## Build Flutter client for macOS
	cd client && $(FLUTTER) build macos --release

# --- Database ---

db-shell:          ## Open psql shell in postgres container
	docker compose exec postgres psql -U eyed -d eyed

db-reset:          ## Drop and recreate database schema
	docker compose exec postgres psql -U eyed -d eyed -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
	docker compose exec postgres psql -U eyed -d eyed -f /docker-entrypoint-initdb.d/init.sql

# --- Training Data ---

export-training:   ## Export training dataset from archive
	python3 scripts/export_training.py --db-url postgresql://eyed:eyed_dev@localhost:9506/eyed --archive-root ./data/archive --output-dir ./data/training-export

# --- Cleanup ---

clean:             ## Stop and remove volumes
	docker compose down -v

nuke:              ## Remove everything (containers, volumes, images, networks)
	docker compose down -v --rmi all --remove-orphans

# --- Help ---

help:              ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
