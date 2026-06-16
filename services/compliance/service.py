from __future__ import annotations

from collections import Counter
from hashlib import sha1

from shared.models import ComplianceFinding, ComplianceReport, Event, NarrativeIntelligence

SEVERITY_RANK = {"low": 1, "medium": 2, "high": 3, "critical": 4}
STATUS_RANK = {
    "compliant": 1,
    "insufficient_evidence": 2,
    "watch": 3,
    "likely_violation": 4,
}


def finding_id(category: str, event_ids: list[str]) -> str:
    digest = sha1(f"{category}:{','.join(sorted(event_ids))}".encode("utf-8")).hexdigest()[:10]
    return f"cmp_{digest}"


def make_finding(
    category: str,
    severity: str,
    status: str,
    summary: str,
    reasoning: str,
    events: list[Event],
) -> ComplianceFinding:
    return ComplianceFinding(
        finding_id=finding_id(category, [event.event_id for event in events]),
        category=category,
        severity=severity,  # type: ignore[arg-type]
        status=status,  # type: ignore[arg-type]
        summary=summary,
        reasoning=reasoning,
        evidence_event_ids=[event.event_id for event in events],
    )


def assess_compliance(events: list[Event], intelligence: NarrativeIntelligence) -> ComplianceReport:
    findings: list[ComplianceFinding] = []

    ceasefire_events = [event for event in events if event.event_type == "ceasefire_violation"]
    propaganda_events = [event for event in events if event.event_type == "propaganda_alert"]
    sanctions_events = [event for event in events if event.event_type == "sanctions_signal"]

    if ceasefire_events:
        verified = [event for event in ceasefire_events if event.verification_status == "verified"]
        status = "likely_violation" if verified else "watch"
        severity = "high" if len(ceasefire_events) >= 2 else "medium"
        findings.append(
            make_finding(
                "ceasefire_compliance",
                severity,
                status,
                f"{len(ceasefire_events)} ceasefire breach signal(s) detected.",
                "Ceasefire violation events were extracted and scored. Verified or repeated signals raise the compliance risk.",
                ceasefire_events,
            )
        )

    if propaganda_events:
        source_count = len({event.source for event in propaganda_events})
        status = "watch" if source_count < 3 else "likely_violation"
        findings.append(
            make_finding(
                "information_integrity",
                "medium" if source_count < 3 else "high",
                status,
                f"{len(propaganda_events)} propaganda or disinformation signal(s) across {source_count} source(s).",
                "The system detected propaganda/disinformation framing. Multi-source recurrence increases coordination risk.",
                propaganda_events,
            )
        )

    if sanctions_events:
        findings.append(
            make_finding(
                "sanctions_pressure",
                "medium",
                "watch",
                f"{len(sanctions_events)} sanctions-related signal(s) detected.",
                "Sanctions signals do not directly imply agreement violation, but they indicate compliance pressure and enforcement activity.",
                sanctions_events,
            )
        )

    high_propagation_clusters = [
        cluster for cluster in intelligence.clusters if cluster.propagation_score >= 4.0 or cluster.source_count >= 4
    ]
    if high_propagation_clusters:
        event_ids = {event_id for cluster in high_propagation_clusters for event_id in cluster.event_ids}
        evidence = [event for event in events if event.event_id in event_ids]
        findings.append(
            make_finding(
                "narrative_propagation",
                "medium",
                "watch",
                f"{len(high_propagation_clusters)} narrative cluster(s) show broad source propagation.",
                "The propagation graph links similar claims across sources. This indicates amplification, not proof of coordination.",
                evidence,
            )
        )

    if not findings:
        findings.append(
            ComplianceFinding(
                finding_id="cmp_no_findings",
                category="general_compliance",
                severity="low",
                status="insufficient_evidence",
                summary="No compliance-relevant signals detected.",
                reasoning="The current event set does not contain enough compliance-specific evidence for a finding.",
                evidence_event_ids=[],
            )
        )

    top_status = max(findings, key=lambda finding: STATUS_RANK[finding.status]).status
    confidence = min(0.45 + (len(events) * 0.01) + (len(intelligence.propagation_edges) * 0.01), 0.88)
    categories = Counter(finding.category for finding in findings)

    recommended_actions = [
        "Review evidence events behind high-severity findings.",
        "Scrape article-level URLs to improve timestamps and propagation ordering.",
        "Run human analyst review before treating focus/propagation signals as attribution.",
    ]
    if ceasefire_events:
        recommended_actions.insert(0, "Escalate ceasefire breach signals for source corroboration.")
    if propaganda_events:
        recommended_actions.insert(0, "Compare propaganda alerts against OSINT fact-check sources.")

    return ComplianceReport(
        overall_status=top_status,
        confidence=round(confidence, 2),
        reasoning_mode="heuristic_compliance_reasoning",
        executive_summary=(
            f"Compliance posture is {top_status.replace('_', ' ')} with {len(findings)} finding(s). "
            f"Dominant categories: {', '.join(category for category, _ in categories.most_common(3))}. "
            "This is analyst-support reasoning, not a legal determination."
        ),
        findings=sorted(findings, key=lambda finding: (STATUS_RANK[finding.status], SEVERITY_RANK[finding.severity]), reverse=True),
        recommended_actions=recommended_actions,
    )
