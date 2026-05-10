#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 -m services.ingestion.producer --limit "${1:-10}"
python3 -m services.pipeline
python3 run_api.py
