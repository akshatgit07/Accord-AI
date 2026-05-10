from neo4j import GraphDatabase

driver = GraphDatabase.driver("bolt://localhost:7687", auth=("neo4j", "password"))

def add_event_graph(event):
    with driver.session() as session:
        session.run("""
        MERGE (s:Source {name: $source})
        MERGE (n:Narrative {name: $narrative})
        MERGE (e:Event {id: $id})
        
        MERGE (s)-[:PUBLISHES]->(e)
        MERGE (e)-[:BELONGS_TO]->(n)
        """, 
        source=event["source"],
        narrative=event["narrative"],
        id=event["id"]
        )
