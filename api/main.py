from __future__ import annotations

from fastapi import FastAPI

from services.alerts.service import summarize_alerts
from services.compliance.service import assess_compliance
from services.narrative.service import build_narrative_intelligence, calculate_influence, cluster_narratives
from shared.models import ComplianceReport, Event, HealthStatus
from shared.storage import EVENTS_FILE, read_jsonl

app = FastAPI(title="Accord AI API", version="0.1.0")


@app.get("/health", response_model=HealthStatus)
def health() -> HealthStatus:
    return HealthStatus(status="ok")


@app.get("/storage/status")
def storage_status() -> dict:
    try:
        from shared.database import can_use_db

        if can_use_db():
            return {"active_store": "postgres", "fallback_available": True}
    except Exception:
        pass

    return {"active_store": "jsonl_fallback", "fallback_available": True}


@app.get("/events", response_model=list[Event])
def list_events() -> list[Event]:
    try:
        from shared.database import read_events_from_db

        events = read_events_from_db()
        if events:
            return events
    except Exception:
        pass

    return read_jsonl(EVENTS_FILE, Event)


@app.get("/narratives")
def list_narratives() -> list[dict]:
    events = list_events()
    clusters = cluster_narratives(events)
    return [cluster.model_dump() for cluster in clusters]


@app.get("/influence")
def list_influence() -> list[dict]:
    events = list_events()
    records = calculate_influence(events)
    return [record.model_dump() for record in records]


@app.get("/alerts")
def list_alerts() -> list[dict]:
    events = list_events()
    summaries = summarize_alerts(events)
    return [summary.model_dump() for summary in summaries]


@app.get("/narrative-intelligence")
def narrative_intelligence() -> dict:
    events = list_events()
    intelligence = build_narrative_intelligence(events)
    return intelligence.model_dump()


@app.get("/compliance-report", response_model=ComplianceReport)
def compliance_report() -> ComplianceReport:
    events = list_events()
    intelligence = build_narrative_intelligence(events)
    return assess_compliance(events, intelligence)
