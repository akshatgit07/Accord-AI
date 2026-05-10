from __future__ import annotations

from collections import Counter

from shared.models import Event


def verify_events(events: list[Event]) -> list[Event]:
    narrative_counts = Counter(event.narrative for event in events)

    for event in events:
        if narrative_counts[event.narrative] >= 2:
            event.verification_status = "verified"
            event.metadata["verification_reason"] = "multiple related events observed"
        else:
            event.verification_status = "unverified"
            event.metadata["verification_reason"] = "single-source or isolated signal"
    return events
