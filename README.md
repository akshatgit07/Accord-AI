# Accord-AI
Built a real-time AI geopolitical intelligence platform using Kafka, FastAPI, Neo4j, and LLMs to detect treaty violations, perform multi-source event verification, track propaganda narratives, and visualize conflict dynamics through interactive geospatial dashboards.
AccordAI — AI-Powered Geopolitical Intelligence & Compliance Tracking
🧠 Overview

AccordAI is a real-time AI intelligence platform designed to monitor geopolitical agreements, detect violations, track evolving narratives, and verify events using multi-source OSINT data.

The system combines:

LLM-powered event extraction
Semantic deduplication
Multi-source verification
Narrative & propaganda tracking
Graph-based influence analysis
Confidence scoring
Geospatial + temporal visualization

Built for modern conflict intelligence workflows, AccordAI transforms noisy unstructured information into structured, explainable geopolitical insights.

🚀 Key Features
🔍 Agreement Compliance Tracking

Extract obligations from ceasefire agreements, treaties, and official statements, then compare them against real-world events.

Examples:

Missile strikes after ceasefire
Airspace violations
Cross-border escalations
🛰️ Multi-Source Verification Engine

Events are validated across:

Reuters
BBC
GDELT
RSS feeds
Telegram/X (optional)

The platform assigns verification confidence based on:

Number of corroborating sources
Source credibility
Semantic similarity
🔁 Semantic Event Deduplication

Multiple outlets often report the same event differently.

AccordAI uses embeddings + vector similarity to:

Detect duplicate events
Merge redundant reports
Reduce misinformation amplification
🧠 Narrative & Propaganda Tracking

The platform clusters semantically similar content into narratives such as:

“Iran escalation”
“Civilian targeting”
“Retaliatory response”

Track:

Narrative evolution over time
Which sources amplify which narratives
Cross-source propagation patterns
📊 Confidence Scoring

Each event receives a dynamic confidence score based on:

LLM extraction confidence
Source reliability
Multi-source agreement
Verification consistency
🌍 Interactive Dashboard

Built with Shiny + Leaflet:

Live geopolitical map
Timeline visualization
Narrative filters
Violation monitoring
Trust scoring
🕸️ Graph-Based Influence Tracking

Neo4j graph analysis enables:

Source → Narrative → Event relationships
Narrative propagation analysis
Influence ranking
Coordination pattern detection
🏗️ System Architecture
                ┌──────────────┐
                │  Data Sources│
                │ News / RSS   │
                └──────┬───────┘
                       ↓
                ┌──────────────┐
                │ Kafka Stream │
                └──────┬───────┘
                       ↓
        ┌──────────────┼──────────────┐
        ↓                              ↓
┌──────────────┐              ┌──────────────┐
│ Event Extract│              │ Narrative AI │
│ (LLM)        │              │ Clustering   │
└──────┬───────┘              └──────┬───────┘
       ↓                              ↓
┌──────────────┐              ┌──────────────┐
│ Dedup Engine │              │ Graph Builder│
└──────┬───────┘              └──────┬───────┘
       ↓                              ↓
┌──────────────┐              ┌──────────────┐
│ Verification │              │ Influence    │
│ Engine       │              │ Tracking     │
└──────┬───────┘              └──────┬───────┘
       ↓                              ↓
        └──────────────┬──────────────┘
                       ↓
                ┌──────────────┐
                │ Scoring Layer│
                └──────┬───────┘
                       ↓
                ┌──────────────┐
                │ Postgres DB  │
                └──────┬───────┘
                       ↓
                ┌──────────────┐
                │ FastAPI      │
                └──────┬───────┘
                       ↓
                ┌──────────────┐
                │ Shiny UI     │
                └──────────────┘
⚙️ Tech Stack
Layer	Technology
LLMs	OpenAI GPT-4o
Embeddings	OpenAI Embeddings / SBERT
Vector Search	FAISS
Streaming	Apache Kafka
Graph Analysis	Neo4j
Backend API	FastAPI
Database	PostgreSQL
Dashboard	Shiny + Leaflet
Data Sources	GDELT, RSS, News APIs
Infra	Docker Compose
📁 Project Structure
accord-ai/
│
├── services/
│   ├── ingestion/
│   ├── extraction/
│   ├── dedup/
│   ├── verification/
│   ├── scoring/
│   ├── narrative/
│   ├── graph/
│
├── api/
│   └── main.py
│
├── dashboard/
│   └── app.R
│
├── infra/
│   ├── docker-compose.yml
│
├── data/
├── notebooks/
├── tests/
└── README.md
⚡ Installation
1. Clone Repository
git clone https://github.com/yourname/accord-ai.git
cd accord-ai
2. Create Virtual Environment
python -m venv venv
source venv/bin/activate
3. Install Dependencies
pip install -r requirements.txt
🐳 Infrastructure Setup
Start Kafka, Neo4j, and Postgres
docker-compose up -d

Services:

Kafka → localhost:9092
Neo4j → localhost:7687
Postgres → localhost:5432
🔑 Environment Variables

Create .env

OPENAI_API_KEY=your_key
NEWS_API_KEY=your_key
POSTGRES_URL=your_db_url
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=password
▶️ Running the Pipeline
1. Start Ingestion Service
python services/ingestion/producer.py
2. Start Event Processing
python services/extraction/consumer.py
3. Start FastAPI Backend
uvicorn api.main:app --reload

API:

http://localhost:8000/events
http://localhost:8000/violations
http://localhost:8000/narratives
4. Launch Dashboard
Rscript dashboard/app.R
🧠 Core Modules
Event Extraction

Uses LLMs to transform unstructured news into structured events:

{
  "actor": "Iran",
  "action": "missile strike",
  "location": "Tel Aviv",
  "confidence": 0.82
}
Verification Engine

Cross-checks events across multiple independent sources.

Outputs:

verified/unverified
corroboration count
confidence adjustments
Narrative Clustering

Groups semantically related content into evolving narratives.

Deduplication Engine

Uses vector similarity to detect duplicate reports.

Graph Intelligence

Neo4j powers:

influence mapping
narrative propagation
source relationships
📊 Dashboard Features
🌍 Live Event Map
Geospatial conflict visualization
Confidence-based coloring
Event clustering
📈 Timeline View

Track:

escalation patterns
violation frequency
narrative spikes
🧠 Narrative Explorer

Filter events by:

narrative
source
confidence
region
🧪 Future Improvements
Real-time X/Twitter ingestion
Agentic reasoning pipelines
Automated treaty parsing
Temporal anomaly detection
Network influence scoring
Satellite imagery integration
Multilingual propaganda analysis
💼 Resume Description

Built a real-time AI geopolitical intelligence platform using Kafka, FastAPI, Neo4j, and LLMs to detect treaty violations, perform multi-source event verification, track propaganda narratives, and visualize conflict dynamics through interactive geospatial dashboards.

⚠️ Disclaimer

This project is intended for:

research
OSINT analysis
educational purposes

The system does not guarantee factual correctness and should not be used as a sole source for operational or policy decisions.

📜 License

MIT License

🤝 Contributing

Contributions are welcome.

Potential areas:

streaming optimization
multilingual NLP
graph analytics
frontend UX
source integrations
