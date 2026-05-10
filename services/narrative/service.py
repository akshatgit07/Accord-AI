from __future__ import annotations

from collections import Counter, defaultdict

from shared.models import Event, NarrativeCluster


def cluster_narratives(events: list[Event]) -> list[NarrativeCluster]:
    grouped: dict[str, list[Event]] = defaultdict(list)
    for event in events:
        grouped[event.narrative].append(event)

    clusters: list[NarrativeCluster] = []
    for narrative, group in grouped.items():
        entity_counts = Counter(entity for event in group for entity in event.entities)
        clusters.append(
            NarrativeCluster(
                narrative=narrative,
                event_ids=[event.event_id for event in group],
                top_entities=[entity for entity, _ in entity_counts.most_common(5)],
            )
        )
    return clusters
