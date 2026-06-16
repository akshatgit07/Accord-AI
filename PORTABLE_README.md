# Accord-AI

Accord-AI is an AI intelligence platform prototype for monitoring geopolitical events, extracting structured signals, detecting ceasefire violations and propaganda alerts, tracking narratives, scoring risk, and displaying results in an analyst dashboard.

The project is designed as a production-style architecture, but the current local demo can run without full infrastructure by using JSONL file storage as a fallback.

## What It Does

Accord-AI tracks events from news-style sources and converts them into analyst-ready intelligence records.

Core features:

- Event extraction from raw source documents
- OpenAI structured extraction with heuristic fallback
- Firecrawl web scraping with OpenAI markdown summarization
- Ceasefire violation detection
- Propaganda / disinformation alert detection
- Sanctions signal classification
- Narrative grouping
- Source influence tracking
- Risk scoring and priority assignment
- FastAPI backend
- Shiny dashboard with map, timeline, filters, source badges, and event detail drawer
- Postgres-ready persistence layer
- Kafka-ready streaming worker
- Neo4j-ready graph layer

## Architecture

Target production architecture:

```text
Data Sources
News / X / RSS / GDELT / Firecrawl
        |
        v
Kafka Streaming Backbone
        |
        v
Event Extraction
OpenAI structured extraction or heuristic fallback
        |
        v
Violation Classification
Ceasefire / Propaganda / Sanctions / General Signal
        |
        v
Deduplication
        |
        v
Verification
        |
        v
Scoring Layer
        |
        v
Postgres Event Store
        |
        v
FastAPI
        |
        v
Shiny Dashboard
```

Graph architecture:

```text
Source -> Event -> Narrative
```

This supports influence tracking such as:

```text
Which source is driving which narrative?
Which narratives contain alert-heavy events?
Which sources repeatedly publish high-score signals?
```

## Current Local Demo Path

The local demo currently runs through:

```text
Seed documents
or Firecrawl scraped web pages
-> JSONL raw document store
-> extraction
-> event type classification
-> deduplication
-> verification
-> scoring
-> JSONL event store
-> FastAPI
-> Shiny dashboard
```

Postgres, Kafka, and Neo4j are scaffolded and ready, but the demo can run without them.

## Project Structure

```text
accord-ai/
  api/
    main.py

  dashboard/
    app.R

  data/
    raw_documents.jsonl
    events.jsonl

  infra/
    docker-compose.yml
    kafka/
    postgres/
      001_init.sql

  notebooks/

  scripts/
    seed_sample_data.py
    run_phase1.sh

  services/
    dedup/
      service.py

    extraction/
      extractor.py
      consumer.py

    graph/
      neo4j_client.py

    ingestion/
      producer.py
      firecrawl_client.py

    narrative/
      service.py

    scoring/
      service.py

    streaming/
      worker.py

    verification/
      service.py

    violation/
      service.py

    pipeline.py

  shared/
    database.py
    models.py
    settings.py
    storage.py

  .env.example
  .gitignore
  Makefile
  README.md
  requirements.txt
  run_api.py
```

## Event Types

Accord-AI currently supports these event types:

```text
geopolitical_signal
sanctions_signal
ceasefire_violation
propaganda_alert
```

Example event:

```json
{
  "event_id": "evt_example",
  "document_id": "doc_example",
  "source": "AP",
  "headline": "Observers report ceasefire violation after overnight shelling",
  "summary": "Observers report ceasefire violation after overnight shelling: extracted from AP for analyst review.",
  "event_type": "ceasefire_violation",
  "narrative": "ceasefire monitoring",
  "entities": [],
  "locations": [
    {
      "name": "Jerusalem",
      "lat": 31.7683,
      "lon": 35.2137
    }
  ],
  "occurred_at": "2026-04-21T10:00:00Z",
  "verification_status": "unverified",
  "score": 0.55,
  "priority": "p2",
  "metadata": {
    "extraction_mode": "heuristic_baseline",
    "alert_reason": "ceasefire language paired with a hostile incident term",
    "verification_reason": "single-source or isolated signal"
  }
}
```

## Setup

Create a Python environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Copy environment settings:

```bash
cp .env.example .env
```

Example `.env`:

```env
KAFKA_BOOTSTRAP_SERVERS=localhost:9092
KAFKA_TOPIC_RAW_EVENTS=raw-events
KAFKA_TOPIC_STRUCTURED_EVENTS=structured-events
POSTGRES_DSN=postgresql://accord:accord@localhost:5432/accord_ai
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=password
GDELT_QUERY=iran israel
FIRECRAWL_API_KEY=
OPENAI_MODEL=gpt-4.1-mini
OPENAI_SUMMARY_MODEL=gpt-5-nano
EXTRACTION_MODE=auto
API_HOST=0.0.0.0
API_PORT=8000
```

## Run Local Demo

Seed local documents and run the pipeline:

```bash
make seed
```

Start the API:

```bash
make api
```

Start the dashboard:

```bash
make dashboard
```

Scrape live web pages with Firecrawl, summarize the markdown with OpenAI, append the result to `data/raw_documents.jsonl`, and rerun event extraction:

```bash
make scrape URLS="https://example.com/news-page https://example.com/report"
```

## Firecrawl MCP

The project includes `.mcp.json` for MCP-capable clients:

```json
{
  "mcpServers": {
    "firecrawl": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"],
      "env": {
        "FIRECRAWL_API_KEY": "${FIRECRAWL_API_KEY}"
      }
    }
  }
}
```

Set `FIRECRAWL_API_KEY` in your shell or client environment, then reload the MCP client.

Open:

```text
http://127.0.0.1:8050
```

API runs at:

```text
http://0.0.0.0:8000
```

Useful API endpoints:

```text
GET /health
GET /storage/status
GET /events
GET /narratives
GET /influence
GET /alerts
```

## Make Commands

```bash
make seed
```

Runs seed data generation and the local event pipeline.

```bash
make scrape URLS="https://example.com/news-page"
```

Scrapes web content with Firecrawl, summarizes it with OpenAI, and runs the local event pipeline.

```bash
make api
```

Starts FastAPI.

```bash
make dashboard
```

Starts the Shiny dashboard.

```bash
make db-up
```

Starts Postgres through Docker Compose.

```bash
make db-init
```

Initializes the Postgres schema.

```bash
make kafka-up
```

Starts Kafka and Zookeeper through Docker Compose.

```bash
make stream-worker
```

Starts the Kafka streaming worker.

## Dashboard Features

The Shiny dashboard includes:

- Event map with Leaflet markers
- Risk timeline with Plotly
- Narrative filter
- Event type filter
- Phase 2 alert summaries from `/alerts`
- Severity legend
- Source influence ranking
- Narrative snapshots
- Event cards with source and status badges
- Focused event detail drawer
- API polling every 5 seconds
- JSONL fallback if API or database is unavailable

## Storage Modes

Accord-AI supports two storage modes.

### JSONL Fallback Mode

This is the default local demo mode.

Files:

```text
data/raw_documents.jsonl
data/events.jsonl
```

This works without Docker, Postgres, Kafka, or Neo4j.

### Postgres Mode

When Postgres is available, the pipeline writes to Postgres and the API reads from Postgres first.

Start Postgres:

```bash
make db-up
make db-init
make seed
```

Check active storage:

```bash
curl http://localhost:8000/storage/status
```

Expected Postgres response:

```json
{
  "active_store": "postgres",
  "fallback_available": true
}
```

Fallback response:

```json
{
  "active_store": "jsonl_fallback",
  "fallback_available": true
}
```

## Kafka Streaming Path

Kafka architecture is scaffolded.

Start Kafka:

```bash
make kafka-up
```

Publish raw events:

```bash
python3 -m services.ingestion.producer --limit 10 --publish-kafka
```

Run streaming worker:

```bash
make stream-worker
```

The worker consumes:

```text
raw-events
```

And publishes:

```text
structured-events
```

## Neo4j Graph Layer

Neo4j support is scaffolded in:

```text
services/graph/neo4j_client.py
```

Current graph model:

```text
(Source)-[:PUBLISHES]->(Event)-[:BELONGS_TO]->(Narrative)
```

The graph layer stores:

- source
- narrative
- event ID
- headline
- event type
- score
- priority

Example influence query:

```cypher
MATCH (s:Source)-[:PUBLISHES]->(e:Event)-[:BELONGS_TO]->(n:Narrative)
RETURN s.name AS source,
       n.name AS narrative,
       count(e) AS event_count,
       sum(CASE WHEN e.event_type IN ['ceasefire_violation', 'propaganda_alert'] THEN 1 ELSE 0 END) AS alert_count,
       avg(e.score) AS average_score
ORDER BY event_count DESC, alert_count DESC
```

## Current Limitations

This is a strong prototype, not a fully production-grade system yet.

Current limitations:

- Event extraction uses OpenAI structured outputs when `OPENAI_API_KEY` is configured
- Heuristic extraction remains as the no-key/no-network fallback
- Propaganda and ceasefire labels are LLM-extracted first, then normalized by heuristic classifiers as a guardrail
- Verification is simple narrative-count logic
- Kafka is scaffolded but not required for local demo
- Neo4j is scaffolded but not dashboard-critical yet
- Postgres is supported but local fallback works without it
- Real-time ingestion is not continuous unless Kafka worker is running

## Suggested Next Phases

### Phase 1: Local Analyst Demo

Status: implemented.

Includes:

- seed data
- extraction
- event classification
- scoring
- FastAPI
- Shiny dashboard
- JSONL fallback

### Phase 2: Structured Intelligence Layer

Status: implemented for the local prototype.

Includes:

- ceasefire violation event type
- propaganda alert event type
- sanctions signal event type
- OpenAI structured event extraction
- narrative grouping
- influence tracking
- alert summary API at `/alerts`
- dashboard alert summary panel
- regression tests for event classification, alert summaries, narrative grouping, and influence tracking

### Phase 3: Real Persistence

Next recommended step.

Implement fully:

- Docker Postgres
- database migrations
- API reads from Postgres
- dashboard backed by API/Postgres

### Phase 4: Streaming

Implement fully:

- Kafka producer
- Kafka consumer
- structured event topic
- streaming dashboard refresh

### Phase 5: Graph Intelligence

Implement fully:

- Neo4j graph writes
- source influence queries
- narrative propagation tracking
- dashboard graph panel

### Phase 6: Extraction Hardening

Expand the current schema-based LLM output with evidence spans, confidence rationales, and evaluation tests.

Target structured output:

```json
{
  "event_type": "ceasefire_violation",
  "summary": "Short analyst summary",
  "entities": ["Entity A", "Entity B"],
  "locations": [
    {
      "name": "Location",
      "lat": 0,
      "lon": 0
    }
  ],
  "narrative": "ceasefire monitoring",
  "confidence": 0.82,
  "evidence": [
    {
      "quote": "Short supporting source excerpt"
    }
  ]
}
```

## Portfolio Summary

Accord-AI is a real-time intelligence platform prototype for monitoring geopolitical compliance signals. It uses structured event extraction, ceasefire violation detection, propaganda alert classification, narrative clustering, influence tracking, risk scoring, FastAPI, and an interactive Shiny dashboard.

Resume version:

```text
Built Accord-AI, an AI intelligence platform prototype for geopolitical monitoring with structured event extraction, ceasefire violation detection, propaganda alert classification, narrative influence tracking, FastAPI APIs, Postgres/Kafka/Neo4j-ready architecture, and an interactive Shiny dashboard for geospatial and temporal analysis.
```

## Demo Script

Run:

```bash
source .venv/bin/activate
make seed
make api
```

In another terminal:

```bash
make dashboard
```

Open:

```text
http://127.0.0.1:8050
```

You should see:

- 4 seeded events
- ceasefire violation alert
- propaganda alert
- sanctions signal
- regional escalation narrative
- influence ranking
- map markers
- timeline
- event detail drawer
