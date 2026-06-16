from __future__ import annotations

import argparse

from services.dedup.service import deduplicate_events
from services.extraction.extractor import extract_event
from services.narrative.service import cluster_narratives
from services.scoring.service import score_events
from services.verification.service import verify_events
from services.violation.service import classify_events
from shared.models import Event, RawDocument
from shared.storage import EVENTS_FILE, RAW_DOCS_FILE, overwrite_jsonl, read_jsonl


def run_file_backed_pipeline(write_graph: bool = False, persist_db: bool = True) -> list[Event]:
    raw_documents = read_jsonl(RAW_DOCS_FILE, RawDocument)
    extracted = [extract_event(document) for document in raw_documents]
    classified = classify_events(extracted)
    deduped = deduplicate_events(classified)
    verified = verify_events(deduped)
    scored = score_events(verified)
    overwrite_jsonl(EVENTS_FILE, scored)

    if persist_db:
        from shared.database import persist_pipeline_state

        persisted = persist_pipeline_state(raw_documents, scored)
        if persisted:
            print("Persisted pipeline state to Postgres.")
        else:
            print("Postgres unavailable; kept JSONL as the active local store.")

    cluster_narratives(scored)
    if write_graph:
        from services.graph.neo4j_client import add_event_graph

        for event in scored:
            add_event_graph(event)
    return scored


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the local Accord AI Phase 1 pipeline over stored raw documents.")
    parser.add_argument(
        "--write-graph",
        action="store_true",
        help="Write extracted event relationships to Neo4j.",
    )
    parser.add_argument(
        "--skip-db",
        action="store_true",
        help="Skip Postgres persistence and only write local JSONL files.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    events = run_file_backed_pipeline(write_graph=args.write_graph, persist_db=not args.skip_db)
    print(f"Processed {len(events)} events.")
