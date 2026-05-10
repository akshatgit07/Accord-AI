# Kafka notes

- Topic 1: `raw-events` for normalized source documents.
- Topic 2: `structured-events` for extracted events.
- Keep document payloads immutable once published.
- Push analyst feedback through a separate topic when the review loop exists.
