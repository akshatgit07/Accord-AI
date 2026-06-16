from __future__ import annotations

import argparse
import json
from typing import Optional

from kafka import KafkaConsumer, KafkaProducer

from services.dedup.service import deduplicate_events
from services.extraction.extractor import extract_event
from services.scoring.service import score_events
from services.verification.service import verify_events
from services.violation.service import classify_event_type
from shared.models import Event, RawDocument
from shared.settings import settings
from shared.storage import EVENTS_FILE, RAW_DOCS_FILE, append_jsonl, overwrite_jsonl, read_jsonl


def build_consumer() -> KafkaConsumer:
    return KafkaConsumer(
        settings.kafka_topic_raw_events,
        bootstrap_servers=settings.kafka_bootstrap_servers,
        value_deserializer=lambda value: json.loads(value.decode("utf-8")),
        auto_offset_reset="earliest",
        enable_auto_commit=True,
        group_id="accord-ai-extraction",
    )


def build_producer() -> KafkaProducer:
    return KafkaProducer(
        bootstrap_servers=settings.kafka_bootstrap_servers,
        value_serializer=lambda value: json.dumps(value).encode("utf-8"),
    )


def process_document(document: RawDocument) -> list[Event]:
    append_jsonl(RAW_DOCS_FILE, document)

    existing_events = read_jsonl(EVENTS_FILE, Event)
    extracted = classify_event_type(extract_event(document))
    candidate_events = existing_events + [extracted]
    deduped = deduplicate_events(candidate_events)
    verified = verify_events(deduped)
    scored = score_events(verified)
    overwrite_jsonl(EVENTS_FILE, scored)

    try:
        from shared.database import persist_pipeline_state

        raw_documents = read_jsonl(RAW_DOCS_FILE, RawDocument)
        persist_pipeline_state(raw_documents, scored)
    except Exception:
        pass

    return scored


def run(max_messages: Optional[int] = None) -> None:
    consumer = build_consumer()
    producer = build_producer()
    processed = 0

    try:
        for message in consumer:
            document = RawDocument.model_validate(message.value)
            scored_events = process_document(document)
            for event in scored_events:
                producer.send(settings.kafka_topic_structured_events, event.model_dump(mode="json"))
            producer.flush()

            processed += 1
            print(f"Processed streamed document {document.document_id}.")
            if max_messages is not None and processed >= max_messages:
                break
    finally:
        producer.close()
        consumer.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Accord AI Kafka streaming worker.")
    parser.add_argument(
        "--max-messages",
        type=int,
        default=None,
        help="Stop after processing this many Kafka messages. Useful for local smoke tests.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run(max_messages=args.max_messages)
