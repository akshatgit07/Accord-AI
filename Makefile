PYTHON := .venv/bin/python
RSCRIPT := Rscript
API_PORT ?= 8000
DASHBOARD_PORT ?= 8050

.PHONY: seed scrape api dashboard db-up db-init kafka-up stream-worker

seed:
	$(PYTHON) scripts/seed_sample_data.py
	$(PYTHON) -m services.pipeline

scrape:
	$(PYTHON) -m services.ingestion.firecrawl_client $(URLS)
	$(PYTHON) -m services.pipeline

api:
	$(PYTHON) run_api.py

dashboard:
	$(RSCRIPT) -e "shiny::runApp('dashboard', host='127.0.0.1', port=$(DASHBOARD_PORT))"

db-up:
	docker compose -f infra/docker-compose.yml up -d postgres

db-init:
	$(PYTHON) -c "from shared.database import init_db; init_db(); print('Postgres schema ready')"

kafka-up:
	docker compose -f infra/docker-compose.yml up -d zookeeper kafka

stream-worker:
	$(PYTHON) -m services.streaming.worker
