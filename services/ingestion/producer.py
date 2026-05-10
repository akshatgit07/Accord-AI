from kafka import KafkaProducer
import requests, json

producer = KafkaProducer(
    bootstrap_servers='localhost:9092',
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

def fetch_gdelt():
    url = "https://api.gdeltproject.org/api/v2/doc/doc?query=iran+israel&format=json"
    data = requests.get(url).json()
    
    for article in data["articles"][:10]:
        producer.send("raw-events", article)

fetch_gdelt()
