from __future__ import annotations

from collections import defaultdict

from shared.models import AlertSummary, Event

ALERT_EVENT_TYPES = {"ceasefire_violation", "propaganda_alert", "sanctions_signal"}
PRIORITY_RANK = {"p1": 3, "p2": 2, "p3": 1}


def summarize_alerts(events: list[Event]) -> list[AlertSummary]:
    grouped: dict[str, list[Event]] = defaultdict(list)
    for event in events:
        if event.event_type in ALERT_EVENT_TYPES:
            grouped[event.event_type].append(event)

    summaries: list[AlertSummary] = []
    for event_type, group in grouped.items():
        top_priority = sorted(
            (event.priority for event in group),
            key=lambda priority: PRIORITY_RANK.get(priority, 0),
            reverse=True,
        )[0]

        summaries.append(
            AlertSummary(
                event_type=event_type,
                event_count=len(group),
                verified_count=sum(event.verification_status == "verified" for event in group),
                max_score=round(max(event.score for event in group), 2),
                top_priority=top_priority,
                event_ids=[event.event_id for event in group],
            )
        )

    return sorted(
        summaries,
        key=lambda summary: (PRIORITY_RANK.get(summary.top_priority, 0), summary.max_score, summary.event_count),
        reverse=True,
    )
