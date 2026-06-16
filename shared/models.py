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
    event_type: str = "geopolitical_signal"
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
    cluster_id: str = ""
    event_ids: List[str] = Field(default_factory=list)
    top_entities: List[str] = Field(default_factory=list)
    source_count: int = 0
    first_seen: Optional[str] = None
    latest_seen: Optional[str] = None
    stance_distribution: Dict[str, int] = Field(default_factory=dict)
    propagation_score: float = 0.0


class InfluenceRecord(BaseModel):
    source: str
    narrative: str
    event_count: int
    alert_count: int
    average_score: float
    influence_score: float
    event_ids: List[str] = Field(default_factory=list)


class AlertSummary(BaseModel):
    event_type: str
    event_count: int
    verified_count: int
    max_score: float
    top_priority: Literal["p1", "p2", "p3"]
    event_ids: List[str] = Field(default_factory=list)


class PropagationEdge(BaseModel):
    from_event_id: str
    to_event_id: str
    from_source: str
    to_source: str
    cluster_id: str
    narrative: str
    similarity: float
    time_delta_minutes: Optional[float] = None
    propagation_type: str


class SourceStanceSummary(BaseModel):
    source: str
    cluster_id: str
    narrative: str
    stance: Literal["iran_focus", "israel_focus", "neutral", "unclear"]
    confidence: float
    event_count: int
    event_ids: List[str] = Field(default_factory=list)


class NarrativeIntelligence(BaseModel):
    clusters: List[NarrativeCluster] = Field(default_factory=list)
    propagation_edges: List[PropagationEdge] = Field(default_factory=list)
    source_stances: List[SourceStanceSummary] = Field(default_factory=list)


class ComplianceFinding(BaseModel):
    finding_id: str
    category: str
    severity: Literal["low", "medium", "high", "critical"]
    status: Literal["compliant", "watch", "likely_violation", "insufficient_evidence"]
    summary: str
    reasoning: str
    evidence_event_ids: List[str] = Field(default_factory=list)


class ComplianceReport(BaseModel):
    overall_status: Literal["compliant", "watch", "likely_violation", "insufficient_evidence"]
    confidence: float
    reasoning_mode: str
    executive_summary: str
    findings: List[ComplianceFinding] = Field(default_factory=list)
    recommended_actions: List[str] = Field(default_factory=list)


class HealthStatus(BaseModel):
    status: str
    timestamp: str = Field(default_factory=utc_now_iso)
