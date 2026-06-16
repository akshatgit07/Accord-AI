from __future__ import annotations

import json

import requests

from shared.models import Event, Location, RawDocument
from shared.settings import settings

PLACE_HINTS = {
    "tehran": Location(name="Tehran", lat=35.6892, lon=51.3890),
    "jerusalem": Location(name="Jerusalem", lat=31.7683, lon=35.2137),
    "washington": Location(name="Washington, DC", lat=38.9072, lon=-77.0369),
    "moscow": Location(name="Moscow", lat=55.7558, lon=37.6173),
    "beijing": Location(name="Beijing", lat=39.9042, lon=116.4074),
}

COUNTRY_FALLBACKS = {
    "iran": Location(name="Tehran", lat=35.6892, lon=51.3890),
    "israel": Location(name="Jerusalem", lat=31.7683, lon=35.2137),
    "united states": Location(name="Washington, DC", lat=38.9072, lon=-77.0369),
    "russia": Location(name="Moscow", lat=55.7558, lon=37.6173),
    "china": Location(name="Beijing", lat=39.9042, lon=116.4074),
}

EVENT_EXTRACTION_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "headline": {"type": "string"},
        "summary": {"type": "string"},
        "event_type": {
            "type": "string",
            "enum": [
                "geopolitical_signal",
                "sanctions_signal",
                "ceasefire_violation",
                "propaganda_alert",
            ],
        },
        "narrative": {
            "type": "string",
            "enum": [
                "regional escalation",
                "ceasefire monitoring",
                "information warfare",
                "sanctions pressure",
                "general monitoring",
            ],
        },
        "entities": {"type": "array", "items": {"type": "string"}},
        "locations": {
            "type": "array",
            "items": {
                "type": "object",
                "additionalProperties": False,
                "properties": {
                    "name": {"type": "string"},
                    "lat": {"type": "number"},
                    "lon": {"type": "number"},
                },
                "required": ["name", "lat", "lon"],
            },
        },
        "alert_reason": {"type": "string"},
    },
    "required": ["headline", "summary", "event_type", "narrative", "entities", "locations", "alert_reason"],
}


def infer_locations(text: str) -> list[Location]:
    locations: list[Location] = []
    seen_names = set()

    for hint, location in PLACE_HINTS.items():
        if hint in text and location.name not in seen_names:
            locations.append(location)
            seen_names.add(location.name)

    if locations:
        return locations

    for hint, location in COUNTRY_FALLBACKS.items():
        if hint in text and location.name not in seen_names:
            locations.append(location)
            seen_names.add(location.name)

    return locations[:1]


def extract_event_heuristic(document: RawDocument, extraction_error: str | None = None) -> Event:
    headline = document.title
    raw_text = document.raw_text.lower()
    combined_text = f"{headline} {document.raw_text}".lower()

    narrative = "general monitoring"
    event_type = "geopolitical_signal"
    if "ceasefire" in combined_text and any(term in combined_text for term in ["violation", "violated", "strike", "shelling", "breach", "attack"]):
        narrative = "ceasefire monitoring"
        event_type = "ceasefire_violation"
    elif any(term in combined_text for term in ["propaganda", "disinformation", "misinformation", "influence campaign", "state media"]):
        narrative = "information warfare"
        event_type = "propaganda_alert"
    elif "iran" in raw_text or "israel" in raw_text:
        narrative = "regional escalation"
    elif "sanction" in raw_text:
        narrative = "sanctions pressure"
        event_type = "sanctions_signal"

    entities = []
    for candidate in ["Iran", "Israel", "United States", "Russia", "China"]:
        if candidate.lower() in raw_text:
            entities.append(candidate)

    summary = f"{headline}: extracted from {document.source_name} for analyst review."
    locations = infer_locations(combined_text)

    metadata = {"extraction_mode": "heuristic_baseline"}
    if extraction_error:
        metadata["llm_extraction_error"] = extraction_error[:400]

    return Event(
        document_id=document.document_id,
        source=document.source_name,
        headline=headline,
        summary=summary,
        event_type=event_type,
        narrative=narrative,
        entities=entities,
        locations=locations,
        occurred_at=document.published_at,
        metadata=metadata,
    )


def parse_response_text(payload: dict) -> str:
    if isinstance(payload.get("output_text"), str):
        return payload["output_text"]

    for item in payload.get("output", []):
        for content in item.get("content", []):
            if isinstance(content.get("text"), str):
                return content["text"]

    raise ValueError("OpenAI response did not include text output")


def extract_event_with_openai(document: RawDocument) -> Event:
    if not settings.openai_api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured")

    response = requests.post(
        "https://api.openai.com/v1/responses",
        headers={
            "Authorization": f"Bearer {settings.openai_api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": settings.openai_model,
            "input": [
                {
                    "role": "system",
                    "content": (
                        "You extract analyst-ready geopolitical intelligence events. "
                        "Return only facts supported by the provided document. "
                        "Use concise neutral language. If a location is implied but not exact, "
                        "use the nearest capital or known city with reasonable coordinates. "
                        "Use the narrative field as a compact category, not a sentence."
                    ),
                },
                {
                    "role": "user",
                    "content": json.dumps(
                        {
                            "source": document.source_name,
                            "title": document.title,
                            "published_at": document.published_at,
                            "raw_text": document.raw_text,
                        }
                    ),
                },
            ],
            "text": {
                "format": {
                    "type": "json_schema",
                    "name": "accord_event_extraction",
                    "strict": True,
                    "schema": EVENT_EXTRACTION_SCHEMA,
                }
            },
        },
        timeout=30,
    )
    response.raise_for_status()

    extracted = json.loads(parse_response_text(response.json()))
    locations = [Location(**location) for location in extracted.get("locations", [])]
    if not locations:
        locations = infer_locations(f"{document.title} {document.raw_text}".lower())

    return Event(
        document_id=document.document_id,
        source=document.source_name,
        headline=extracted["headline"] or document.title,
        summary=extracted["summary"],
        event_type=extracted["event_type"],
        narrative=extracted["narrative"],
        entities=extracted.get("entities", []),
        locations=locations,
        occurred_at=document.published_at,
        metadata={
            "extraction_mode": "openai_structured",
            "openai_model": settings.openai_model,
            "alert_reason": extracted.get("alert_reason", "LLM extracted structured event"),
        },
    )


def extract_event(document: RawDocument) -> Event:
    if settings.extraction_mode in {"auto", "llm"} and settings.openai_api_key:
        try:
            return extract_event_with_openai(document)
        except Exception as exc:
            return extract_event_heuristic(document, extraction_error=str(exc))

    return extract_event_heuristic(document)
