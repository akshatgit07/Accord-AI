from __future__ import annotations

from shared.models import Event


def classify_event_type(event: Event) -> Event:
    bag = " ".join(
        [
            event.headline.lower(),
            event.summary.lower(),
            event.narrative.lower(),
            " ".join(entity.lower() for entity in event.entities),
        ]
    )

    if "ceasefire" in bag and any(term in bag for term in ["violation", "violated", "strike", "shelling", "attack", "breach"]):
        event.event_type = "ceasefire_violation"
        event.metadata["alert_reason"] = "ceasefire language paired with a hostile incident term"
        return event

    if any(term in bag for term in ["propaganda", "disinformation", "misinformation", "influence campaign", "state media"]):
        event.event_type = "propaganda_alert"
        event.metadata["alert_reason"] = "information warfare or propaganda framing detected"
        return event

    if "sanction" in bag:
        event.event_type = "sanctions_signal"
        event.metadata["alert_reason"] = "sanctions-related language detected"
        return event

    event.event_type = "geopolitical_signal"
    event.metadata["alert_reason"] = "general geopolitical monitoring signal"
    return event


def classify_events(events: list[Event]) -> list[Event]:
    return [classify_event_type(event) for event in events]
