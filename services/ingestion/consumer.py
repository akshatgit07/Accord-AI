from kafka import KafkaConsumer
import json

consumer = KafkaConsumer(
    "raw-events",
    bootstrap_servers='localhost:9092',
    value_deserializer=lambda x: json.loads(x.decode('utf-8'))
)

for msg in consumer:
    article = msg.value
    # send to extraction → rest of pipeline
