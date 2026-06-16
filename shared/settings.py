from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

ROOT_DIR = Path(__file__).resolve().parents[1]
load_dotenv(ROOT_DIR / ".env")
load_dotenv(ROOT_DIR / ".env.local")


class Settings:
    kafka_bootstrap_servers = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
    kafka_topic_raw_events = os.getenv("KAFKA_TOPIC_RAW_EVENTS", "raw-events")
    kafka_topic_structured_events = os.getenv("KAFKA_TOPIC_STRUCTURED_EVENTS", "structured-events")
    postgres_dsn = os.getenv("POSTGRES_DSN", "postgresql://accord:accord@localhost:5432/accord_ai")
    neo4j_uri = os.getenv("NEO4J_URI", "bolt://localhost:7687")
    neo4j_user = os.getenv("NEO4J_USER", "neo4j")
    neo4j_password = os.getenv("NEO4J_PASSWORD", "password")
    gdelt_query = os.getenv("GDELT_QUERY", "iran israel")
    firecrawl_api_key = os.getenv("FIRECRAWL_API_KEY")
    openai_api_key = os.getenv("OPENAI_API_KEY")
    openai_model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
    openai_summary_model = os.getenv("OPENAI_SUMMARY_MODEL", "gpt-5-nano")
    extraction_mode = os.getenv("EXTRACTION_MODE", "auto")
    verification_mode = os.getenv("VERIFICATION_MODE", "heuristic")
    compliance_mode = os.getenv("COMPLIANCE_MODE", "heuristic")
    api_host = os.getenv("API_HOST", "0.0.0.0")
    api_port = int(os.getenv("API_PORT", "8000"))


settings = Settings()
