PYTHON := .venv/bin/python
RSCRIPT := Rscript
API_PORT ?= 8000
DASHBOARD_PORT ?= 8050

.PHONY: seed api dashboard

seed:
	$(PYTHON) scripts/seed_sample_data.py
	$(PYTHON) -m services.pipeline

api:
	$(PYTHON) run_api.py

dashboard:
	$(RSCRIPT) -e "shiny::runApp('dashboard', host='127.0.0.1', port=$(DASHBOARD_PORT))"
