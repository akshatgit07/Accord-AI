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
                MERGE (s)-[:PUBLISHES]->(e)
                MERGE (e)-[:BELONGS_TO]->(n)
                """,
                source=event.source,
                narrative=event.narrative,
                event_id=event.event_id,
                headline=event.headline,
            )
    finally:
        driver.close()
