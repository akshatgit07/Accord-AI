from __future__ import annotations

from collections import defaultdict

from shared.models import Event


def deduplicate_events(events: list[Event]) -> list[Event]:
    seen_by_key: dict[tuple[str, str], Event] = {}
    duplicates = defaultdict(list)

    for event in events:
        key = (event.headline.strip().lower(), event.narrative.strip().lower())
        if key in seen_by_key:
            duplicates[seen_by_key[key].event_id].append(event.event_id)
            continue
        seen_by_key[key] = event

    deduped = list(seen_by_key.values())
    for event in deduped:
        if duplicates[event.event_id]:
            event.metadata["merged_event_ids"] = duplicates[event.event_id]
    return deduped
