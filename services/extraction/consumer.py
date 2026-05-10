from __future__ import annotations

import json

from kafka import KafkaConsumer, KafkaProducer

from services.extraction.extractor import extract_event
from shared.models import RawDocument
from shared.settings import settings
from shared.storage import EVENTS_FILE, append_jsonl


def run() -> None:
    consumer = KafkaConsumer(
        settings.kafka_topic_raw_events,
        bootstrap_servers=settings.kafka_bootstrap_servers,
        value_deserializer=lambda value: json.loads(value.decode("utf-8")),
    )
    producer = KafkaProducer(
        bootstrap_servers=settings.kafka_bootstrap_servers,
        value_serializer=lambda value: json.dumps(value).encode("utf-8"),
    )

    try:
        for message in consumer:
            document = RawDocument.model_validate(message.value)
            event = extract_event(document)
            append_jsonl(EVENTS_FILE, event)
            producer.send(settings.kafka_topic_structured_events, event.model_dump(mode="json"))
            producer.flush()
    finally:
        producer.close()
        consumer.close()


if __name__ == "__main__":
    run()
