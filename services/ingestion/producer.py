from __future__ import annotations

import argparse
import json
from typing import Any

import requests
from kafka import KafkaProducer

from shared.models import RawDocument
from shared.settings import settings
from shared.storage import RAW_DOCS_FILE, append_jsonl

GDELT_URL = "https://api.gdeltproject.org/api/v2/doc/doc"


def build_producer() -> KafkaProducer:
    return KafkaProducer(
        bootstrap_servers=settings.kafka_bootstrap_servers,
        value_serializer=lambda value: json.dumps(value).encode("utf-8"),
    )


def fetch_gdelt_articles(limit: int = 10) -> list[dict[str, Any]]:
    response = requests.get(
        GDELT_URL,
        params={"query": settings.gdelt_query, "format": "json"},
        timeout=30,
    )
    response.raise_for_status()
    payload = response.json()
    return payload.get("articles", [])[:limit]


def normalize_article(article: dict[str, Any]) -> RawDocument:
    raw_text = "\n".join(
        part
        for part in [
            article.get("title", ""),
            article.get("snippet", ""),
            article.get("seendate", ""),
        ]
        if part
    ).strip()

    return RawDocument(
        source_type="gdelt",
        source_name="GDELT",
        title=article.get("title") or "Untitled article",
        url=article.get("url") or "https://example.com",
        published_at=article.get("seendate"),
        raw_text=raw_text or "No normalized body available yet.",
        metadata={
            "domain": article.get("domain"),
            "language": article.get("language"),
            "source_country": article.get("sourcecountry"),
        },
    )


def run(limit: int = 10, publish_to_kafka: bool = False) -> list[RawDocument]:
    articles = fetch_gdelt_articles(limit=limit)
    documents = [normalize_article(article) for article in articles]

    producer = build_producer() if publish_to_kafka else None
    try:
        for document in documents:
            append_jsonl(RAW_DOCS_FILE, document)
            if producer is not None:
                producer.send(settings.kafka_topic_raw_events, document.model_dump(mode="json"))
        if producer is not None:
            producer.flush()
    finally:
        if producer is not None:
            producer.close()

    return documents


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch GDELT articles into the Accord AI raw document store.")
    parser.add_argument("--limit", type=int, default=10, help="Maximum number of GDELT articles to fetch.")
    parser.add_argument(
        "--publish-kafka",
        action="store_true",
        help="Also publish normalized documents to the configured Kafka topic.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run(limit=args.limit, publish_to_kafka=args.publish_kafka)
