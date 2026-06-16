from __future__ import annotations

import unittest

from services.alerts.service import summarize_alerts
from services.compliance.service import assess_compliance
from services.extraction.extractor import extract_event
from services.narrative.service import build_narrative_intelligence, calculate_influence, cluster_narratives
from services.scoring.service import score_events
from services.verification.service import verify_events
from services.violation.service import classify_events
from shared.models import RawDocument
from shared.settings import settings


class Phase2StructuredIntelligenceTest(unittest.TestCase):
    def build_events(self):
        settings.extraction_mode = "heuristic"
        documents = [
            RawDocument(
                source_type="seed",
                source_name="AP",
                title="Observers report ceasefire violation after overnight shelling",
                url="https://example.com/ap",
                raw_text="A ceasefire was violated after overnight shelling near Jerusalem.",
            ),
            RawDocument(
                source_type="seed",
                source_name="Al Jazeera",
                title="State media propaganda campaign amplifies false battlefield claims",
                url="https://example.com/aj",
                raw_text="Analysts warned that a state media propaganda and disinformation campaign amplified false claims.",
            ),
            RawDocument(
                source_type="seed",
                source_name="BBC",
                title="Sanctions pressure grows after regional escalation",
                url="https://example.com/bbc",
                raw_text="Sanctions pressure increased after Iran and Israel exchanged warnings.",
            ),
            RawDocument(
                source_type="seed",
                source_name="Reuters",
                title="Israel and Iran trade warnings after ceasefire breach",
                url="https://example.com/reuters",
                raw_text="Israel and Iran traded warnings after monitors reported a ceasefire breach near Jerusalem.",
            ),
        ]

        extracted = [extract_event(document) for document in documents]
        classified = classify_events(extracted)
        verified = verify_events(classified)
        return score_events(verified)

    def test_phase2_event_types_are_classified(self):
        events = self.build_events()
        event_types = {event.event_type for event in events}

        self.assertIn("ceasefire_violation", event_types)
        self.assertIn("propaganda_alert", event_types)
        self.assertIn("sanctions_signal", event_types)

    def test_alert_summaries_are_generated(self):
        events = self.build_events()
        summaries = summarize_alerts(events)
        summary_types = {summary.event_type for summary in summaries}

        self.assertEqual(len(summaries), 3)
        self.assertIn("ceasefire_violation", summary_types)
        self.assertIn("propaganda_alert", summary_types)
        self.assertIn("sanctions_signal", summary_types)

    def test_narrative_and_influence_records_are_generated(self):
        events = self.build_events()
        narratives = cluster_narratives(events)
        influence = calculate_influence(events)

        self.assertGreaterEqual(len(narratives), 3)
        self.assertGreaterEqual(len(influence), 3)
        self.assertEqual(influence[0].alert_count, 1)

    def test_narrative_intelligence_has_clusters_stances_and_edges(self):
        events = self.build_events()
        intelligence = build_narrative_intelligence(events)

        self.assertGreaterEqual(len(intelligence.clusters), 1)
        self.assertTrue(all(cluster.cluster_id.startswith("nar_") for cluster in intelligence.clusters))
        self.assertGreaterEqual(len(intelligence.source_stances), 1)
        self.assertGreaterEqual(len(intelligence.propagation_edges), 1)

    def test_compliance_report_is_generated_from_alerts_and_narratives(self):
        events = self.build_events()
        intelligence = build_narrative_intelligence(events)
        report = assess_compliance(events, intelligence)

        self.assertIn(report.overall_status, {"watch", "likely_violation"})
        self.assertGreaterEqual(report.confidence, 0.45)
        self.assertGreaterEqual(len(report.findings), 3)
        self.assertIn("ceasefire_compliance", {finding.category for finding in report.findings})


if __name__ == "__main__":
    unittest.main()
