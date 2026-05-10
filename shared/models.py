from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List, Literal, Optional
from uuid import uuid4

from pydantic import BaseModel, Field, HttpUrl


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


class Location(BaseModel):
    name: str
    lat: float
    lon: float


class RawDocument(BaseModel):
    document_id: str = Field(default_factory=lambda: f"doc_{uuid4().hex[:12]}")
    source_type: str
    source_name: str
    title: str
    url: HttpUrl
    published_at: Optional[str] = None
    captured_at: str = Field(default_factory=utc_now_iso)
    raw_text: str
    metadata: Dict[str, Any] = Field(default_factory=dict)


class Event(BaseModel):
    event_id: str = Field(default_factory=lambda: f"evt_{uuid4().hex[:12]}")
    document_id: str
    source: str
    headline: str
    summary: str
    narrative: str
    entities: List[str] = Field(default_factory=list)
    locations: List[Location] = Field(default_factory=list)
    occurred_at: Optional[str] = None
    verification_status: Literal["unverified", "verified", "contested"] = "unverified"
    score: float = 0.0
    priority: Literal["p1", "p2", "p3"] = "p3"
    metadata: Dict[str, Any] = Field(default_factory=dict)


class NarrativeCluster(BaseModel):
    narrative: str
    event_ids: List[str] = Field(default_factory=list)
    top_entities: List[str] = Field(default_factory=list)


class HealthStatus(BaseModel):
    status: str
    timestamp: str = Field(default_factory=utc_now_iso)
