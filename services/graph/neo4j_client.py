from __future__ import annotations

from neo4j import GraphDatabase

from shared.models import Event
from shared.settings import settings


def get_driver():
    return GraphDatabase.driver(
        settings.neo4j_uri,
        auth=(settings.neo4j_user, settings.neo4j_password),
    )


def add_event_graph(event: Event) -> None:
    driver = get_driver()
    try:
        with driver.session() as session:
            session.run(
                """
                MERGE (s:Source {name: $source})
                MERGE (n:Narrative {name: $narrative})
                MERGE (e:Event {id: $event_id})
                SET e.headline = $headline
                SET e.event_type = $event_type
                SET e.score = $score
                SET e.priority = $priority
                MERGE (s)-[:PUBLISHES]->(e)
                MERGE (e)-[:BELONGS_TO]->(n)
                """,
                source=event.source,
                narrative=event.narrative,
                event_id=event.event_id,
                headline=event.headline,
                event_type=event.event_type,
                score=event.score,
                priority=event.priority,
            )
    finally:
        driver.close()


def source_influence_query() -> str:
    return """
    MATCH (s:Source)-[:PUBLISHES]->(e:Event)-[:BELONGS_TO]->(n:Narrative)
    RETURN s.name AS source,
           n.name AS narrative,
           count(e) AS event_count,
           sum(CASE WHEN e.event_type IN ['ceasefire_violation', 'propaganda_alert'] THEN 1 ELSE 0 END) AS alert_count,
           avg(e.score) AS average_score
    ORDER BY event_count DESC, alert_count DESC
    """
