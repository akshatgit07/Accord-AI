from __future__ import annotations

from shared.models import Event


def score_event(event: Event) -> Event:
    score = 0.25
    score += min(len(event.entities) * 0.1, 0.3)

    if event.verification_status == "verified":
        score += 0.25

    if event.narrative in {"regional escalation", "sanctions pressure"}:
        score += 0.15

    event.score = round(min(score, 0.99), 2)

    if event.score >= 0.75:
        event.priority = "p1"
    elif event.score >= 0.5:
        event.priority = "p2"
    else:
        event.priority = "p3"

    return event


def score_events(events: list[Event]) -> list[Event]:
    return [score_event(event) for event in events]
