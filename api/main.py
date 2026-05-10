from __future__ import annotations

from fastapi import FastAPI

from services.narrative.service import cluster_narratives
from shared.models import Event, HealthStatus
from shared.storage import EVENTS_FILE, read_jsonl

app = FastAPI(title="Accord AI API", version="0.1.0")


@app.get("/health", response_model=HealthStatus)
def health() -> HealthStatus:
    return HealthStatus(status="ok")


@app.get("/events", response_model=list[Event])
def list_events() -> list[Event]:
    return read_jsonl(EVENTS_FILE, Event)


@app.get("/narratives")
def list_narratives() -> list[dict]:
    events = read_jsonl(EVENTS_FILE, Event)
    clusters = cluster_narratives(events)
    return [cluster.model_dump() for cluster in clusters]
