from __future__ import annotations

import argparse

from services.dedup.service import deduplicate_events
from services.extraction.extractor import extract_event
from services.narrative.service import cluster_narratives
from services.scoring.service import score_events
from services.verification.service import verify_events
from shared.models import Event, RawDocument
from shared.storage import EVENTS_FILE, RAW_DOCS_FILE, overwrite_jsonl, read_jsonl


def run_file_backed_pipeline(write_graph: bool = False) -> list[Event]:
    raw_documents = read_jsonl(RAW_DOCS_FILE, RawDocument)
    extracted = [extract_event(document) for document in raw_documents]
    deduped = deduplicate_events(extracted)
    verified = verify_events(deduped)
    scored = score_events(verified)
    overwrite_jsonl(EVENTS_FILE, scored)

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
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    events = run_file_backed_pipeline(write_graph=args.write_graph)
    print(f"Processed {len(events)} events.")
