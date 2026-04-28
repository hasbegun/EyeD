.PHONY: up up-prod up-dev up-test up-d down build build-gateway build-capture build-client build-storage rebuild logs health ready test-integration status clean nuke ps gallery webcam webcam-macos webcam-relay build-tools dev-client2 dev-client2-macos build-client2-web build-client2-macos db-shell db-reset db-clean export-training download-models build-iris2 test-iris2 test-iris-engine2-container clean-iris2 verify-s1 verify-s2 verify-s3 verify-s6 verify-dev-config verify-prod-config verify-fhe-toggle verify-db-isolation verify-fhe-persist verify-all fetch-openfhe build-vnv vnv-benchmark vnv-analyze vnv-report vnv vnv-clean db-reset-dev

# --- Core ---

PROD_COMPOSE := docker compose -f docker-compose.yml -f docker-compose.prod.yml

up: up-prod        ## Start all services (prod mode — safe default)

up-prod:           ## Start in prod mode (hardcoded EYED_MODE=prod)
	$(PROD_COMPOSE) up

up-dev:            ## Start in dev mode (FHE toggle, debug logs, eyed_dev database)
	EYED_MODE=dev docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

up-test:           ## Start in test mode (eyed_test database, integration-test auto-included)
	EYED_MODE=test docker compose -f docker-compose.yml -f docker-compose.test.yml --profile test up --build

up-d:              ## Start all services detached (prod mode)
	$(PROD_COMPOSE) up -d

down:              ## Stop all services
	docker compose down

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

# --- Status ---

ps:                ## Show running containers
	docker compose ps

health:            ## Liveness check (all services)
	@echo "--- iris-engine2 ---" && curl -s http://localhost:9510/health/alive | python3 -m json.tool
	@echo "--- gateway ---" && curl -s http://localhost:9504/health/alive | python3 -m json.tool
	@echo "--- storage ---" && curl -s http://localhost:9507/health/alive | python3 -m json.tool 2>/dev/null || echo '  (not running)'

ready:             ## Readiness check (all services)
	@echo "--- iris-engine2 ---" && curl -s http://localhost:9510/health/ready | python3 -m json.tool
	@echo "--- gateway ---" && curl -s http://localhost:9504/health/ready | python3 -m json.tool
	@echo "--- storage ---" && curl -s http://localhost:9507/health/ready | python3 -m json.tool 2>/dev/null || echo '  (not running)'

gallery:           ## Show gallery size
	@curl -s http://localhost:9510/gallery/size | python3 -m json.tool

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

logs-nats:         ## Follow NATS logs
	docker compose logs -f nats

logs-gateway:      ## Follow gateway logs
	docker compose logs -f gateway

logs-capture:      ## Follow capture-device logs
	docker compose logs -f capture-device

logs-storage:      ## Follow storage service logs
	docker compose logs -f storage

# --- Testing ---

test-integration:  ## Run end-to-end integration test (gateway → NATS → iris-engine2)
	@docker compose stop capture-device 2>/dev/null || true
	@sleep 2
	docker compose run --rm integration-test
	@docker compose start capture-device 2>/dev/null || true

# --- Security Gate Verification (Phase 4) ---
# Run these against a live stack: make up-prod / make up-dev as appropriate.

ENGINE := http://localhost:9510

verify-s1:         ## S1: POST /config/fhe must return 404 in prod (route not registered)
	@echo "=== S1: FHE toggle blocked in prod ==="
	@STATUS=$$(curl -s -o /dev/null -w "%{http_code}" -X POST $(ENGINE)/config/fhe \
		-H "Content-Type: application/json" -d '{"enabled":false}') && \
	if [ "$$STATUS" = "404" ]; then \
		echo "  PASS: POST /config/fhe → 404 (route not registered)"; \
	else \
		echo "  FAIL: POST /config/fhe → $$STATUS (expected 404)"; exit 1; \
	fi

verify-s2:         ## S2: GET /config in prod returns exactly gallery_size, db_connected, version
	@echo "=== S2: Config endpoint — no sensitive fields in prod ==="
	@STATUS=$$(curl -s -o /tmp/eyed_verify_s2.json -w "%{http_code}" $(ENGINE)/config); \
	echo "  HTTP $$STATUS  Response: $$(cat /tmp/eyed_verify_s2.json)"; \
	if [ "$$STATUS" != "200" ]; then \
		echo "  FAIL: GET /config returned HTTP $$STATUS (expected 200)"; \
		echo "  Hint: run 'make build-engine2' if the image is stale"; exit 1; \
	fi; \
	python3 -c "import sys,json; d=json.load(open('/tmp/eyed_verify_s2.json')); bad=[k for k in d if k not in {'gallery_size','db_connected','version'}]; print('  FAIL: unexpected keys:',bad) or sys.exit(1) if bad else print('  PASS: only allowed keys:',sorted(d.keys()))"

verify-s3:         ## S3: Database isolation — show row counts per mode database
	@echo "=== S3: Database isolation ==="
	@echo "--- prod (eyed) ---"
	@docker compose exec postgres psql -U eyed -d eyed -t \
	    -c "SELECT COUNT(*) AS identities FROM identities;" 2>/dev/null || echo "  (db not running)"
	@echo "--- dev (eyed_dev) ---"
	@docker compose exec postgres psql -U eyed -d eyed_dev -t \
	    -c "SELECT COUNT(*) AS identities FROM identities;" 2>/dev/null || echo "  (db not running)"
	@echo "--- test (eyed_test) ---"
	@docker compose exec postgres psql -U eyed -d eyed_test -t \
	    -c "SELECT COUNT(*) AS identities FROM identities;" 2>/dev/null || echo "  (db not running)"

verify-s6:         ## S6: Show last 30 engine2 log lines (prod should show warn-level only)
	@echo "=== S6: iris-engine2 log verbosity ==="
	@docker compose logs --tail=30 iris-engine2 2>&1

verify-dev-config: ## A1: GET /config in dev mode — shows full config including mode/fhe fields
	@echo "=== A1: GET /config (expect full config in dev) ==="
	@curl -s $(ENGINE)/config | python3 -m json.tool

verify-prod-config: ## A2: GET /config in prod mode — shows minimal config
	@echo "=== A2: GET /config (expect minimal config in prod) ==="
	@curl -s $(ENGINE)/config | python3 -m json.tool

verify-fhe-toggle: ## A3/A4: Toggle FHE on then off (run against dev; prod should return 404)
	@echo "=== A3: Toggle FHE off ==="
	@curl -s -X POST $(ENGINE)/config/fhe \
	    -H "Content-Type: application/json" -d '{"enabled":false}' | python3 -m json.tool
	@echo "=== A3: Toggle FHE on ==="
	@curl -s -X POST $(ENGINE)/config/fhe \
	    -H "Content-Type: application/json" -d '{"enabled":true}' | python3 -m json.tool

verify-db-isolation: ## S3 extended: full template counts across all three databases
	@echo "=== Database template counts ==="
	@for DB in eyed eyed_dev eyed_test; do \
	    echo "--- $$DB ---"; \
	    docker compose exec postgres psql -U eyed -d $$DB -t \
	        -c "SELECT COUNT(*) AS templates FROM templates;" 2>/dev/null || echo "  (not found)"; \
	done

verify-fhe-persist: ## S8: Show persisted FHE toggle state file inside iris-engine2 container
	@echo "=== FHE persist: /config/fhe_state ==="
	@docker compose exec iris-engine2 cat /config/fhe_state 2>/dev/null \
	    && echo "" || echo "  (no persisted state — normal for fresh prod deployment)"

verify-all:        ## Run all automated security gate checks (S1, S2, S3, S6) in sequence
	@echo "================================================"
	@echo " EyeD Security Gate Verification"
	@echo "================================================"
	@$(MAKE) verify-s1
	@$(MAKE) verify-s2
	@$(MAKE) verify-s3
	@$(MAKE) verify-s6
	@echo "================================================"
	@echo " All automated gates passed."
	@echo " Manual gates (S4, S7, S8) require human review"
	@echo " — see dev-option.md §4 Phase 4 for details."
	@echo "================================================"

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

dev-client2:        ## Start Flutter client2 (web, Chrome)
	cd client2 && $(FLUTTER) run -d chrome

dev-client2-macos:  ## Start Flutter client2 (macOS native)
	cd client2 && $(FLUTTER) run -d macos

build-client2-web:  ## Build Flutter client2 for web
	cd client2 && $(FLUTTER) build web --release

build-client2-macos: ## Build Flutter client2 for macOS
	cd client2 && $(FLUTTER) build macos --release

# --- Database ---

db-shell:          ## Open psql shell in postgres container
	docker compose exec postgres psql -U eyed -d eyed

db-reset:          ## Drop and recreate database schema (prod: eyed)
	docker compose exec postgres psql -U eyed -d eyed -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
	docker compose exec postgres psql -U eyed -d eyed -f /docker-entrypoint-initdb.d/01-init.sql

db-reset-dev:      ## Drop and recreate dev database schema (eyed_dev)
	docker compose exec postgres psql -U eyed -d eyed_dev -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
	docker compose exec postgres psql -U eyed -d eyed_dev -f /docker-entrypoint-initdb.d/01-init.sql

db-clean:          ## Clean database for dev (warns before deleting)
	@echo ""
	@echo "  WARNING: This will DELETE ALL DATA in the eyed database."
	@echo "  All identities, templates, and match logs will be permanently lost."
	@echo "  This action is IRREVERSIBLE."
	@echo ""
	@read -p "  Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || (echo "  Aborted." && exit 1)
	@echo "  Cleaning database..."
	docker compose exec postgres psql -U eyed -d eyed -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
	docker compose exec postgres psql -U eyed -d eyed -f /docker-entrypoint-initdb.d/01-init.sql
	@echo "  Database cleaned and schema recreated."

# --- Training Data ---

export-training:   ## Export training dataset from archive
	python3 scripts/export_training.py --db-url postgresql://eyed:eyed_dev@localhost:9506/eyed --archive-root ./data/archive --output-dir ./data/training-export

# --- Models ---

fetch-openfhe:     ## Clone OpenFHE v1.4.2 into 3rd-party/ (fallback if local copy absent)
	@mkdir -p 3rd-party/openfhe_1-4-2
	@if [ -d 3rd-party/openfhe_1-4-2/openfhe-development ]; then \
		echo "  OpenFHE v1.4.2 already present in 3rd-party/ — nothing to do"; \
	else \
		echo "  Cloning openfhe-development v1.4.2 ..."; \
		git clone --depth 1 --branch v1.4.2 \
			https://github.com/openfheorg/openfhe-development.git \
			3rd-party/openfhe_1-4-2/openfhe-development; \
		echo "  Done — rebuild with 'make build'"; \
	fi

download-models:   ## Download ONNX segmentation model from HuggingFace
	@mkdir -p models
	@if [ -f models/iris_semseg_upp_scse_mobilenetv2.onnx ]; then \
		echo "  Model already exists: models/iris_semseg_upp_scse_mobilenetv2.onnx"; \
	else \
		echo "  Downloading segmentation model from HuggingFace..."; \
		curl -L -o models/iris_semseg_upp_scse_mobilenetv2.onnx \
			"https://huggingface.co/Worldcoin/iris-semantic-segmentation/resolve/main/iris_semseg_upp_scse_mobilenetv2.onnx"; \
		echo "  Done."; \
	fi

# --- iris-engine2 (C++ libiris) ---

IRIS2_SRC := iris-engine2/.libiris/iris
IRIS2_BUILD := iris-engine2/build

stage-iris2:
	mkdir -p $(IRIS2_SRC)
	cp -r ../BiometricLib/iris/* $(IRIS2_SRC)/
# 	ln -s ../../BiometricLib/iris $(IRIS2_SRC)

build-iris2:       ## Build iris-engine2 C++ library (in container)
	docker compose -f $(IRIS2_SRC)/docker-compose.yml build test

test-iris2:        ## Run iris-engine2 C++ tests (in container)
	docker compose -f $(IRIS2_SRC)/docker-compose.yml run --rm test

test-iris-engine2-container: ## Run iris-engine2 C++ unit tests in container
	cd iris-engine2 && docker compose -f docker-compose.test.yml build --no-cache && docker compose -f docker-compose.test.yml run --rm test

clean-iris2:       ## Remove iris-engine2 build artifacts
	docker compose -f $(IRIS2_SRC)/docker-compose.yml down --rmi local --remove-orphans 2>/dev/null || true

# --- iris-engine2 service ---

build-engine2:     ## Build iris-engine2 service Docker image
	docker compose build iris-engine2

up-engine2:        ## Start iris-engine2 service (port 9510)
	docker compose up iris-engine2

logs-engine2:      ## Follow iris-engine2 logs
	docker compose logs -f iris-engine2

health-engine2:    ## Health check iris-engine2
	@echo "--- iris-engine2 ---" && curl -s http://localhost:9510/health/ready | python3 -m json.tool

gallery-engine2:   ## Show iris-engine2 gallery size
	@curl -s http://localhost:9510/gallery/size | python3 -m json.tool

# --- V&V Benchmark ---

DEV_COMPOSE := EYED_MODE=dev docker compose -f docker-compose.yml -f docker-compose.dev.yml
VNV_RUN := $(DEV_COMPOSE) --profile vnv run --rm vnv

build-vnv:         ## Build V&V benchmark container
	$(DEV_COMPOSE) --profile vnv build vnv

vnv-benchmark:     ## Run V&V benchmark (enroll + genuine + impostor probes) in container
	@echo "=== V&V Benchmark ==="
	@echo "Ensure dev stack is running: make up-dev"
	$(VNV_RUN) benchmark.py --no-progress

vnv-analyze:       ## Analyze V&V results and generate plots
	$(VNV_RUN) analyze.py --input /reports/vnv/latest

vnv-report:        ## Generate self-contained HTML report
	$(VNV_RUN) report.py --input /reports/vnv/latest

vnv:               ## Run full V&V pipeline: db-reset → benchmark → analyze → report
	@echo "================================================"
	@echo " EyeD V&V Full Pipeline"
	@echo " Dataset: CASIA-Iris-Thousand (1000 subjects)"
	@echo " Enrolled: 000-799 (80%), Impostor: 800-999 (20%)"
	@echo "================================================"
	$(MAKE) db-reset-dev
	@echo "Waiting for iris-engine2 to reload gallery..."
	@sleep 5
	$(MAKE) vnv-benchmark
	$(MAKE) vnv-analyze
	$(MAKE) vnv-report
	@echo "================================================"
	@echo " V&V Complete. Report: reports/vnv/latest/report.html"
	@echo "================================================"

vnv-clean:         ## Remove all V&V reports
	rm -rf reports/vnv/

# --- Cleanup ---

clean:             ## Stop and remove volumes
	docker compose down -v

nuke:              ## Remove everything (containers, volumes, images, networks)
	docker compose down -v --rmi all --remove-orphans

# --- Help ---

help:              ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
