from __future__ import annotations

import hashlib
import math
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone

from shared.models import (
    Event,
    InfluenceRecord,
    NarrativeCluster,
    NarrativeIntelligence,
    PropagationEdge,
    SourceStanceSummary,
)

STOPWORDS = {
    "a",
    "an",
    "and",
    "are",
    "as",
    "at",
    "by",
    "for",
    "from",
    "in",
    "is",
    "it",
    "of",
    "on",
    "or",
    "that",
    "the",
    "to",
    "with",
}

STANCE_TERMS = {
    "iran_focus": {"iran", "tehran", "iranian", "sanctions", "retaliation", "us-iran", "hormuz"},
    "israel_focus": {"israel", "israeli", "jerusalem", "idf", "hamas", "hezbollah", "golan"},
    "neutral": {"diplomats", "monitors", "analysts", "officials", "agreement", "talks", "deal"},
}


def parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def event_text(event: Event) -> str:
    return " ".join(
        [
            event.headline,
            event.summary,
            event.narrative,
            event.event_type,
            " ".join(event.entities),
            " ".join(location.name for location in event.locations),
        ]
    ).lower()


def tokenize(text: str) -> set[str]:
    tokens = set(re.findall(r"[a-zA-Z][a-zA-Z\-]{2,}", text.lower()))
    return {token for token in tokens if token not in STOPWORDS}


def similarity(left: Event, right: Event) -> float:
    left_tokens = tokenize(event_text(left))
    right_tokens = tokenize(event_text(right))
    if not left_tokens or not right_tokens:
        return 0.0

    jaccard = len(left_tokens & right_tokens) / len(left_tokens | right_tokens)
    narrative_boost = 0.2 if left.narrative == right.narrative else 0.0
    type_boost = 0.1 if left.event_type == right.event_type else 0.0
    entity_overlap = len(set(left.entities) & set(right.entities))
    entity_boost = min(entity_overlap * 0.08, 0.16)
    return round(min(jaccard + narrative_boost + type_boost + entity_boost, 1.0), 3)


def cluster_id_for(narrative: str, event_ids: list[str]) -> str:
    seed = f"{narrative}:{','.join(sorted(event_ids))}"
    return f"nar_{hashlib.sha1(seed.encode('utf-8')).hexdigest()[:10]}"


def infer_stance(event: Event) -> tuple[str, float]:
    text = event_text(event)
    tokens = tokenize(text)
    scores = {
        stance: len(tokens & terms)
        for stance, terms in STANCE_TERMS.items()
    }

    if event.event_type == "sanctions_signal":
        scores["iran_focus"] += 1
    if event.narrative == "ceasefire monitoring" or event.event_type == "ceasefire_violation":
        scores["israel_focus"] += 1
    if any(term in text for term in ["state media", "propaganda", "disinformation", "influence campaign"]):
        scores["neutral"] += 1

    if not scores or max(scores.values()) == 0:
        return "unclear", 0.35

    ranked = sorted(scores.items(), key=lambda item: item[1], reverse=True)
    if len(ranked) > 1 and ranked[0][1] == ranked[1][1]:
        iran_position = min([pos for token in ["iran", "tehran", "iranian"] if (pos := text.find(token)) >= 0], default=math.inf)
        israel_position = min([pos for token in ["israel", "jerusalem", "israeli"] if (pos := text.find(token)) >= 0], default=math.inf)
        if iran_position < israel_position:
            return "iran_focus", 0.58
        if israel_position < iran_position:
            return "israel_focus", 0.58
        return "neutral", 0.5

    stance = ranked[0][0]
    confidence = min(0.45 + (ranked[0][1] * 0.15), 0.9)
    return stance, round(confidence, 2)


def semantic_cluster_events(events: list[Event], threshold: float = 0.34) -> dict[str, list[Event]]:
    clusters: list[list[Event]] = []
    for event in events:
        best_idx = None
        best_score = 0.0
        for idx, cluster in enumerate(clusters):
            score = max(similarity(event, existing) for existing in cluster)
            if score > best_score:
                best_idx = idx
                best_score = score

        if best_idx is not None and best_score >= threshold:
            clusters[best_idx].append(event)
        else:
            clusters.append([event])

    result: dict[str, list[Event]] = {}
    for cluster in clusters:
        narrative = Counter(event.narrative for event in cluster).most_common(1)[0][0]
        cluster_id = cluster_id_for(narrative, [event.event_id for event in cluster])
        result[cluster_id] = cluster
    return result


def build_cluster(cluster_id: str, group: list[Event]) -> NarrativeCluster:
    narrative = Counter(event.narrative for event in group).most_common(1)[0][0]
    entity_counts = Counter(entity for event in group for entity in event.entities)
    times = [parse_time(event.occurred_at) for event in group]
    times = [time for time in times if time is not None]
    stance_distribution = Counter(infer_stance(event)[0] for event in group)
    source_count = len({event.source for event in group})
    alert_count = sum(event.event_type in {"ceasefire_violation", "propaganda_alert"} for event in group)
    propagation_score = round((len(group) * 0.45) + (source_count * 0.25) + (alert_count * 0.2), 2)

    return NarrativeCluster(
        narrative=narrative,
        cluster_id=cluster_id,
        event_ids=[event.event_id for event in group],
        top_entities=[entity for entity, _ in entity_counts.most_common(5)],
        source_count=source_count,
        first_seen=min(times).isoformat() if times else None,
        latest_seen=max(times).isoformat() if times else None,
        stance_distribution=dict(stance_distribution),
        propagation_score=propagation_score,
    )


def build_propagation_edges(cluster_id: str, group: list[Event]) -> list[PropagationEdge]:
    edges: list[PropagationEdge] = []
    ordered = sorted(
        group,
        key=lambda event: parse_time(event.occurred_at) or datetime.max.replace(tzinfo=timezone.utc),
    )
    for idx, current in enumerate(ordered):
        current_time = parse_time(current.occurred_at)
        candidates = ordered[:idx]
        if not candidates:
            continue

        scored = sorted(
            ((previous, similarity(previous, current)) for previous in candidates if previous.source != current.source),
            key=lambda item: item[1],
            reverse=True,
        )
        if not scored or scored[0][1] < 0.25:
            continue

        previous, score = scored[0]
        previous_time = parse_time(previous.occurred_at)
        delta = None
        if current_time is not None and previous_time is not None:
            delta = round((current_time - previous_time).total_seconds() / 60, 1)

        edges.append(
            PropagationEdge(
                from_event_id=previous.event_id,
                to_event_id=current.event_id,
                from_source=previous.source,
                to_source=current.source,
                cluster_id=cluster_id,
                narrative=Counter(event.narrative for event in group).most_common(1)[0][0],
                similarity=score,
                time_delta_minutes=delta,
                propagation_type="time_ordered_amplification" if delta is not None else "similarity_link",
            )
        )
    return edges


def build_source_stances(cluster_id: str, group: list[Event]) -> list[SourceStanceSummary]:
    narrative = Counter(event.narrative for event in group).most_common(1)[0][0]
    grouped: dict[str, list[Event]] = defaultdict(list)
    for event in group:
        grouped[event.source].append(event)

    summaries: list[SourceStanceSummary] = []
    for source, events in grouped.items():
        stances = [infer_stance(event) for event in events]
        stance_counts = Counter(stance for stance, _ in stances)
        stance = stance_counts.most_common(1)[0][0]
        confidence = round(sum(conf for _, conf in stances) / len(stances), 2)
        summaries.append(
            SourceStanceSummary(
                source=source,
                cluster_id=cluster_id,
                narrative=narrative,
                stance=stance,
                confidence=confidence,
                event_count=len(events),
                event_ids=[event.event_id for event in events],
            )
        )
    return summaries


def build_narrative_intelligence(events: list[Event]) -> NarrativeIntelligence:
    clustered = semantic_cluster_events(events)
    clusters = [build_cluster(cluster_id, group) for cluster_id, group in clustered.items()]
    edges = [
        edge
        for cluster_id, group in clustered.items()
        for edge in build_propagation_edges(cluster_id, group)
    ]
    stances = [
        stance
        for cluster_id, group in clustered.items()
        for stance in build_source_stances(cluster_id, group)
    ]

    clusters = sorted(clusters, key=lambda cluster: cluster.propagation_score, reverse=True)
    edges = sorted(edges, key=lambda edge: edge.similarity, reverse=True)
    stances = sorted(stances, key=lambda stance: (stance.cluster_id, -stance.confidence, stance.source))
    return NarrativeIntelligence(clusters=clusters, propagation_edges=edges, source_stances=stances)


def cluster_narratives(events: list[Event]) -> list[NarrativeCluster]:
    return build_narrative_intelligence(events).clusters


def calculate_influence(events: list[Event]) -> list[InfluenceRecord]:
    intelligence = build_narrative_intelligence(events)
    cluster_by_event = {
        event_id: cluster
        for cluster in intelligence.clusters
        for event_id in cluster.event_ids
    }

    grouped: dict[tuple[str, str, str], list[Event]] = defaultdict(list)
    for event in events:
        cluster = cluster_by_event.get(event.event_id)
        cluster_id = cluster.cluster_id if cluster else "nar_unclustered"
        grouped[(event.source, event.narrative, cluster_id)].append(event)

    edge_counts = Counter(edge.from_source for edge in intelligence.propagation_edges)
    records: list[InfluenceRecord] = []
    for (source, narrative, cluster_id), group in grouped.items():
        alert_count = sum(event.event_type in {"ceasefire_violation", "propaganda_alert"} for event in group)
        average_score = round(sum(event.score for event in group) / len(group), 2)
        propagation_bonus = min(edge_counts[source] * 0.2, 1.0)
        influence_score = round((len(group) * 0.50) + (alert_count * 0.30) + (average_score * 0.15) + propagation_bonus, 2)

        records.append(
            InfluenceRecord(
                source=source,
                narrative=narrative,
                event_count=len(group),
                alert_count=alert_count,
                average_score=average_score,
                influence_score=influence_score,
                event_ids=[event.event_id for event in group],
            )
        )

    return sorted(records, key=lambda record: record.influence_score, reverse=True)
