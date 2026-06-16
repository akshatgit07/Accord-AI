CREATE TABLE IF NOT EXISTS raw_documents (
  document_id TEXT PRIMARY KEY,
  source_type TEXT NOT NULL,
  source_name TEXT NOT NULL,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  published_at TEXT,
  captured_at TEXT NOT NULL,
  payload JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS events (
  event_id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL,
  source TEXT NOT NULL,
  event_type TEXT NOT NULL,
  narrative TEXT NOT NULL,
  verification_status TEXT NOT NULL,
  priority TEXT NOT NULL,
  score DOUBLE PRECISION NOT NULL,
  occurred_at TEXT,
  payload JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_events_narrative ON events (narrative);
CREATE INDEX IF NOT EXISTS idx_events_event_type ON events (event_type);
CREATE INDEX IF NOT EXISTS idx_events_source ON events (source);
CREATE INDEX IF NOT EXISTS idx_events_priority ON events (priority);
