from __future__ import annotations

from pathlib import Path
from typing import Iterable

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

import psycopg

from shared.models import Event, RawDocument
from shared.settings import ROOT_DIR, settings

MIGRATION_PATH = ROOT_DIR / "infra" / "postgres" / "001_init.sql"


def connect():
    return psycopg.connect(settings.postgres_dsn, row_factory=dict_row)


def init_db() -> None:
    schema = MIGRATION_PATH.read_text(encoding="utf-8")
    with connect() as conn:
        conn.execute(schema)


def can_use_db() -> bool:
    try:
        with connect() as conn:
            conn.execute("SELECT 1")
        return True
    except Exception:
        return False


def upsert_raw_documents(documents: Iterable[RawDocument]) -> None:
    rows = list(documents)
    if not rows:
        return

    with connect() as conn:
        with conn.cursor() as cur:
            for document in rows:
                payload = document.model_dump(mode="json")
                cur.execute(
                    """
                    INSERT INTO raw_documents (
                      document_id, source_type, source_name, title, url,
                      published_at, captured_at, payload, updated_at
                    )
                    VALUES (
                      %(document_id)s, %(source_type)s, %(source_name)s, %(title)s, %(url)s,
                      %(published_at)s, %(captured_at)s, %(payload)s, now()
                    )
                    ON CONFLICT (document_id) DO UPDATE SET
                      source_type = EXCLUDED.source_type,
                      source_name = EXCLUDED.source_name,
                      title = EXCLUDED.title,
                      url = EXCLUDED.url,
                      published_at = EXCLUDED.published_at,
                      captured_at = EXCLUDED.captured_at,
                      payload = EXCLUDED.payload,
                      updated_at = now()
                    """,
                    {
                        "document_id": document.document_id,
                        "source_type": document.source_type,
                        "source_name": document.source_name,
                        "title": document.title,
                        "url": str(document.url),
                        "published_at": document.published_at,
                        "captured_at": document.captured_at,
                        "payload": Jsonb(payload),
                    },
                )


def upsert_events(events: Iterable[Event]) -> None:
    rows = list(events)
    if not rows:
        return

    with connect() as conn:
        with conn.cursor() as cur:
            for event in rows:
                payload = event.model_dump(mode="json")
                cur.execute(
                    """
                    INSERT INTO events (
                      event_id, document_id, source, event_type, narrative,
                      verification_status, priority, score, occurred_at, payload, updated_at
                    )
                    VALUES (
                      %(event_id)s, %(document_id)s, %(source)s, %(event_type)s, %(narrative)s,
                      %(verification_status)s, %(priority)s, %(score)s, %(occurred_at)s,
                      %(payload)s, now()
                    )
                    ON CONFLICT (event_id) DO UPDATE SET
                      document_id = EXCLUDED.document_id,
                      source = EXCLUDED.source,
                      event_type = EXCLUDED.event_type,
                      narrative = EXCLUDED.narrative,
                      verification_status = EXCLUDED.verification_status,
                      priority = EXCLUDED.priority,
                      score = EXCLUDED.score,
                      occurred_at = EXCLUDED.occurred_at,
                      payload = EXCLUDED.payload,
                      updated_at = now()
                    """,
                    {
                        "event_id": event.event_id,
                        "document_id": event.document_id,
                        "source": event.source,
                        "event_type": event.event_type,
                        "narrative": event.narrative,
                        "verification_status": event.verification_status,
                        "priority": event.priority,
                        "score": event.score,
                        "occurred_at": event.occurred_at,
                        "payload": Jsonb(payload),
                    },
                )


def read_events_from_db() -> list[Event]:
    with connect() as conn:
        rows = conn.execute("SELECT payload FROM events ORDER BY occurred_at NULLS LAST, updated_at").fetchall()
    return [Event.model_validate(row["payload"]) for row in rows]


def read_raw_documents_from_db() -> list[RawDocument]:
    with connect() as conn:
        rows = conn.execute("SELECT payload FROM raw_documents ORDER BY captured_at, updated_at").fetchall()
    return [RawDocument.model_validate(row["payload"]) for row in rows]


def persist_pipeline_state(documents: list[RawDocument], events: list[Event]) -> bool:
    try:
        init_db()
        upsert_raw_documents(documents)
        upsert_events(events)
        return True
    except Exception:
        return False
