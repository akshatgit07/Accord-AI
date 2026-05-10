from __future__ import annotations

from shared.models import Event, Location, RawDocument

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


def extract_event(document: RawDocument) -> Event:
    headline = document.title
    raw_text = document.raw_text.lower()
    combined_text = f"{headline} {document.raw_text}".lower()

    narrative = "general monitoring"
    if "iran" in raw_text or "israel" in raw_text:
        narrative = "regional escalation"
    elif "sanction" in raw_text:
        narrative = "sanctions pressure"

    entities = []
    for candidate in ["Iran", "Israel", "United States", "Russia", "China"]:
        if candidate.lower() in raw_text:
            entities.append(candidate)

    summary = f"{headline}: extracted from {document.source_name} for analyst review."
    locations = infer_locations(combined_text)

    return Event(
        document_id=document.document_id,
        source=document.source_name,
        headline=headline,
        summary=summary,
        narrative=narrative,
        entities=entities,
        locations=locations,
        occurred_at=document.published_at,
        metadata={"extraction_mode": "heuristic_baseline"},
    )
